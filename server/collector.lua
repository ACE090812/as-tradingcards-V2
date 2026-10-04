--[[ Repacks, appraisal letters, personal stats, collection value history, daily Discord market report ]]

--[[ ---------------------------------------------------------------------------
    TABLES
--------------------------------------------------------------------------- ]]
CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `ascard_repack_pool` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `item` VARCHAR(64) NOT NULL,
            `metadata` LONGTEXT NOT NULL,
            `value` INT NOT NULL,
            `added_at` INT NOT NULL,
            PRIMARY KEY (`id`)
        )
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `ascard_stats` (
            `identifier` VARCHAR(64) NOT NULL,
            `packs` INT NOT NULL DEFAULT 0,
            `cards` INT NOT NULL DEFAULT 0,
            `spent` INT NOT NULL DEFAULT 0,
            `pulled_value` INT NOT NULL DEFAULT 0,
            `sold` INT NOT NULL DEFAULT 0,
            `auction_spent` INT NOT NULL DEFAULT 0,
            `auction_earned` INT NOT NULL DEFAULT 0,
            `repacks` INT NOT NULL DEFAULT 0,
            `best_title` VARCHAR(160) NULL,
            `best_value` INT NOT NULL DEFAULT 0,
            `best_card` VARCHAR(64) NULL,
            `best_item` VARCHAR(64) NULL,
            `best_at` INT NULL,
            `first_at` INT NULL,
            PRIMARY KEY (`identifier`)
        )
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `ascard_appraisals` (
            `ref` VARCHAR(24) NOT NULL,
            `identifier` VARCHAR(64) NOT NULL,
            `data` LONGTEXT NOT NULL,
            `created_at` INT NOT NULL,
            PRIMARY KEY (`ref`),
            KEY `identifier` (`identifier`)
        )
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `ascard_value_history` (
            `identifier` VARCHAR(64) NOT NULL,
            `day` INT NOT NULL,
            `value` INT NOT NULL,
            PRIMARY KEY (`identifier`, `day`)
        )
    ]])
    Repacks.Load()
end)

--[[ ---------------------------------------------------------------------------
    STATS
--------------------------------------------------------------------------- ]]
Stats = {}
local FIELDS = { packs = true, cards = true, spent = true, pulled_value = true, sold = true, auction_spent = true, auction_earned = true, repacks = true }

function Stats.Add(identifier, field, n)
    if not identifier or not FIELDS[field] then return end
    n = math.floor(tonumber(n) or 0)
    if n == 0 then return end
    MySQL.insert(('INSERT INTO ascard_stats (identifier, `%s`, first_at) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE `%s` = `%s` + VALUES(`%s`)'):format(field, field, field, field),
        { identifier, n, os.time() })
end

