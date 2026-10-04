--[[ Market prices, price history, price alerts, checklist, stolen lookup and phone alerts.
     Prices: base value x supply x demand
       supply = ((average pulls of that card type + padding) / (this card's pulls + padding)) ^ elasticity
       demand = what auctions of this card actually sold for, compared with the supply price ]]
Market = {
    factor = {},      -- [cardId] = supply * demand
    supply = {},      -- [cardId]
    demand = {},      -- [cardId]
    sales = {},       -- [cardId] = number of recent sales counted
    avg = {},         -- [typeId] = average pulls
    weekAgo = {},     -- [cardId] = price about 7 days ago (for the % change)
    alerts = {},      -- [id] = price alert row
    updatedAt = 0,
    ready = false,
}

local MC = Config.Market or {}
local AL = Config.Alerts or {}
local RES = GetCurrentResourceName()

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

-- used by Utils.CardValue
function MarketFactor(cardId)
    if not (MC.enabled and Market.ready) then return 1 end
    return Market.factor[cardId] or 1
end

--[[ ---------------------------------------------------------------------------
    PLAYERS ONLINE / PHONE NOTIFICATIONS
--------------------------------------------------------------------------- ]]
local online = {}   -- [identifier] = src

function Market.Track(src)
    local id = Framework.GetIdentifier(src)
    if id then online[id] = src end
    return id
end

function Market.SourceOf(identifier)
    if not identifier then return nil end
    local src = online[identifier]
    if src and GetPlayerName(src) and Framework.GetIdentifier(src) == identifier then return src end
    online[identifier] = nil
    for _, s in ipairs(GetPlayers()) do
        s = tonumber(s)
        local id = Framework.GetIdentifier(s)
        if id then
            online[id] = s
            if id == identifier then return s end
        end
    end
end

function Market.EachOnline(fn)
    for _, s in ipairs(GetPlayers()) do
        s = tonumber(s)
        local id = Framework.GetIdentifier(s)
        if id then online[id] = s fn(s, id) end
    end
end

AddEventHandler('playerDropped', function()
    local src = source
    for id, s in pairs(online) do if s == src then online[id] = nil end end
end)

function Market.Notify(src, title, body)
    if not src then return end
    if GetResourceState('sd-phone') == 'started' and Config.Phone and Config.Phone.enabled then
        local ok = pcall(function()
            exports['sd-phone']:notify(src, {
                app = Config.Phone.identifier, appId = Config.Phone.identifier,
                title = title, body = body, time = 'now',
            })
        end)
        if ok then return end
    end
    Framework.Notify(src, ('%s: %s'):format(title, body), 'inform')
end

function Market.NotifyId(identifier, title, body)
    local src = Market.SourceOf(identifier)
    if src then Market.Notify(src, title, body) end
    return src
end

function Market.Money(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
    if out:sub(1, 1) == ',' then out = out:sub(2) end
    return '£' .. out
end

--[[ ---------------------------------------------------------------------------
    TABLES
--------------------------------------------------------------------------- ]]
CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `ascard_sales` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `card_id` VARCHAR(64) NULL,
            `item` VARCHAR(64) NOT NULL,
            `title` VARCHAR(160) NOT NULL,
            `kind` VARCHAR(16) NOT NULL DEFAULT 'card',
            `price` INT NOT NULL,
            `ratio` DOUBLE NULL,
            `sold_at` INT NOT NULL,
            PRIMARY KEY (`id`),
            KEY `card_time` (`card_id`, `sold_at`)
        )
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `ascard_price_history` (
            `card_id` VARCHAR(64) NOT NULL,
            `at` INT NOT NULL,
            `price` INT NOT NULL,
            PRIMARY KEY (`card_id`, `at`),
            KEY `at` (`at`)
        )
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `ascard_price_alerts` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `identifier` VARCHAR(64) NOT NULL,
            `card_id` VARCHAR(64) NOT NULL,
            `dir` VARCHAR(8) NOT NULL,
            `price` INT NOT NULL,
            `created_at` INT NOT NULL,
            PRIMARY KEY (`id`),
            KEY `identifier` (`identifier`)
        )
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `ascard_market_prefs` (
            `identifier` VARCHAR(64) NOT NULL,
            `locker` VARCHAR(64) NULL,
            `watch` LONGTEXT NULL,
            PRIMARY KEY (`identifier`)
        )
    ]])
    for _, row in ipairs(MySQL.query.await('SELECT * FROM ascard_price_alerts') or {}) do Market.alerts[row.id] = row end

    while not DB.Ready do Wait(200) end
    Market.Recompute()
    Market.LoadWeekAgo()
    Market.ready = true
    print(('^2[as-tradingcards] market ready: %d cards priced^0'):format(Market.count or 0))
