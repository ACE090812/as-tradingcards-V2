--[[ Money logs, admin switches, sealed boxes, sun / damp damage, serial history, shop hours, admin panel ]]

--[[ ---------------------------------------------------------------------------
    TABLES
--------------------------------------------------------------------------- ]]
AdminFlags = { auctions = false, sellBack = false, shop = false, market = false, series2 = false }

CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `ascard_money_log` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `at` INT NOT NULL,
            `identifier` VARCHAR(64) NULL,
            `name` VARCHAR(80) NULL,
            `kind` VARCHAR(24) NOT NULL,
            `amount` INT NOT NULL,
            `detail` VARCHAR(200) NULL,
            PRIMARY KEY (`id`),
            KEY `at` (`at`),
            KEY `kind` (`kind`),
            KEY `identifier` (`identifier`)
        )
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `ascard_settings` (
            `k` VARCHAR(32) NOT NULL,
            `v` VARCHAR(64) NOT NULL,
            PRIMARY KEY (`k`)
        )
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `ascard_seals` (
            `seal` VARCHAR(16) NOT NULL,
            `item` VARCHAR(64) NOT NULL,
            `status` VARCHAR(10) NOT NULL DEFAULT 'sealed',
            `created_at` INT NOT NULL,
            `opened_at` INT NULL,
            PRIMARY KEY (`seal`)
        )
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `ascard_serial_events` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `serial` VARCHAR(64) NOT NULL,
            `kind` VARCHAR(16) NOT NULL,
            `detail` VARCHAR(160) NULL,
            `at` INT NOT NULL,
            PRIMARY KEY (`id`),
            KEY `serial` (`serial`)
        )
    ]])
    for _, r in ipairs(MySQL.query.await('SELECT k, v FROM ascard_settings') or {}) do
        if AdminFlags[r.k] ~= nil then AdminFlags[r.k] = r.v == '1' end
    end
    local keep = ((Config.MoneyLogs or {}).keepDays or 60) * 86400
    MySQL.update('DELETE FROM ascard_money_log WHERE `at` < ?', { os.time() - keep })
end)

--[[ ---------------------------------------------------------------------------
    MONEY LOGS
--------------------------------------------------------------------------- ]]
MoneyLog = {}
local ML = Config.MoneyLogs or {}
local KIND_LABEL = {
    shop_buy = 'Bought at the card shop', sell_back = 'Sold a card to the shop', sell_sealed = 'Sold sealed to the shop',
    auction_sale = 'Auction sale (seller paid)', auction_fee = 'Auction final value fee', listing_fee = 'Auction listing fee',
    auction_buy = 'Won an auction', repack = 'Bought a repack', release = 'Release day purchase', appraisal = 'Appraisal letter',
    grading = 'Grading fee', toptrumps = 'Top Trumps winnings', admin = 'Admin',
}
MoneyLog.Labels = KIND_LABEL

local function hook() return GetConvar('ascard_log_webhook', '') end
local function money(n) return Utils.Money(n) end

local sellWatch = {}   -- [identifier] = { {at, amount} ... }

local function discord(title, lines, colour)
    local d = ML.discord or {}
    local url = hook()
    if not d.enabled or url == '' then return end
    PerformHttpRequest(url, function() end, 'POST', json.encode({ username = d.username or 'Card Economy Log', embeds = { {
        title = title, description = table.concat(lines, '\n'):sub(1, 1900), color = colour or 0xe8a33b, timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
    } } }), { ['Content-Type'] = 'application/json' })
end