function Stats.Pull(identifier, meta, itemName)
    if not identifier or not meta then return end
    local v = Utils.CardValue(meta, itemName)
    local title = Utils.CardTitle(meta, itemName):sub(1, 160)
    MySQL.insert([[
        INSERT INTO ascard_stats (identifier, cards, pulled_value, best_title, best_value, best_card, best_item, best_at, first_at)
        VALUES (?, 1, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE cards = cards + 1, pulled_value = pulled_value + VALUES(pulled_value),
            best_title = IF(VALUES(best_value) > best_value, VALUES(best_title), best_title),
            best_card = IF(VALUES(best_value) > best_value, VALUES(best_card), best_card),
            best_item = IF(VALUES(best_value) > best_value, VALUES(best_item), best_item),
            best_at = IF(VALUES(best_value) > best_value, VALUES(best_at), best_at),
            best_value = GREATEST(best_value, VALUES(best_value))
    ]], { identifier, v, title, v, meta.cardId, itemName, os.time(), os.time() })
end

function Stats.Get(identifier)
    local r = MySQL.single.await('SELECT * FROM ascard_stats WHERE identifier = ?', { identifier }) or {}
    local spent, pulled = r.spent or 0, r.pulled_value or 0
    return {
        packs = r.packs or 0, cards = r.cards or 0, repacks = r.repacks or 0, spent = spent, pulledValue = pulled,
        returnPct = spent > 0 and math.floor(pulled / spent * 100 + 0.5) or nil,
        sold = r.sold or 0, auctionSpent = r.auction_spent or 0, auctionEarned = r.auction_earned or 0,
        best = r.best_title and { title = r.best_title, value = r.best_value, cardId = r.best_card, item = r.best_item, at = r.best_at } or nil,
        since = r.first_at,
    }
end

--[[ ---------------------------------------------------------------------------
    REPACKS
--------------------------------------------------------------------------- ]]
Repacks = { pool = {} }
local RP = Config.Repacks or {}

function Repacks.Load()
    for _, r in ipairs(MySQL.query.await('SELECT id, item, metadata, value FROM ascard_repack_pool') or {}) do
        Repacks.pool[r.id] = { id = r.id, item = r.item, meta = json.decode(r.metadata) or {}, value = r.value }
    end
end

-- a card sold to the shop goes into the pool
function Repacks.Add(itemName, meta, value)
    if not RP.enabled or type(meta) ~= 'table' or not meta.cardId then return end
    local now = os.time()
    MySQL.insert('INSERT INTO ascard_repack_pool (item, metadata, value, added_at) VALUES (?, ?, ?, ?)', { itemName, json.encode(meta), value, now }, function(id)
        if id then Repacks.pool[id] = { id = id, item = itemName, meta = meta, value = value } end
    end)
    -- keep the pool from growing forever: drop the cheapest when it's full
    local n = 0
    for _ in pairs(Repacks.pool) do n = n + 1 end
    if n > (RP.maxPool or 2000) then
        local cheapest
        for _, r in pairs(Repacks.pool) do if not cheapest or r.value < cheapest.value then cheapest = r end end
        if cheapest then Repacks.pool[cheapest.id] = nil MySQL.update('DELETE FROM ascard_repack_pool WHERE id = ?', { cheapest.id }) end
    end
end

local function qualifies(r, g)
    local m = r.meta
    if g == 'numbered' then return m.parallel ~= nil or m.insert ~= nil or m.grade ~= nil end
    if g == 'bigHit' then return m.grade ~= nil or m.insert ~= nil end
    return true
end

local function eligible(tier, taken)
    local out = {}
    for id, r in pairs(Repacks.pool) do
        if not taken[id] and (not tier.maxValue or r.value <= tier.maxValue) then out[#out + 1] = r end
    end
    return out
end

-- cheap cards come up more often: weight = 1 / sqrt(value + 1)
local function pickFrom(list)
    if #list == 0 then return nil end
    local total = 0
    for _, r in ipairs(list) do total = total + 1 / math.sqrt(r.value + 1) end
    local roll, acc = math.random() * total, 0
    for _, r in ipairs(list) do
        acc = acc + 1 / math.sqrt(r.value + 1)
        if roll <= acc then return r end
    end
    return list[#list]
end

local function tierById(id) for _, t in ipairs(RP.tiers or {}) do if t.id == id then return t end end end

local function availability(tier)
    local list = eligible(tier, {})
    local chase
    for _, r in ipairs(list) do if not chase or r.value > chase.value then chase = r end end
    local okGuarantee = true
    if tier.guarantee then
        okGuarantee = false
        for _, r in ipairs(list) do if qualifies(r, tier.guarantee) then okGuarantee = true break end end
    end
    local enough = #list >= tier.cards or (tier.id == 'bronze' and RP.topUpBronze)
    return okGuarantee and enough, chase, #list
end

function Repacks.List()
    local out = {}
    for _, t in ipairs(RP.tiers or {}) do
        local ok, chase, count = availability(t)
        out[#out + 1] = { id = t.id, label = t.label, price = t.price, cards = t.cards, guarantee = t.guarantee, available = ok, pool = count,
            chase = chase and { title = Utils.CardTitle(chase.meta, chase.item), value = chase.value } or nil }
    end
    return out
end

lib.callback.register('as-tradingcards:server:repackList', function(src)
    if not RP.enabled or not IsNearRole(src, 'shop') then return nil end
    return Repacks.List()
end)

local buyingRepack = {}
lib.callback.register('as-tradingcards:server:repackBuy', function(src, tierId)
    if not RP.enabled or not IsNearRole(src, 'shop') or buyingRepack[src] then return false end
    if AdminFlags and AdminFlags.shop then Framework.Notify(src, 'The card shop is closed by staff right now.', 'error') return false end
    local tier = tierById(tostring(tierId))
    if not tier then return false end
    if not availability(tier) then Framework.Notify(src, 'That repack is out of stock right now. Check back later.', 'error') return false end
    if Inventory.FreeSlots(src) < tier.cards then Framework.Notify(src, L('no_space', tier.cards), 'error') return false end
    buyingRepack[src] = true

    -- choose the cards first, then take the money
    local taken, picks = {}, {}
    if tier.guarantee then
        local g = {}
        for _, r in ipairs(eligible(tier, taken)) do if qualifies(r, tier.guarantee) then g[#g + 1] = r end end
        local r = pickFrom(g)
        if r then taken[r.id] = true picks[#picks + 1] = r end
    end
    while #picks < tier.cards do
        local r = pickFrom(eligible(tier, taken))
        if not r then break end
        taken[r.id] = true
        picks[#picks + 1] = r
    end
    local fresh = tier.cards - #picks
    if fresh > 0 and not (tier.id == 'bronze' and RP.topUpBronze) then
        buyingRepack[src] = nil
        Framework.Notify(src, 'That repack is out of stock right now.', 'error')
        return false
    end
    if not Framework.Charge(src, tier.price, 'ascard-repack') then
        buyingRepack[src] = nil
        Framework.Notify(src, L('not_enough_money'), 'error')
        return false
    end

    local identifier = Framework.GetIdentifier(src)
    local displays = {}
    for _, r in ipairs(picks) do
        -- whoever removes the row owns the card (never handed out twice)
        if (MySQL.update.await('DELETE FROM ascard_repack_pool WHERE id = ?', { r.id }) or 0) > 0 then
            Repacks.pool[r.id] = nil
            Inventory.AddItem(src, r.item, 1, r.meta)
            displays[#displays + 1] = Utils.BuildDisplay(r.meta, r.item)
        else
            fresh = fresh + 1
        end
    end
    -- top up with fresh base cards (Player / Star)
    for _ = 1, fresh do
        local pool = {}
        for id, c in pairs(Config.Cards) do if (c.type == 'player' or c.type == 'star') and not DB.IsSoldOut(id) then pool[#pool + 1] = id end end
        local cardId = pool[math.random(#pool)]
        local meta = Cards.Mint(cardId, false, nil)
        local itemName = Cards.ItemFor(cardId)
        if meta and itemName and Inventory.AddItem(src, itemName, 1, meta) then
            displays[#displays + 1] = Utils.BuildDisplay(meta, itemName)
            if identifier then DB.SetOwner(meta.serial, identifier, cardId) end
        end
    end
    buyingRepack[src] = nil
    Stats.Add(identifier, 'spent', tier.price)
    Stats.Add(identifier, 'repacks', 1)
    if MoneyLog then MoneyLog.Add(src, 'repack', -tier.price, tier.label) end
    table.sort(displays, function(a, b) return (Utils.RarityIndex[a.rarity.id] or 0) < (Utils.RarityIndex[b.rarity.id] or 0) end)
    TriggerClientEvent('as-tradingcards:client:openPack', src, { label = tier.label, art = Config.PackArt, cards = displays })
    return true
end)
AddEventHandler('playerDropped', function() buyingRepack[source] = nil end)

--[[ ---------------------------------------------------------------------------
    APPRAISAL LETTERS
--------------------------------------------------------------------------- ]]
local AP = Config.Appraisal or {}
Appraisal = {}

function Appraisal.Order(src, identifier, slot, serial)
    if not AP.enabled then return nil, 'Appraisals are turned off.' end
    local item = Inventory.GetSlot(src, tonumber(slot))
    if not item or not Utils.IsCollectible(item.name) then return nil, 'That card is no longer in your pockets.' end
    local m = item.metadata or {}
    if serial and m.serial ~= serial then return nil, 'That card moved in your pockets. Try again.' end
    if not m.cardId then return nil, 'That card can’t be appraised.' end
    DB.Seen(src, m)
    local acc = (Config.Auctions or {}).account or 'bank'
    local price = AP.price or 50
    if (Framework.GetMoney(src, acc) or 0) < price or not Framework.RemoveMoney(src, acc, price, 'ascard-appraisal') then
        return nil, ('You need %s in your %s.'):format(Market.Money(price), acc)
    end
    local title = Utils.CardTitle(m, item.name)
    local value = Utils.CardValue(m, item.name)
    local condition
    if m.grade then
        condition = ('Graded %s %d%s'):format(m.pristine and (Config.Pristine or {}).label or (Config.Grading.labels[m.grade] or ''), m.grade, m.cert and (' (cert ' .. m.cert .. ')') or '')
    elseif type(m.cond) == 'table' then
        local sc = Condition.Scores(m.cond)
        condition = ('%s (%s)'):format(sc.word, sc.overall)
    else
        condition = 'Not assessed'
    end
    local date = os.date('%d %b %Y')
    local letter = {
        label = ('Appraisal: %s'):format(title):sub(1, 60),
        description = ('%s | Serial %s | %s | Valued at %s | %s | %s'):format(title, m.serial or '-', condition, Market.Money(value), date, AP.issuer or 'LS Card Exchange'),
        appraisal = { title = title, serial = m.serial, value = value, condition = condition, date = date, cardId = m.cardId, issuer = AP.issuer, ref = ('AP-%d%03d'):format(os.time() % 1000000, math.random(0, 999)),
            holder = Framework.GetName(src), graded = m.grade ~= nil },
    }
    MySQL.insert('INSERT INTO ascard_appraisals (ref, identifier, data, created_at) VALUES (?, ?, ?, ?)', { letter.appraisal.ref, identifier, json.encode(letter.appraisal), os.time() })
    if MoneyLog then MoneyLog.Add(src, 'appraisal', -price, ('%s (%s)'):format(title, m.serial or '?')) end
    if SerialLog then SerialLog.Add(m.serial, 'appraised', ('Appraised at %s · %s · ref %s'):format(Market.Money(value), condition, letter.appraisal.ref)) end
    local ok, locker = Auctions.Deliver(identifier, AP.item or 'ascard_appraisal', letter, 'Appraisal letter: ' .. title, Auctions.LockerFor(identifier), 'appraisal')
    return { value = value, locker = locker and locker.label or nil, ref = letter.appraisal.ref }
end

-- every letter this character has ordered (to save to the phone or print again)
function Appraisal.Mine(identifier)
    local out = {}
    for _, r in ipairs(MySQL.query.await('SELECT data, created_at FROM ascard_appraisals WHERE identifier = ? ORDER BY created_at DESC LIMIT 30', { identifier }) or {}) do
        local a = json.decode(r.data) or {}
        a.at = r.created_at
        out[#out + 1] = a
    end
    return out
end

local function letterFor(identifier, ref)
    local r = MySQL.single.await('SELECT data FROM ascard_appraisals WHERE ref = ? AND identifier = ?', { tostring(ref or ''):sub(1, 24), identifier })
    return r and json.decode(r.data) or nil
end

local function letterText(a)
    return table.concat({
        (a.issuer or 'LS Card Exchange Appraisals'):upper(),
        'CERTIFICATE OF APPRAISAL',
        '',
        ('Reference: %s'):format(a.ref or '-'),
        ('Date: %s'):format(a.date or '-'),
        '',
        ('Card: %s'):format(a.title or '-'),
        ('Serial number: %s'):format(a.serial or '-'),
        ('%s: %s'):format(a.graded and 'Grade' or 'Condition', a.condition or '-'),
        ('Presented by: %s'):format(a.holder or '-'),
        '',
        ('APPRAISED VALUE: %s'):format(Market.Money(a.value)),
        '',
        'Value at the date of appraisal, based on the LS Card Exchange market.',
        'Check the serial number on the card matches this letter.',
        '',
        'R. Hollis, Senior Appraiser',
    }, '\n')
end

local function esc(s) return (tostring(s or ''):gsub('[<>&"]', { ['<'] = '&lt;', ['>'] = '&gt;', ['&'] = '&amp;', ['"'] = '&quot;' })) end
local function letterHtml(a)
    return ('<h1>%s</h1><h2>Certificate of appraisal</h2><p>Reference %s &middot; %s</p>'
        .. '<p>This is to certify that the trading card described below has been examined and appraised.</p>'
        .. '<table><tr><td>Card</td><td><b>%s</b></td></tr><tr><td>Serial number</td><td>%s</td></tr><tr><td>%s</td><td>%s</td></tr>'
        .. '<tr><td>Presented by</td><td>%s</td></tr><tr><td><b>Appraised value</b></td><td><b>%s</b></td></tr></table>'
        .. '<p><small>Value at the date of appraisal, based on the LS Card Exchange market. Card prices change over time. Check the serial number on the card matches this letter.</small></p>'
        .. '<p>R. Hollis<br>Senior Appraiser</p>'):format(esc(a.issuer or 'LS Card Exchange Appraisals'), esc(a.ref), esc(a.date), esc(a.title), esc(a.serial),
            a.graded and 'Grade' or 'Condition', esc(a.condition), esc(a.holder), esc(Market.Money(a.value)))
end

-- rich text for as-computer's Notepad / File Explorer (only b, p, h1, h2, br survive there)
local function letterNote(a)
    return ('<h1>%s</h1><h2>Certificate of appraisal</h2><p>Reference: %s<br>Date: %s</p>'
        .. '<p><b>Card:</b> %s<br><b>Serial number:</b> %s<br><b>%s:</b> %s<br><b>Presented by:</b> %s</p>'
        .. '<h2>Appraised value: %s</h2><p>Value at the date of appraisal, based on the LS Card Exchange market. Check the serial number on the card matches this letter.</p>'
        .. '<p>R. Hollis, Senior Appraiser</p>'):format(esc(a.issuer or 'LS Card Exchange Appraisals'), esc(a.ref), esc(a.date), esc(a.title), esc(a.serial),
            a.graded and 'Grade' or 'Condition', esc(a.condition), esc(a.holder), esc(Market.Money(a.value)))
end

-- save to the character's Downloads folder on as-computer (any computer they log into)
function Appraisal.SaveToComputer(src, identifier, ref)
    local a = letterFor(identifier, ref)
    if not a then return nil, 'Letter not found.' end
    if GetResourceState('as-computer') ~= 'started' then return nil, 'Computers aren’t available.' end
    local ok, id, why = pcall(function() return exports['as-computer']:saveToDownloads(identifier, ('Appraisal %s'):format(a.ref), letterNote(a), 'LS Card Exchange') end)
    if not ok then return nil, 'Your computer can’t take downloads yet (as-computer needs the saveToDownloads export).' end
    if not id then return nil, why == 'full' and 'Your Downloads folder is full.' or 'Could not save it to your computer.' end
    return { saved = true }
end

-- save to the phone's Files app
function Appraisal.SaveToPhone(src, identifier, ref)
    local a = letterFor(identifier, ref)
    if not a then return nil, 'Letter not found.' end
    if GetResourceState('sd-phone') ~= 'started' then return nil, 'The phone isn’t available.' end
    local ok = pcall(function()
        exports['sd-phone']:createDocument(src, { name = ('Appraisal %s'):format(a.ref), kind = 'text', content = letterText(a), folder = 'Card Exchange', deletable = true })
    end)
    if not ok then return nil, 'Could not save it to your phone.' end
    return { saved = true }
end

-- print it (as-printer). choice = { printer, colour, design, letterhead } from the print dialog
function Appraisal.Print(src, identifier, ref, choice)
    local a = letterFor(identifier, ref)
    if not a then return nil, 'Letter not found.' end
    if GetResourceState('as-printer') ~= 'started' then return nil, 'Printing isn’t available.' end
    choice = type(choice) == 'table' and choice or {}
    local ok, res = pcall(function()
        return exports['as-printer']:print(src, { title = ('Appraisal %s'):format(a.ref), pages = { letterHtml(a) }, copyable = false },
            { printer = tostring(choice.printer or ''):sub(1, 64), colour = choice.colour == true, design = tostring(choice.design or ''):sub(1, 24), letterhead = tostring(choice.letterhead or ''):sub(1, 48) })
    end)
    if not ok or type(res) ~= 'table' then return nil, 'Could not print.' end
    if not res.ok then return nil, res.error or 'Could not print.' end
    return { pages = res.pages, seconds = res.seconds, printer = res.printer }
end

lib.callback.register('as-tradingcards:server:appraisalSave', function(src, ref)
    local id = Framework.GetIdentifier(src)
    if not id then return nil end
    local r, e = Appraisal.SaveToPhone(src, id, ref)
    Framework.Notify(src, r and 'Saved to your phone (Files → Card Exchange).' or e, r and 'success' or 'error')
    return r
end)

-- using the letter shows it
function Appraisal.View(src, item)
    local a = item.metadata and item.metadata.appraisal
    if not a then return end
    TriggerClientEvent('as-tradingcards:client:viewAppraisal', src, a)
end

--[[ ---------------------------------------------------------------------------
    COLLECTION VALUE HISTORY
--------------------------------------------------------------------------- ]]
local VH = Config.ValueHistory or {}
ValueHistory = {}

local function today() local d = os.date('*t') return os.time({ year = d.year, month = d.month, day = d.day, hour = 12 }) end

function ValueHistory.Save(identifier, value)
    if not VH.enabled or not identifier then return end
    MySQL.insert('INSERT INTO ascard_value_history (identifier, `day`, value) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE value = VALUES(value)', { identifier, today(), math.floor(value) })
end

function ValueHistory.Get(identifier)
    local out = {}
    local since = os.time() - (VH.days or 60) * 86400
    for _, r in ipairs(MySQL.query.await('SELECT `day`, value FROM ascard_value_history WHERE identifier = ? AND `day` >= ? ORDER BY `day`', { identifier, since }) or {}) do
        out[#out + 1] = { r.day, r.value }
    end
    return out
end

CreateThread(function()
    if not VH.enabled then return end
    while not (Market and Market.ready) do Wait(2000) end
    while true do
        Wait((VH.minutes or 30) * 60000)
        Market.EachOnline(function(s, id)
            local ok, p = pcall(Market.Portfolio, s)
            if ok and p then ValueHistory.Save(id, (p.total or 0) + (p.sealedTotal or 0)) end
        end)
        MySQL.update('DELETE FROM ascard_value_history WHERE `day` < ?', { os.time() - (VH.days or 60) * 86400 })
    end
end)

--[[ ---------------------------------------------------------------------------
    DAILY DISCORD MARKET REPORT
--------------------------------------------------------------------------- ]]
local function reportHook()
    local url = GetConvar('ascard_market_webhook', '')
    if url == '' then url = GetConvar('ascard_webhook', '') end
    return url
end

function MarketReport(force)
    local mr = (Config.Discord or {}).marketReport
    if not mr or (not mr.enabled and not force) then return false, 'The market report is turned off.' end
    local url = reportHook()
    if url == '' then return false, 'No webhook set (set ascard_market_webhook in server.cfg).' end
    local since = os.time() - 86400
    local function lines(rows, fmt)
        if #rows == 0 then return '—' end
        local t = {}
        for i, r in ipairs(rows) do t[#t + 1] = fmt(i, r) end
        return table.concat(t, '\n'):sub(1, 1000)
    end
    local sales = MySQL.query.await('SELECT title, price FROM ascard_sales WHERE sold_at >= ? ORDER BY price DESC LIMIT 5', { since }) or {}
    local pulls = MySQL.query.await('SELECT title, value FROM ascard_pull_log WHERE pulled_at >= ? ORDER BY value DESC LIMIT 5', { since }) or {}
    local vol = MySQL.single.await('SELECT COUNT(*) AS n, COALESCE(SUM(price), 0) AS total FROM ascard_sales WHERE sold_at >= ?', { since }) or {}
    local movers = Market.Movers()
    local live = 0
    for _ in pairs(Auctions and Auctions.live or {}) do live = live + 1 end
    local drops = Releases and Releases.Summary() or { live = 0, upcoming = 0 }
    local embed = {
        title = ('Card market report · %s'):format(os.date('%d %b %Y')),
        color = 0xe8a33b,
        description = ('**%d** auction sales in the last 24 hours (%s)  ·  **%d** live auctions%s'):format(vol.n or 0, Market.Money(vol.total or 0), live,
            (drops.live > 0 and ('  ·  **%d** release on sale now'):format(drops.live)) or (drops.upcoming > 0 and ('  ·  %d release coming soon'):format(drops.upcoming)) or ''),
        fields = {
            { name = 'Top sales (24h)', value = lines(sales, function(i, r) return ('%d. %s: **%s**'):format(i, r.title, Market.Money(r.price)) end), inline = false },
            { name = 'Biggest pulls (24h)', value = lines(pulls, function(i, r) return ('%d. %s (%s)'):format(i, r.title, Market.Money(r.value)) end), inline = false },
            { name = 'Rising (7 days)', value = lines(movers.up, function(i, r) return ('%s %s (+%s%%)'):format(r.name, Market.Money(r.price), r.change) end), inline = true },
            { name = 'Falling (7 days)', value = lines(movers.down, function(i, r) return ('%s %s (%s%%)'):format(r.name, Market.Money(r.price), r.change) end), inline = true },
        },
        footer = { text = (Config.Site and Config.Site.domain) or 'LS Card Exchange' },
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
    }
    PerformHttpRequest(url, function() end, 'POST', json.encode({ username = mr.username or 'LS Card Exchange', embeds = { embed } }), { ['Content-Type'] = 'application/json' })
    return true
end

CreateThread(function()
    local posted
    while true do
        Wait(30000)
        local mr = (Config.Discord or {}).marketReport
        if mr and mr.enabled and Market and Market.ready then
            local d = os.date('*t')
            local key = os.date('%Y%m%d')
            if d.hour == (mr.hour or 20) and d.min >= (mr.minute or 0) and posted ~= key then
                posted = key
                pcall(MarketReport)
            end
        end
    end
end)

lib.addCommand('cardreport', { help = 'Post the card market report to Discord now', restricted = Config.AdminAce }, function(src)
    local ok, err = MarketReport(true)
    local msg = ok and 'Market report posted to Discord.' or err
    if src and src > 0 then Framework.Notify(src, msg, ok and 'success' or 'error') else print(msg) end
end)

lib.callback.register('as-tradingcards:server:appraisalSaveComputer', function(src, ref)
    local id = Framework.GetIdentifier(src)
    if not id then return nil end
    local r, e = Appraisal.SaveToComputer(src, id, ref)
    Framework.Notify(src, r and 'Saved to your computer (File Explorer → Downloads).' or e, r and 'success' or 'error')
    return r
end)