end)

--[[ ---------------------------------------------------------------------------
    PRICES
--------------------------------------------------------------------------- ]]
local function baseValue(card)
    local t = Utils.RarityById[card.type]
    return card.value or (t and t.value) or 0
end
Market.BaseValue = baseValue

-- reference price: a mint raw base card
function Market.Price(cardId)
    local card = Config.Cards[cardId]
    if not card then return 0 end
    return math.max(1, math.floor(baseValue(card) * (Market.factor[cardId] or 1) + 0.5))
end

function Market.Change(cardId)
    local old = Market.weekAgo[cardId]
    if not old or old <= 0 then return 0 end
    return math.floor(((Market.Price(cardId) - old) / old) * 1000 + 0.5) / 10
end

local function median(list)
    table.sort(list)
    local n = #list
    if n == 0 then return nil end
    if n % 2 == 1 then return list[(n + 1) / 2] end
    return (list[n / 2] + list[n / 2 + 1]) / 2
end

function Market.Recompute()
    local sc, dc = MC.supply or {}, MC.demand or {}
    local sum, count = {}, {}
    for id, card in pairs(Config.Cards) do
        local p = DB.GetPrinted(id)
        sum[card.type] = (sum[card.type] or 0) + p
        count[card.type] = (count[card.type] or 0) + 1
    end
    for typeId, n in pairs(count) do Market.avg[typeId] = sum[typeId] / n end

    -- recent sales -> demand
    local byCard = {}
    local since = os.time() - (dc.days or 14) * 86400
    for _, row in ipairs(MySQL.query.await('SELECT card_id, ratio FROM ascard_sales WHERE sold_at >= ? AND card_id IS NOT NULL AND ratio IS NOT NULL', { since }) or {}) do
        byCard[row.card_id] = byCard[row.card_id] or {}
        table.insert(byCard[row.card_id], row.ratio)
    end

    local n = 0
    for id, card in pairs(Config.Cards) do
        local printed = DB.GetPrinted(id)
        local avg = Market.avg[card.type] or printed
        local pad = sc.padding or 25
        local supply = ((avg + pad) / (printed + pad)) ^ (sc.elasticity or 0.35)
        supply = clamp(supply, sc.min or 0.6, sc.max or 2.5)
        if card.maxPrints and printed >= card.maxPrints then supply = supply * (sc.soldOutBonus or 1) end

        local demand = 1
        local ratios = byCard[id]
        Market.sales[id] = ratios and #ratios or 0
        if ratios and #ratios >= (dc.minSales or 3) then
            local m = median(ratios)
            demand = clamp(1 + (m - 1) * (dc.weight or 0.5), dc.min or 0.6, dc.max or 1.8)
        end
        Market.supply[id], Market.demand[id], Market.factor[id] = supply, demand, supply * demand
        n = n + 1
    end
    Market.count = n
    Market.updatedAt = os.time()
    if Market.ready then Market.CheckAlerts() end
end

-- the price about a week ago, for the % change column
function Market.LoadWeekAgo()
    local since = os.time() - 7 * 86400
    local rows = MySQL.query.await([[
        SELECT h.card_id, h.price FROM ascard_price_history h
        JOIN (SELECT card_id, MIN(`at`) AS m FROM ascard_price_history WHERE `at` >= ? GROUP BY card_id) x
          ON x.card_id = h.card_id AND x.m = h.`at`
    ]], { since }) or {}
    local t = {}
    for _, r in ipairs(rows) do t[r.card_id] = r.price end
    Market.weekAgo = t
end