-- who: a player source (number) or an identifier (string). amount: + money to the player, - money from them
function MoneyLog.Add(who, kind, amount, detail)
    if not ML.enabled then return end
    amount = math.floor(tonumber(amount) or 0)
    local identifier, name
    if type(who) == 'number' then
        identifier = Framework.GetIdentifier(who)
        name = Framework.GetName(who)
    else
        identifier = who
        local src = Market and Market.SourceOf(who)
        name = src and Framework.GetName(src) or nil
    end
    detail = tostring(detail or ''):sub(1, 200)
    MySQL.insert('INSERT INTO ascard_money_log (`at`, identifier, name, kind, amount, detail) VALUES (?, ?, ?, ?, ?, ?)',
        { os.time(), identifier, name, kind, amount, detail })
    local d = ML.discord or {}
    if math.abs(amount) >= (d.minAmount or 2500) then
        discord(('%s: %s'):format(KIND_LABEL[kind] or kind, money(math.abs(amount))),
            { ('**Player:** %s (%s)'):format(name or '?', identifier or '?'), ('**Amount:** %s%s'):format(amount < 0 and '-' or '+', money(math.abs(amount))), detail ~= '' and ('**Detail:** ' .. detail) or nil },
            amount < 0 and 0x3b82f6 or 0x22c55e)
    end
    -- selling a lot back to the shop in a short time can mean a dupe
    if (kind == 'sell_back' or kind == 'sell_sealed') and identifier and ML.watch then
        local now, list, total = os.time(), sellWatch[identifier] or {}, 0
        local keep = {}
        for _, e in ipairs(list) do if now - e.at <= (ML.watch.minutes or 30) * 60 then keep[#keep + 1] = e total = total + e.amount end end
        keep[#keep + 1] = { at = now, amount = amount }
        total = total + amount
        sellWatch[identifier] = keep
        if total >= (ML.watch.sellBackTotal or 25000) and not keep.flagged then
            keep.flagged = true
            discord('⚠ Check this player: big sell-back', { ('**%s** (%s) sold %s to the card shop in the last %d minutes.'):format(name or '?', identifier, money(total), ML.watch.minutes or 30) }, 0xef4444)
        end
    end
end

--[[ ---------------------------------------------------------------------------
    SERIAL HISTORY
--------------------------------------------------------------------------- ]]
SerialLog = {}
function SerialLog.Add(serial, kind, detail)
    if type(serial) ~= 'string' or serial == '' then return end
    MySQL.insert('INSERT INTO ascard_serial_events (serial, kind, detail, `at`) VALUES (?, ?, ?, ?)', { serial, kind, tostring(detail or ''):sub(1, 160), os.time() })
end

function SerialLog.Get(serial)
    local out = {}
    for _, r in ipairs(MySQL.query.await('SELECT kind, detail, `at` FROM ascard_serial_events WHERE serial = ? ORDER BY `at`, id', { serial }) or {}) do
        out[#out + 1] = { kind = r.kind, detail = r.detail, at = r.at }
    end
    return out
end

--[[ ---------------------------------------------------------------------------
    SEALED BOXES
--------------------------------------------------------------------------- ]]
Seals = {}
local SL = Config.Seals or {}

function Seals.IsBox(name)
    return (Config.Boxes and Config.Boxes[name] ~= nil) or (Config.BoosterBox and Config.BoosterBox.item == name)
end

local function sealCode()
    local chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    local t = {}
    for i = 1, 8 do local k = math.random(#chars) t[i] = chars:sub(k, k) end
    return 'FS-' .. table.concat(t)
end

-- metadata for a new factory-sealed box (registered, so a seal check says "factory sealed")
function Seals.New(item)
    local seal = sealCode()
    MySQL.insert('INSERT INTO ascard_seals (seal, item, status, created_at) VALUES (?, ?, ?, ?)', { seal, item, 'sealed', os.time() })
    return { seal = seal, description = ('Factory sealed · Seal %s'):format(seal) }
end

-- status: 'opened' (default) or 'shop' (sold back to the card shop)
function Seals.Opened(meta, status)
    if type(meta) ~= 'table' or not meta.seal or meta.resealed then return end
    MySQL.update("UPDATE ascard_seals SET status = ?, opened_at = ? WHERE seal = ? AND status = 'sealed'", { status or 'opened', os.time(), meta.seal })
end

function Seals.Check(seal)
    seal = tostring(seal or ''):upper():gsub('%s', ''):sub(1, 16)
    if #seal < 5 then return nil, 'Enter the seal number printed on the box wrap.' end
    local r = MySQL.single.await('SELECT item, status, created_at, opened_at FROM ascard_seals WHERE seal = ?', { seal })
    if not r then return { seal = seal, found = false } end
    local bx = (Config.Boxes or {})[r.item] or (Config.BoosterBox and Config.BoosterBox.item == r.item and Config.BoosterBox) or {}
    return { seal = seal, found = true, item = r.item, label = bx.label or r.item, status = r.status, sealedAt = r.created_at, openedAt = r.opened_at }
end

-- what packs a box needs to be (re)sealed: { { item, count } }
local function boxRecipe(name)
    local bx = (Config.Boxes or {})[name]
    if bx then return bx.gives, bx.label end
    if Config.BoosterBox and Config.BoosterBox.item == name then return { Config.BoosterBox.gives }, Config.BoosterBox.label end
end

lib.callback.register('as-tradingcards:server:resealList', function(src)
    if not (SL.enabled and SL.allowReseal) or Inventory.Count(src, SL.shrinkwrap) < 1 then return nil end
    local out = {}
    local names = {}
    for name in pairs(Config.Boxes or {}) do names[#names + 1] = name end
    if Config.BoosterBox and Config.BoosterBox.enabled then names[#names + 1] = Config.BoosterBox.item end
    table.sort(names)
    for _, name in ipairs(names) do
        local recipe, label = boxRecipe(name)
        local ok, need = true, {}
        for _, g in ipairs(recipe) do
            local have = Inventory.Count(src, g.item)
            need[#need + 1] = ('%d/%d %s'):format(math.min(have, g.count), g.count, (Config.Packs[g.item] or {}).label or g.item)
            if have < g.count then ok = false end
        end
        out[#out + 1] = { item = name, label = label or name, possible = ok, need = table.concat(need, ', ') }
    end
    return out
end)

lib.callback.register('as-tradingcards:server:reseal', function(src, boxName)
    if not (SL.enabled and SL.allowReseal) then return false end
    local recipe, label = boxRecipe(tostring(boxName))
    if not recipe or Inventory.Count(src, SL.shrinkwrap) < 1 then return false end
    -- collect the exact packs first (keep their metadata, including any hit)
    local take, contents = {}, {}
    for _, g in ipairs(recipe) do
        local left = g.count
        for _, it in ipairs(Inventory.GetItems(src, function(n) return n == g.item end)) do
            if left <= 0 then break end
            local n = math.min(left, it.count)
            take[#take + 1] = { item = it.item or it.name, slot = it.slot, count = n, metadata = it.metadata }
            for _ = 1, n do contents[#contents + 1] = { item = it.name, metadata = it.metadata or {} } end
            left = left - n
        end
        if left > 0 then Framework.Notify(src, 'You don’t have all the packs for that box.', 'error') return false end
    end
    if not Inventory.RemoveItem(src, SL.shrinkwrap, 1) then return false end
    for _, t in ipairs(take) do Inventory.RemoveItem(src, t.item or '', t.count, t.slot) end
    local fakeSeal = sealCode()   -- looks the same, but it was never registered
    local ok = Inventory.AddItem(src, boxName, 1, { seal = fakeSeal, description = ('Factory sealed · Seal %s'):format(fakeSeal), resealed = true, contents = contents })
    Framework.Notify(src, ok and ('You shrink-wrapped the packs into a %s.'):format(label or boxName) or 'No space for the box.', ok and 'success' or 'error')
    return ok
end)

-- opening a resealed box gives back exactly what was sealed inside it
function Seals.OpenResealed(src, meta)
    for _, p in ipairs(meta.contents or {}) do Inventory.AddItem(src, p.item, 1, p.metadata or {}) end
    return #(meta.contents or {})
end

--[[ ---------------------------------------------------------------------------
    SUN AND DAMP (raw cards left in a vehicle or on the ground)
--------------------------------------------------------------------------- ]]
local WE = Config.Weather or {}

local function placeOf(p, to)
    local t = to and p.toType or p.fromType
    local inv = to and p.toInventory or p.fromInventory
    if t == 'drop' or inv == 'newdrop' then return 'drop' end
    if t == 'glovebox' or t == 'trunk' then return t end
end

local function exposed(meta, place, hours)
    local cfg = WE.places and WE.places[place]
    if not cfg then return false end
    local h = hours - (cfg.safeHours or 0)
    if h <= 0 then return false end
    local factor = 1
    if meta.prot == 'toploader' then factor = WE.toploader or 0 elseif meta.prot == 'sleeve' then factor = WE.sleeve or 0.5 end
    if factor <= 0 then return false end
    Condition.Ensure(meta)
    local c = meta.cond
    local changed = false
    if (cfg.fadePerHour or 0) > 0 then
        local before = c.fade or 0
        c.fade = math.min(WE.maxFade or 0.85, before + cfg.fadePerHour * h * factor)
        changed = c.fade ~= before
    end
    if (c.warp or 0) == 0 and (cfg.warpPerHour or 0) > 0 then
        local chance = 1 - (1 - math.min(0.9, cfg.warpPerHour * factor)) ^ h
        if math.random() < chance then c.warp = 1 changed = true end
    end
    return changed
end

if WE.enabled and Inventory.name == 'ox' then
    local filter = {}
    for name in pairs(Utils.CardItems) do filter[name] = true end
    CreateThread(function()
        exports.ox_inventory:registerHook('swapItems', function(p)
            local item = p.fromSlot
            if type(item) ~= 'table' or type(item.metadata) ~= 'table' or not item.metadata.cardId or item.metadata.grade then return end
            local m = item.metadata
            local into, outOf = placeOf(p, true), placeOf(p, false)
            if outOf and m.leftAt then
                local hours = (os.time() - m.leftAt) / 3600
                if exposed(m, m.leftIn or outOf, hours) then m.description = Utils.CardDescription(m, item.name) end
                m.leftAt, m.leftIn = nil, nil
            end
            if into then m.leftAt, m.leftIn = os.time(), into end
        end, { itemFilter = filter })
    end)
end

--[[ ---------------------------------------------------------------------------
    SHOP HOURS
--------------------------------------------------------------------------- ]]
local SH = Config.ShopHours or {}
function ShopOpen(src)
    if not SH.enabled then return true end
    local hour, wday
    if SH.clock == 'game' and src then
        hour = tonumber(Player(src).state.ascardHour)
        wday = tonumber(os.date('%w'))
    end
    if not hour then
        local d = os.date('*t')
        hour, wday = d.hour, d.wday - 1
    end
    for _, d in ipairs(SH.closedDays or {}) do if d == wday then return false end end
    local o, c = SH.open or 9, SH.close or 23
    if o == c then return true end
    if o < c then return hour >= o and hour < c end
    return hour >= o or hour < c
end
function ShopHoursText()
    local function f(h) return ('%02d:00'):format(h % 24) end
    return ('Open %s–%s'):format(f(SH.open or 9), f(SH.close or 23))
end

--[[ ---------------------------------------------------------------------------
    ADMIN PANEL
--------------------------------------------------------------------------- ]]
local function isAdmin(src) return Framework.IsAdmin(src) end

local function setFlag(k, v)
    if AdminFlags[k] == nil then return end
    AdminFlags[k] = v and true or false
    MySQL.insert('INSERT INTO ascard_settings (k, v) VALUES (?, ?) ON DUPLICATE KEY UPDATE v = VALUES(v)', { k, v and '1' or '0' })
end

local A = {}

A.overview = function(src)
    local now = os.time()
    local function sums(since)
        local out = {}
        for _, r in ipairs(MySQL.query.await('SELECT kind, COUNT(*) AS n, COALESCE(SUM(amount), 0) AS total FROM ascard_money_log WHERE `at` >= ? GROUP BY kind', { since }) or {}) do
            out[r.kind] = { n = r.n, total = r.total }
        end
        return out
    end
    local live, bids = 0, 0
    for _, a in pairs(Auctions.live) do live = live + 1 bids = bids + (a.bid or 0) end
    local pool, poolValue = 0, 0
    for _, r in pairs(Repacks and Repacks.pool or {}) do pool = pool + 1 poolValue = poolValue + r.value end
    local waiting = MySQL.single.await('SELECT COUNT(*) AS n, COALESCE(SUM(amount), 0) AS total FROM ascard_payouts') or {}
    local undelivered = MySQL.scalar.await("SELECT COUNT(*) FROM ascard_deliveries WHERE status = 'pending'") or 0
    local online = #GetPlayers()
    return {
        day = sums(now - 86400), week = sums(now - 7 * 86400), labels = KIND_LABEL,
        live = live, liveBids = bids, pool = pool, poolValue = poolValue, payouts = waiting.n or 0, payoutsTotal = waiting.total or 0,
        undelivered = undelivered, online = online, flags = AdminFlags, marketUpdated = Market.updatedAt, shopOpen = ShopOpen(), hours = ShopHoursText(),
    }
end

A.players = function()
    local out = {}
    for _, s in ipairs(GetPlayers()) do
        s = tonumber(s)
        out[#out + 1] = { id = s, name = Framework.GetName(s), identifier = Framework.GetIdentifier(s) }
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

A.player = function(src, d)
    local t = tonumber(d.id)
    if not t or not GetPlayerName(t) then return nil, 'Player not online.' end
    local id = Framework.GetIdentifier(t)
    local p = Market.Portfolio(t)
    local logs = {}
    for _, r in ipairs(MySQL.query.await('SELECT `at`, kind, amount, detail FROM ascard_money_log WHERE identifier = ? ORDER BY id DESC LIMIT 25', { id }) or {}) do logs[#logs + 1] = r end
    return { id = t, name = Framework.GetName(t), identifier = id, stats = Stats.Get(id), cards = #p.cards, value = p.total, sealed = p.sealedTotal, top = { p.cards[1], p.cards[2], p.cards[3] }, logs = logs }
end

A.searchCards = function(src, d)
    local q = tostring(d.q or ''):lower()
    local out = {}
    if #q < 2 then return out end
    for _, card in ipairs(Market.CardList) do
        local hay = (Utils.FullName(card) .. ' ' .. card.id .. ' ' .. Utils.CardCode(card)):lower()
        if hay:find(q, 1, true) then
            out[#out + 1] = { id = card.id, name = Utils.FullName(card), code = Utils.CardCode(card), type = (Utils.RarityById[card.type] or {}).label }
            if #out >= 20 then break end
        end
    end
    return out
end

A.options = function()
    local pars, packs = {}, {}
    for _, p in ipairs(Config.Parallels or {}) do pars[#pars + 1] = { id = p.id, label = p.label } end
    for _, t in ipairs((Config.Inserts or {}).types or {}) do pars[#pars + 1] = { id = 'ins:' .. t.id, label = t.label } end
    for name, pk in pairs(Config.Packs) do packs[#packs + 1] = { id = name, label = pk.label } end
    for name, bx in pairs(Config.Boxes or {}) do packs[#packs + 1] = { id = name, label = bx.label } end
    if Config.BoosterBox and Config.BoosterBox.enabled then packs[#packs + 1] = { id = Config.BoosterBox.item, label = Config.BoosterBox.label } end
    table.sort(packs, function(a, b) return a.label < b.label end)
    return { parallels = pars, packs = packs }
end

A.give = function(src, d)
    local t = tonumber(d.target)
    if not t or not GetPlayerName(t) then return nil, 'Player not online.' end
    if d.kind == 'pack' then
        local count = math.max(1, math.min(50, math.floor(tonumber(d.count) or 1)))
        local item = tostring(d.id or '')
        if not (Config.Packs[item] or Seals.IsBox(item)) then return nil, 'Unknown product.' end
        if Series2.IsItem(item) and not (Config.Packs[item] and Series2.SetLive(Config.Packs[item].set) or Series2.Live()) then return nil, 'Series 2 is switched off (Switches tab).' end
        Cards.GivePacks(t, item, count)
        MoneyLog.Add(t, 'admin', 0, ('%s gave %dx %s'):format(Framework.GetName(src), count, item))
        return { ok = true }
    end
    local cardId = tostring(d.id or '')
    if not Config.Cards[cardId] then return nil, 'Unknown card.' end
    local par, ins = nil, nil
    if type(d.version) == 'string' and d.version ~= '' then
        if d.version:sub(1, 4) == 'ins:' then ins = d.version:sub(5) else par = d.version end
    end
    local meta = Cards.Mint(cardId, d.foil == true, par, { insert = ins })
    if not meta then return nil, 'Could not make that card (print run full?).' end
    local item = Cards.ItemFor(cardId)
    local grade = tonumber(d.grade)
    if grade and grade >= 1 and grade <= 10 then
        grade = math.floor(grade)
        meta.grade, meta.cert = grade, tostring(math.random(10000000, 99999999))
        meta.sub = { cen = grade, cor = grade, edg = grade, sur = grade }
        meta.pristine = (grade == 10 and d.pristine == true) or nil
        meta.gradedFrom = item
        meta.label = ('%s %d %s'):format(meta.pristine and 'Pristine' or 'Graded', grade, Utils.BuildDisplay(meta, item).label)
        item = Config.Items.slab
    end
    if not Inventory.AddItem(t, item, 1, meta) then return nil, 'Their inventory is full.' end
    DB.SetOwner(meta.serial, Framework.GetIdentifier(t), cardId)
    SerialLog.Add(meta.serial, 'admin', ('Given by staff (%s)'):format(Framework.GetName(src)))
    MoneyLog.Add(t, 'admin', 0, ('%s gave %s'):format(Framework.GetName(src), Utils.CardTitle(meta, item)))
    return { ok = true, title = Utils.CardTitle(meta, item) }
end

A.flag = function(src, d)
    if AdminFlags[d.key] == nil then return nil, 'Unknown switch.' end
    setFlag(d.key, d.value == true)
    MoneyLog.Add(src, 'admin', 0, ('%s turned %s %s'):format(Framework.GetName(src), d.key, d.value and 'ON (paused)' or 'OFF'))
    return { flags = AdminFlags }
end

A.auctions = function()
    local out = {}
    for _, a in pairs(Auctions.live) do
        out[#out + 1] = { id = a.id, title = a.title, seller = a.seller_name, bid = a.bid, bidder = a.bidder_name, bids = a.bids, start = a.start_price, endsAt = a.ends_at }
    end
    table.sort(out, function(x, y) return x.endsAt < y.endsAt end)
    return { list = out, now = os.time() }
end

A.auctionCancel = function(src, d)
    local ok, err = Auctions.AdminCancel(tonumber(d.id), ('Removed by staff (%s)'):format(Framework.GetName(src)))
    return ok and { ok = true } or nil, err
end

A.pool = function()
    local list = {}
    for _, r in pairs(Repacks and Repacks.pool or {}) do list[#list + 1] = r end
    table.sort(list, function(a, b) return a.value > b.value end)
    local out = {}
    for i = 1, math.min(100, #list) do
        local r = list[i]
        out[i] = { id = r.id, title = Utils.CardTitle(r.meta, r.item), value = r.value, serial = r.meta.serial }
    end
    return { list = out, total = #list }
end

A.poolRemove = function(src, d)
    local id = tonumber(d.id)
    if not id or not Repacks.pool[id] then return nil, 'Not in the pool.' end
    Repacks.pool[id] = nil
    MySQL.update('DELETE FROM ascard_repack_pool WHERE id = ?', { id })
    return { ok = true }
end

A.logs = function(src, d)
    local where, params = {}, {}
    if d.kind and d.kind ~= '' then where[#where + 1] = 'kind = ?' params[#params + 1] = tostring(d.kind) end
    if d.search and d.search ~= '' then
        where[#where + 1] = '(name LIKE ? OR identifier LIKE ? OR detail LIKE ?)'
        local q = '%' .. tostring(d.search):sub(1, 40):gsub('[%%_]', '') .. '%'
        params[#params + 1] = q params[#params + 1] = q params[#params + 1] = q
    end
    local page = math.max(1, math.floor(tonumber(d.page) or 1))
    local sql = 'SELECT id, `at`, identifier, name, kind, amount, detail FROM ascard_money_log' .. (#where > 0 and (' WHERE ' .. table.concat(where, ' AND ')) or '') ..
        (' ORDER BY id DESC LIMIT 50 OFFSET %d'):format((page - 1) * 50)
    return { list = MySQL.query.await(sql, params) or {}, page = page, labels = KIND_LABEL }
end

A.report = function()
    local ok, err = MarketReport(true)
    return ok and { ok = true } or nil, err
end

lib.callback.register('as-tradingcards:server:admin', function(src, name, data)
    if not (Config.Admin and Config.Admin.enabled) or not isAdmin(src) then return { ok = false, error = 'Staff only.' } end
    local fn = A[tostring(name)]
    if not fn then return { ok = false, error = 'Unknown request.' } end
    local ok, res, err = pcall(fn, src, type(data) == 'table' and data or {})
    if not ok then print(('^1[as-tradingcards] admin %s failed: %s^0'):format(name, tostring(res))) return { ok = false, error = 'Something went wrong (see server console).' } end
    if res == nil then return { ok = false, error = err or 'Failed.' } end
    return { ok = true, data = res }
end)

lib.addCommand((Config.Admin or {}).command or 'cardadmin', { help = 'Trading card admin panel', restricted = Config.AdminAce }, function(src)
    if src and src > 0 then TriggerClientEvent('as-tradingcards:client:admin', src) end
end)
