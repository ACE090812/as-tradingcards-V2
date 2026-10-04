--[[ v2 tables + small shared helpers (Series 2, seasons, unlocks) ]]
V2 = {}

CreateThread(function()
    local q = MySQL.query.await
    q([[CREATE TABLE IF NOT EXISTS `ascard_decks` (
        `box_id` VARCHAR(40) NOT NULL, `serial` VARCHAR(64) NOT NULL, `card_id` VARCHAR(64) NOT NULL,
        `item` VARCHAR(64) NOT NULL, `metadata` LONGTEXT NOT NULL,
        PRIMARY KEY (`box_id`, `serial`)
    )]])
    q([[CREATE TABLE IF NOT EXISTS `ascard_unlocks` (
        `identifier` VARCHAR(64) NOT NULL, `kind` VARCHAR(16) NOT NULL, `k` VARCHAR(32) NOT NULL,
        PRIMARY KEY (`identifier`, `kind`, `k`)
    )]])
    q([[CREATE TABLE IF NOT EXISTS `ascard_prefs` (
        `identifier` VARCHAR(64) NOT NULL, `mat` VARCHAR(32) NULL,
        PRIMARY KEY (`identifier`)
    )]])
    q([[CREATE TABLE IF NOT EXISTS `ascard_rank` (
        `season` INT NOT NULL, `identifier` VARCHAR(64) NOT NULL, `name` VARCHAR(80) NOT NULL,
        `points` INT NOT NULL DEFAULT 0, `wins` INT NOT NULL DEFAULT 0, `losses` INT NOT NULL DEFAULT 0, `draws` INT NOT NULL DEFAULT 0,
        `updated` INT NOT NULL DEFAULT 0,
        PRIMARY KEY (`season`, `identifier`), KEY `pts` (`season`, `points`)
    )]])
    q([[CREATE TABLE IF NOT EXISTS `ascard_matches` (
        `id` INT NOT NULL AUTO_INCREMENT, `season` INT NOT NULL, `at` INT NOT NULL,
        `p1` VARCHAR(64) NOT NULL, `p2` VARCHAR(64) NOT NULL, `n1` VARCHAR(80) NULL, `n2` VARCHAR(80) NULL,
        `winner` VARCHAR(64) NULL, `wager` INT NOT NULL DEFAULT 0, `life1` INT NULL, `life2` INT NULL, `why` VARCHAR(16) NULL,
        PRIMARY KEY (`id`), KEY `pair` (`p1`, `p2`, `at`)
    )]])
    q([[CREATE TABLE IF NOT EXISTS `ascard_tables` (
        `id` INT NOT NULL AUTO_INCREMENT, `owner` VARCHAR(64) NOT NULL, `owner_name` VARCHAR(80) NULL,
        `x` DOUBLE NOT NULL, `y` DOUBLE NOT NULL, `z` DOUBLE NOT NULL, `h` DOUBLE NOT NULL, `placed_at` INT NOT NULL,
        PRIMARY KEY (`id`)
    )]])
    q([[CREATE TABLE IF NOT EXISTS `ascard_trader_stock` (
        `id` INT NOT NULL AUTO_INCREMENT, `item` VARCHAR(64) NOT NULL, `card_id` VARCHAR(64) NOT NULL,
        `type` VARCHAR(16) NOT NULL, `metadata` LONGTEXT NOT NULL, `added_at` INT NOT NULL,
        PRIMARY KEY (`id`), KEY `type` (`type`)
    )]])
    q([[CREATE TABLE IF NOT EXISTS `ascard_trader_swaps` (
        `identifier` VARCHAR(64) NOT NULL, `day` INT NOT NULL, `n` INT NOT NULL DEFAULT 0,
        PRIMARY KEY (`identifier`, `day`)
    )]])
    q([[CREATE TABLE IF NOT EXISTS `ascard_wants_done` (
        `identifier` VARCHAR(64) NOT NULL, `day` INT NOT NULL, `want` VARCHAR(24) NOT NULL,
        PRIMARY KEY (`identifier`, `day`, `want`)
    )]])
    q([[CREATE TABLE IF NOT EXISTS `ascard_shop_stock` (
        `id` INT NOT NULL AUTO_INCREMENT, `kind` VARCHAR(8) NOT NULL, `item` VARCHAR(64) NOT NULL,
        `qty` INT NOT NULL DEFAULT 1, `metadata` LONGTEXT NULL, `price` INT NOT NULL DEFAULT 0, `cost` INT NOT NULL DEFAULT 0,
        `added_at` INT NOT NULL,
        PRIMARY KEY (`id`), KEY `item` (`item`)
    )]])
    q([[CREATE TABLE IF NOT EXISTS `ascard_shop_ledger` (
        `id` INT NOT NULL AUTO_INCREMENT, `at` INT NOT NULL, `identifier` VARCHAR(64) NULL, `name` VARCHAR(80) NULL,
        `kind` VARCHAR(16) NOT NULL, `amount` INT NOT NULL, `detail` VARCHAR(200) NULL,
        PRIMARY KEY (`id`), KEY `at` (`at`)
    )]])
    q([[CREATE TABLE IF NOT EXISTS `ascard_shop_till` (
        `account` VARCHAR(32) NOT NULL, `balance` BIGINT NOT NULL DEFAULT 0, PRIMARY KEY (`account`)
    )]])
    q([[CREATE TABLE IF NOT EXISTS `ascard_shop_staff` (
        `identifier` VARCHAR(64) NOT NULL, `name` VARCHAR(80) NULL, `minutes` INT NOT NULL DEFAULT 0,
        `sales` INT NOT NULL DEFAULT 0, `sold_value` BIGINT NOT NULL DEFAULT 0, `earned` BIGINT NOT NULL DEFAULT 0, `last_on` INT NULL,
        PRIMARY KEY (`identifier`)
    )]])
    q([[CREATE TABLE IF NOT EXISTS `ascard_shop_gradings` (
        `id` INT NOT NULL AUTO_INCREMENT, `at` INT NOT NULL, `staff` VARCHAR(64) NOT NULL, `customer` VARCHAR(64) NOT NULL, `serial` VARCHAR(64) NULL, `fee` INT NOT NULL,
        PRIMARY KEY (`id`)
    )]])
    V2.Ready = true
    TriggerEvent('as-tradingcards:v2ready')
end)