function Market.SaveHistory()
    local step = (MC.historyMinutes or 60) * 60
    local at = math.floor(os.time() / step) * step
    local values, params = {}, {}
    for id in pairs(Config.Cards) do
        values[#values + 1] = '(?, ?, ?)'
        params[#params + 1] = id
        params[#params + 1] = at
        params[#params + 1] = Market.Price(id)
        if #values >= 400 then
            MySQL.insert.await('INSERT INTO ascard_price_history (card_id, `at`, price) VALUES ' .. table.concat(values, ',') .. ' ON DUPLICATE KEY UPDATE price = VALUES(price)', params)
            values, params = {}, {}
        end
    end
    if #values > 0 then
        MySQL.insert.await('INSERT INTO ascard_price_history (card_id, `at`, price) VALUES ' .. table.concat(values, ',') .. ' ON DUPLICATE KEY UPDATE price = VALUES(price)', params)
    end
    MySQL.update('DELETE FROM ascard_price_history WHERE `at` < ?', { os.time() - (MC.historyDays or 30) * 86400 })
end

function Market.History(cardId)
    local since = os.time() - (MC.historyDays or 30) * 86400
    local out = {}
    for _, r in ipairs(MySQL.query.await('SELECT `at`, price FROM ascard_price_history WHERE card_id = ? AND `at` >= ? ORDER BY `at`', { cardId, since }) or {}) do
        out[#out + 1] = { r.at, r.price }
    end
    out[#out + 1] = { os.time(), Market.Price(cardId) }
    return out
end

-- a finished auction: feeds demand for that card
function Market.RecordSale(itemName, meta, price, title, kind)
    local cardId = type(meta) == 'table' and meta.cardId or nil
    local ratio = nil
    if cardId and Config.Cards[cardId] then
        -- compare with the value WITHOUT demand, so demand never feeds on itself
        Utils.ForceMarket = true
        local fair = Utils.CardValue(meta, itemName)
        Utils.ForceMarket = nil
        local d = Market.demand[cardId] or 1
        local supplyValue = fair / d
        if supplyValue > 0 then ratio = price / supplyValue end
    end
    MySQL.insert('INSERT INTO ascard_sales (card_id, item, title, kind, price, ratio, sold_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { cardId, itemName, tostring(title or itemName):sub(1, 160), kind or 'card', math.floor(price), ratio, os.time() })
    -- the sale moves the price straight away (not at the next scheduled update)
    SetTimeout(1000, function() if Market.ready and not (AdminFlags and AdminFlags.market) then Market.Recompute() end end)
end

CreateThread(function()
    while not Market.ready do Wait(1000) end
    local lastHistory = 0
    while true do
        if MC.enabled and os.time() - lastHistory >= (MC.historyMinutes or 60) * 60 then
            lastHistory = os.time()
            Market.SaveHistory()
            Market.LoadWeekAgo()
        end
        Wait((MC.recomputeMinutes or 10) * 60000)
        if MC.enabled and not (AdminFlags and AdminFlags.market) then Market.Recompute() end   -- staff can freeze prices
    end
end)

--[[ ---------------------------------------------------------------------------
    PRICE ALERTS
--------------------------------------------------------------------------- ]]
function Market.CheckAlerts()
    if not AL.priceAlerts then return end
    for id, a in pairs(Market.alerts) do
        local price = Market.Price(a.card_id)
        local hit = (a.dir == 'above' and price >= a.price) or (a.dir == 'below' and price <= a.price)
        if hit then
            local src = Market.SourceOf(a.identifier)
            if src then   -- only fires while they're online, so they actually see it
                local card = Config.Cards[a.card_id]
                Market.Notify(src, 'Price alert', ('%s is now %s (%s %s)'):format(
                    card and Utils.FullName(card) or a.card_id, Market.Money(price), a.dir == 'above' and 'above' or 'below', Market.Money(a.price)))
                Market.alerts[id] = nil
                MySQL.update('DELETE FROM ascard_price_alerts WHERE id = ?', { id })
            end
        end
    end
end

function Market.AlertsFor(identifier)
    local out = {}
    for _, a in pairs(Market.alerts) do
        if a.identifier == identifier then
            local card = Config.Cards[a.card_id]
            out[#out + 1] = { id = a.id, cardId = a.card_id, name = card and Utils.FullName(card) or a.card_id, dir = a.dir, price = a.price, now = Market.Price(a.card_id) }
        end
    end
    table.sort(out, function(x, y) return x.id > y.id end)
    return out
end

function Market.AddAlert(identifier, cardId, dir, price)
    if not AL.priceAlerts then return nil, 'Price alerts are turned off.' end
    if not Config.Cards[cardId] then return nil, 'Unknown card.' end
    if dir ~= 'above' and dir ~= 'below' then return nil, 'Pick above or below.' end
    price = math.floor(tonumber(price) or 0)
    if price < 1 or price > 100000000 then return nil, 'Enter a price.' end
    local mine = 0
    for _, a in pairs(Market.alerts) do if a.identifier == identifier then mine = mine + 1 end end
    if mine >= (AL.maxPriceAlerts or 10) then return nil, ('You can have %d price alerts at once.'):format(AL.maxPriceAlerts or 10) end
    local now = os.time()
    local id = MySQL.insert.await('INSERT INTO ascard_price_alerts (identifier, card_id, dir, price, created_at) VALUES (?, ?, ?, ?, ?)', { identifier, cardId, dir, price, now })
    if not id then return nil, 'Could not save that alert.' end
    Market.alerts[id] = { id = id, identifier = identifier, card_id = cardId, dir = dir, price = price, created_at = now }
    return true
end

function Market.DeleteAlert(identifier, id)
    local a = Market.alerts[tonumber(id)]
    if not a or a.identifier ~= identifier then return nil, 'Alert not found.' end
    Market.alerts[a.id] = nil
    MySQL.update('DELETE FROM ascard_price_alerts WHERE id = ?', { a.id })
    return true
end

--[[ ---------------------------------------------------------------------------
    GRADING READY ALERTS
--------------------------------------------------------------------------- ]]
CreateThread(function()
    if not AL.gradingReady then return end
    while not DB.Ready do Wait(500) end
    local told = {}
    -- anything already ready when the server starts isn't news
    for _, r in ipairs(MySQL.query.await('SELECT id FROM ascard_grading WHERE collected = 0 AND ready_at <= ?', { os.time() }) or {}) do told[r.id] = true end
    while true do
        Wait(30000)
        local rows = MySQL.query.await('SELECT id, identifier, item, metadata FROM ascard_grading WHERE collected = 0 AND ready_at <= ?', { os.time() }) or {}
        for _, r in ipairs(rows) do
            if not told[r.id] then
                local src = Market.SourceOf(r.identifier)
                if src then
                    told[r.id] = true
                    local meta = json.decode(r.metadata or '{}') or {}
                    Market.Notify(src, 'Grading ready', ('%s is back from grading. Collect it at the card shop.'):format(Utils.CardTitle(meta, r.item)))
                end
            end
        end
    end
end)

--[[ ---------------------------------------------------------------------------
    PRICE GUIDE LISTS
--------------------------------------------------------------------------- ]]
local cardList = {}   -- sorted by set then number
for id, card in pairs(Config.Cards) do cardList[#cardList + 1] = card end
table.sort(cardList, function(a, b)
    if a.set ~= b.set then return a.set < b.set end
    if (a.number or 0) ~= (b.number or 0) then return (a.number or 0) < (b.number or 0) end
    return a.id < b.id
end)
Market.CardList = cardList

local function typeLabel(typeId) local t = Utils.RarityById[typeId] return t and t.label or typeId end

function Market.CardRow(card)
    local club = Config.Clubs[card.club] or {}
    return {
        id = card.id, name = Utils.FullName(card), code = Utils.CardCode(card), set = card.set,
        type = card.type, typeLabel = typeLabel(card.type), club = club.label or '', clubShort = club.short or '',
        price = Market.Price(card.id), change = Market.Change(card.id),
        printed = DB.GetPrinted(card.id), maxPrints = card.maxPrints, rookie = Utils.Rookie[card.id] or nil,
    }
end

function Market.Search(q)
    q = q or {}
    local text = tostring(q.search or ''):lower():gsub('^%s+', ''):gsub('%s+$', '')
    local typeId = q.type ~= '' and q.type or nil
    local sort = q.sort or 'price'
    local list = {}
    for _, card in ipairs(cardList) do
        if (not typeId or card.type == typeId) then
            local ok = text == ''
            if not ok then
                local club = Config.Clubs[card.club] or {}
                local hay = (Utils.FullName(card) .. ' ' .. (club.label or '') .. ' ' .. Utils.CardCode(card) .. ' ' .. card.id):lower()
                ok = hay:find(text, 1, true) ~= nil
            end
            if ok then list[#list + 1] = card end
        end
    end
    if sort == 'price' then table.sort(list, function(a, b) return Market.Price(a.id) > Market.Price(b.id) end)
    elseif sort == 'cheap' then table.sort(list, function(a, b) return Market.Price(a.id) < Market.Price(b.id) end)
    elseif sort == 'up' then table.sort(list, function(a, b) return Market.Change(a.id) > Market.Change(b.id) end)
    elseif sort == 'down' then table.sort(list, function(a, b) return Market.Change(a.id) < Market.Change(b.id) end)
    elseif sort == 'name' then table.sort(list, function(a, b) return Utils.FullName(a) < Utils.FullName(b) end)
    end
    local per = 30
    local page = math.max(1, math.floor(tonumber(q.page) or 1))
    local rows = {}
    for i = (page - 1) * per + 1, math.min(#list, page * per) do rows[#rows + 1] = Market.CardRow(list[i]) end
    return { rows = rows, total = #list, page = page, pages = math.max(1, math.ceil(#list / per)) }
end

function Market.Movers()
    local up, down = {}, {}
    for _, card in ipairs(cardList) do
        local c = Market.Change(card.id)
        if c > 0 then up[#up + 1] = card elseif c < 0 then down[#down + 1] = card end
    end
    table.sort(up, function(a, b) return Market.Change(a.id) > Market.Change(b.id) end)
    table.sort(down, function(a, b) return Market.Change(a.id) < Market.Change(b.id) end)
    local o = { up = {}, down = {} }
    for i = 1, math.min(5, #up) do o.up[i] = Market.CardRow(up[i]) end
    for i = 1, math.min(5, #down) do o.down[i] = Market.CardRow(down[i]) end
    return o
end

function Market.SealedList()
    local out = {}
    for _, e in ipairs(Series2.ShopItems()) do
        if Utils.Sealed[e.item] then
            local now = Utils.SealedValue(e.item)
            out[#out + 1] = { item = e.item, label = e.label, shop = e.price, value = now,
                              buyer = math.floor(now * ((Config.Sealed or {}).buyerPays or 0.8)),
                              left = Stock and Stock.Left(e.item) or nil }
        end
    end
    return out
end

-- prices of every version of one card
function Market.Variants(cardId)
    local card = Config.Cards[cardId]
    local item = Utils.RarityById[card.type].item
    Utils.ForceMarket = true
    local function v(meta, it) meta.cardId = cardId return Utils.CardValue(meta, it or item) end
    local out = { { label = 'Base (mint, raw)', price = v({}) } }
    out[#out + 1] = { label = Config.Foil.label, price = v({ foil = true }) }
    for _, par in ipairs(Config.Parallels or {}) do
        out[#out + 1] = { label = ('%s /%d'):format(par.label, par.maxPrints), price = v({ parallel = par.id }) }
    end
    for _, ins in ipairs((Config.Inserts or {}).types or {}) do
        out[#out + 1] = { label = ('%s /%d'):format(ins.label, ins.maxPrints), price = v({ insert = ins.id }) }
    end
    for _, g in ipairs({ 10, 9, 8, 7 }) do
        out[#out + 1] = { label = ('Graded %d (%s)'):format(g, Config.Grading.labels[g] or ''), price = v({ grade = g }, Config.Items.slab) }
    end
    Utils.ForceMarket = nil
    return out
end

function Market.CardDetail(cardId)
    local card = Config.Cards[cardId]
    if not card then return nil, 'Card not found.' end
    local row = Market.CardRow(card)
    row.number = card.number
    row.pos, row.nation, row.att, row.def = card.pos, card.nation, card.att, card.def
    row.setLabel = (Config.Sets[card.set] or {}).label
    row.avgPrinted = math.floor((Market.avg[card.type] or 0) + 0.5)
    row.supply = math.floor((Market.supply[cardId] or 1) * 100 + 0.5) / 100
    row.demand = math.floor((Market.demand[cardId] or 1) * 100 + 0.5) / 100
    row.salesCounted = Market.sales[cardId] or 0
    row.soldOut = card.maxPrints and row.printed >= card.maxPrints or false
    row.variants = Market.Variants(cardId)
    row.history = Market.History(cardId)
    row.sales = {}
    for _, s in ipairs(MySQL.query.await('SELECT title, price, sold_at FROM ascard_sales WHERE card_id = ? ORDER BY sold_at DESC LIMIT 10', { cardId }) or {}) do
        row.sales[#row.sales + 1] = { title = s.title, price = s.price, at = s.sold_at }
    end
    row.liveAuctions = Auctions and Auctions.CountForCard(cardId) or 0
    row.pop = Pop and Pop.Report(cardId) or nil
    return row
end

--[[ ---------------------------------------------------------------------------
    CHECKLIST (every card in the set: pulled before / holding now)
--------------------------------------------------------------------------- ]]
local function holding(src)
    local held = {}
    for _, item in ipairs(Inventory.GetItems(src, function(n) return Utils.IsCollectible(n) or n == Config.Items.binder end)) do
        local m = item.metadata or {}
        if item.name == Config.Items.binder then
            if m.binderId then
                for _, row in pairs(DB.GetBinder(m.binderId)) do
                    local cid = row.metadata and row.metadata.cardId
                    if cid then held[cid] = true end
                end
            end
        elseif m.cardId then
            held[m.cardId] = true
        end
    end
    return held
end

function Market.Checklist(src, identifier)
    local pulled = DB.GetCollection(identifier)
    local held = holding(src)
    local sets = {}
    for setId, set in pairs(Config.Sets) do sets[setId] = { id = setId, label = set.label, code = set.code, cards = {}, have = 0, pulled = 0 } end
    for _, card in ipairs(cardList) do
        local s = sets[card.set]
        if s then
            local p, h = pulled[card.id] ~= nil, held[card.id] == true
            if h then s.have = s.have + 1 end
            if p or h then s.pulled = s.pulled + 1 end
            local club = Config.Clubs[card.club] or {}
            -- compact: id, code, name, type, club short, pulled, holding, price
            s.cards[#s.cards + 1] = { card.id, Utils.CardCode(card), Utils.FullName(card), card.type, club.short or '', (p or h) and 1 or 0, h and 1 or 0, Market.Price(card.id),
                (Wants and Wants.Has(identifier, card.id)) and 1 or 0 }
        end
    end
    local out = {}
    for _, s in pairs(sets) do s.total = #s.cards out[#out + 1] = s end
    table.sort(out, function(a, b) return a.id < b.id end)
    local types = {}
    for _, t in ipairs(Config.Types) do types[#types + 1] = { id = t.id, label = t.label } end
    return { sets = out, types = types }
end

--[[ ---------------------------------------------------------------------------
    STOLEN CHECK / MY PULLS
--------------------------------------------------------------------------- ]]
local function cleanSerial(s) return tostring(s or ''):upper():gsub('%s', ''):sub(1, 64) end

function Market.CheckSerial(serial)
    serial = cleanSerial(serial)
    if #serial < 4 then return nil, 'Enter the serial number printed on the card.' end
    local row = MySQL.single.await('SELECT card_id, UNIX_TIMESTAMP(pulled_at) AS pulled_at FROM ascard_owners WHERE serial = ?', { serial })
    local stolen = MySQL.single.await('SELECT reported_at FROM ascard_stolen WHERE serial = ?', { serial })
    local card = row and Config.Cards[row.card_id]
    -- history: pulled, graded, sold, reported stolen...
    local events = {}
    if row and row.pulled_at then events[#events + 1] = { kind = 'pulled', detail = 'Pulled from a pack', at = tonumber(row.pulled_at) or row.pulled_at } end
    if row and SerialLog then
        for _, e in ipairs(SerialLog.Get(serial)) do
            if e.kind ~= 'auction' then events[#events + 1] = e end
        end
        -- auction sales come from the auction house records (singles and lots)
        local like = '%"serial":"' .. serial:gsub('[%%_]', '') .. '"%'
        for _, a in ipairs(MySQL.query.await("SELECT id, final_price, ends_at, lot IS NOT NULL AS isLot FROM ascard_auctions WHERE status = 'sold' AND (serial = ? OR lot LIKE ?) ORDER BY ends_at", { serial, like }) or {}) do
            events[#events + 1] = { kind = 'auction', detail = ('Sold at auction #%d for %s%s'):format(a.id, Market.Money(a.final_price or 0), (a.isLot == 1 or a.isLot == true) and ' (in a lot)' or ''), at = a.ends_at }
        end
    end
    for i, e in ipairs(events) do e.i = i end
    table.sort(events, function(x, y)
        local ax, ay = tonumber(x.at) or 0, tonumber(y.at) or 0
        if ax ~= ay then return ax < ay end
        return x.i < y.i
    end)
    return {
        serial = serial,
        known = row ~= nil or #events > 0,
        stolen = stolen ~= nil,
        reportedAt = stolen and stolen.reported_at or nil,
        pulledAt = row and row.pulled_at or nil,
        events = events,
        card = card and { id = card.id, name = Utils.FullName(card), code = Utils.CardCode(card), typeLabel = typeLabel(card.type), set = (Config.Sets[card.set] or {}).label } or nil,
    }
end

function Market.Pulls(identifier)
    local out = {}
    for _, row in ipairs(DB.OwnedSerials(identifier)) do
        local card = Config.Cards[row.card_id]
        out[#out + 1] = { serial = row.serial, cardId = row.card_id, name = card and Utils.FullName(card) or row.card_id, stolen = DB.IsStolen(row.serial) }
    end
    return out
end

function Market.SetStolen(identifier, serial, stolen)
    serial = cleanSerial(serial)
    local owner = DB.GetOwner(serial)
    if not owner then return nil, 'That serial is not on record.' end
    if owner ~= identifier then return nil, 'Only the person who pulled this card can report it.' end
    if stolen then DB.ReportStolen(serial, identifier) else DB.ClearStolen(serial) end
    if SerialLog then SerialLog.Add(serial, stolen and 'stolen' or 'found', stolen and 'Reported stolen by the owner' or 'Marked as recovered') end
    return { serial = serial, stolen = stolen and true or false }
end

--[[ ---------------------------------------------------------------------------
    MY CARDS: every card you hold (pockets + binders) and what it's worth right now.
    Same number the card shop pays, so condition, grade, parallel etc. all count.
--------------------------------------------------------------------------- ]]
local function portfolioRow(itemName, m, where)
    local card = m.cardId and Config.Cards[m.cardId]
    return {
        title = Utils.CardTitle(m, itemName), value = Utils.CardValue(m, itemName), where = where,
        cardId = m.cardId, serial = m.serial, typeLabel = card and typeLabel(card.type) or nil,
        thumb = {
            cardId = m.cardId, graded = m.grade ~= nil, grade = m.grade, foil = m.foil or nil,
            parallel = m.parallel and Utils.ParallelById[m.parallel] and Utils.ParallelById[m.parallel].label or nil,
            insert = m.insert and Utils.InsertById[m.insert] and Utils.InsertById[m.insert].label or nil,
            error = m.error and Utils.ErrorById[m.error] and Utils.ErrorById[m.error].label or nil,
            rookie = m.cardId and Utils.Rookie[m.cardId] or nil, item = itemName,
        },
        condition = (type(m.cond) == 'table' and not m.grade) and Condition.Glance(m.cond) or nil,
    }
end

function Market.Portfolio(src)
    local rows, total, sealedTotal = {}, 0, 0
    for _, item in ipairs(Inventory.GetItems(src, function(n) return Utils.IsCollectible(n) or n == Config.Items.binder end)) do
        local m = item.metadata or {}
        if item.name == Config.Items.binder then
            if m.binderId then
                for _, row in pairs(DB.GetBinder(m.binderId)) do
                    if row.metadata and row.metadata.cardId then rows[#rows + 1] = portfolioRow(row.item, row.metadata, 'Binder') end
                end
            end
        elseif m.cardId then
            rows[#rows + 1] = portfolioRow(item.name, m, 'Pockets')
        end
    end
    if SlabCase then
        for _, s in ipairs(SlabCase.Contents(src)) do
            if s.metadata.cardId then rows[#rows + 1] = portfolioRow(s.name, s.metadata, 'Slab case') end
        end
    end
    for _, r in ipairs(rows) do total = total + r.value end
    local sealed = {}
    for _, item in ipairs(Inventory.GetItems(src, function(n) return Utils.Sealed[n] end)) do
        local pk = Config.Packs[item.name] or (Config.Boxes or {})[item.name] or {}
        local each = Utils.SealedValue(item.name)
        sealed[#sealed + 1] = { title = (pk.label or item.name), count = item.count, value = each * item.count, thumb = { item = item.name } }
        sealedTotal = sealedTotal + each * item.count
    end
    table.sort(rows, function(a, b) return a.value > b.value end)
    local out = { cards = rows, sealed = sealed, total = total, sealedTotal = sealedTotal, updatedAt = Market.updatedAt }
    if ValueHistory then
        local id = Framework.GetIdentifier(src)
        ValueHistory.Save(id, total + sealedTotal)
        out.history = ValueHistory.Get(id)
    end
    return out
end