function V2.Wait() while not V2.Ready do Wait(100) end end

-- Settings in the existing key/value table ---------------------------------
function V2.GetSetting(k, default)
    local row = MySQL.single.await('SELECT v FROM ascard_settings WHERE k = ?', { k })
    return row and row.v or default
end
function V2.SetSetting(k, v)
    MySQL.insert('INSERT INTO ascard_settings (k, v) VALUES (?, ?) ON DUPLICATE KEY UPDATE v = VALUES(v)', { k, tostring(v) })
end

-- Unlocks (binder covers, mats) -------------------------------------------
function V2.HasUnlock(identifier, kind, key)
    return MySQL.scalar.await('SELECT 1 FROM ascard_unlocks WHERE identifier = ? AND kind = ? AND k = ?', { identifier, kind, key }) ~= nil
end
function V2.AddUnlock(identifier, kind, key)
    MySQL.insert.await('INSERT IGNORE INTO ascard_unlocks (identifier, kind, k) VALUES (?, ?, ?)', { identifier, kind, key })
end
function V2.Unlocks(identifier, kind)
    local out = {}
    for _, r in ipairs(MySQL.query.await('SELECT k FROM ascard_unlocks WHERE identifier = ? AND kind = ?', { identifier, kind }) or {}) do out[r.k] = true end
    return out
end

-- Series 2 ------------------------------------------------------------------
Series2 = {}
-- every set with hidden = true (Series 2, Creatures, Los Santos...) is released by the one "Series 2" switch,
-- and only once that set actually has cards.
local hasCache = {}
function Series2.HasCards(setId)
    setId = setId or ((Config.Series2 or {}).set or 'series2')
    if hasCache[setId] == nil then
        hasCache[setId] = false
        for _, c in pairs(Config.Cards) do if c.set == setId then hasCache[setId] = true break end end
    end
    return hasCache[setId]
end
function Series2.SetLive(setId) return AdminFlags.series2 == true and Series2.HasCards(setId) end
function Series2.Live() return AdminFlags.series2 == true and Series2.HasCards() end
-- can players see / pull / buy this set right now?
function Series2.Visible(setId)
    local set = Config.Sets[setId]
    if not set or not set.hidden then return true end
    return Series2.SetLive(setId)
end
function Series2.IsItem(name)
    for _, e in ipairs((Config.Series2 or {}).shop or {}) do if e.item == name then return true end end
    local pk = Config.Packs[name]
    return pk and (Config.Sets[pk.set] or {}).hidden or false
end
-- Config.Shop.items + released-set items
function Series2.ShopItems()
    local list = {}
    for _, e in ipairs(Config.Shop.items) do list[#list + 1] = e end
    for _, e in ipairs((Config.Series2 or {}).shop or {}) do
        local pk = Config.Packs[e.item]
        if not pk or Series2.Visible(pk.set) then list[#list + 1] = e end
    end
    return list
end

-- Seasons -------------------------------------------------------------------
Season = {}
function Season.Length() return ((Config.Season or {}).lengthDays or 28) * 86400 end
function Season.Number(now)
    now = now or os.time()
    local start = (Config.Season or {}).start or 0
    if now < start then return 1 end
    return math.floor((now - start) / Season.Length()) + 1
end
function Season.EndsAt(now)
    local start = (Config.Season or {}).start or 0
    local n = Season.Number(now)
    return start + n * Season.Length()
end
-- points -> { tier, label, division ('III'|'II'|'I'|''), next, nextLabel, into, span }
function Season.Tier(points)
    local tiers = (Config.Season or {}).tiers or {}
    local idx = 1
    for i, t in ipairs(tiers) do if points >= t.min then idx = i end end
    local t, nx = tiers[idx], tiers[idx + 1]
    local div = ''
    if nx then
        local span = nx.min - t.min
        local third = math.min(2, math.floor(((points - t.min) / span) * 3))
        div = ({ 'III', 'II', 'I' })[third + 1]
    end
    return { id = t.id, label = t.label, division = div, name = (t.label .. (div ~= '' and (' ' .. div) or '')),
        next = nx and nx.min or nil, nextLabel = nx and nx.label or nil, into = points - t.min, span = nx and (nx.min - t.min) or nil }
end

-- creator / custom folder report (shows which creator cards and mats loaded, and why any were skipped)
CreateThread(function()
    Wait(500)
    if not Custom then return end
    if #Custom.cards > 0 or #Custom.mats > 0 then
        print(('^2[as-tradingcards]^7 custom folder: %d card(s), %d playmat(s) loaded'):format(#Custom.cards, #Custom.mats))
    end
    for _, e in ipairs(Custom.errors) do print('^3[as-tradingcards] custom: ' .. e .. '^7') end
end)
