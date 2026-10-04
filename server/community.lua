--[[ Wantlist alerts, "This week" page (big sales, big pulls) and release days ]]

--[[ ---------------------------------------------------------------------------
    WANTLIST
--------------------------------------------------------------------------- ]]
Wants = { byCard = {}, byUser = {} }
local WC = Config.Wants or {}

local function addWant(identifier, cardId)
    Wants.byCard[cardId] = Wants.byCard[cardId] or {}
    Wants.byCard[cardId][identifier] = true
    Wants.byUser[identifier] = Wants.byUser[identifier] or {}
    Wants.byUser[identifier][cardId] = true
end

function Wants.Has(identifier, cardId)
    return Wants.byUser[identifier] and Wants.byUser[identifier][cardId] == true or false
end

function Wants.Toggle(identifier, cardId)
    if not WC.enabled then return nil, 'The wantlist is turned off.' end
    if not Config.Cards[cardId] then return nil, 'Unknown card.' end
    if Wants.Has(identifier, cardId) then
        Wants.byUser[identifier][cardId] = nil
        if Wants.byCard[cardId] then Wants.byCard[cardId][identifier] = nil end
        MySQL.update('DELETE FROM ascard_wants WHERE identifier = ? AND card_id = ?', { identifier, cardId })
        return { wanted = false }
    end
    local n = 0
    for _ in pairs(Wants.byUser[identifier] or {}) do n = n + 1 end
    if n >= (WC.max or 50) then return nil, ('Your wantlist is full (%d cards).'):format(WC.max or 50) end
    addWant(identifier, cardId)
    MySQL.insert('INSERT IGNORE INTO ascard_wants (identifier, card_id) VALUES (?, ?)', { identifier, cardId })
    return { wanted = true }
end

function Wants.List(identifier)
    local out = {}
    for cardId in pairs(Wants.byUser[identifier] or {}) do
        local card = Config.Cards[cardId]
        if card then
            out[#out + 1] = { cardId = cardId, name = Utils.FullName(card), code = Utils.CardCode(card), price = Market.Price(cardId),
                live = Auctions and Auctions.CountForCard(cardId) or 0 }
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- a new auction: ping everyone online who wants a card in it
function Wants.OnListed(row)
    if not WC.enabled then return end
    local cards = {}
    if row.lot then
        for _, it in ipairs(row.lot) do if it.metadata and it.metadata.cardId then cards[it.metadata.cardId] = true end end
    elseif row.card_id then
        cards[row.card_id] = true
    end
    local told = {}
    for cardId in pairs(cards) do
        for identifier in pairs(Wants.byCard[cardId] or {}) do
            if identifier ~= row.seller and not told[identifier] then
                told[identifier] = true
                local card = Config.Cards[cardId]
                Market.NotifyId(identifier, 'Wanted card listed', ('%s is up for auction: %s, starting at %s.'):format(
                    card and Utils.FullName(card) or cardId, row.title, Market.Money(row.start_price)))
            end
        end
    end
end

--[[ ---------------------------------------------------------------------------
    PULL LOG + THIS WEEK
--------------------------------------------------------------------------- ]]
Community = {}
local WK = Config.Weekly or {}

CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `ascard_wants` (
            `identifier` VARCHAR(64) NOT NULL,
            `card_id` VARCHAR(64) NOT NULL,
            PRIMARY KEY (`identifier`, `card_id`),
            KEY `card` (`card_id`)
        )
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `ascard_pull_log` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `serial` VARCHAR(64) NOT NULL,
            `identifier` VARCHAR(64) NOT NULL,
            `name` VARCHAR(80) NOT NULL,
            `card_id` VARCHAR(64) NOT NULL,
            `item` VARCHAR(64) NOT NULL,
            `title` VARCHAR(160) NOT NULL,
            `value` INT NOT NULL,
            `pulled_at` INT NOT NULL,
            PRIMARY KEY (`id`),
            KEY `time` (`pulled_at`)
        )
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `ascard_release_sales` (
            `release_id` VARCHAR(64) NOT NULL,
            `identifier` VARCHAR(64) NOT NULL,
            `qty` INT NOT NULL DEFAULT 0,
            PRIMARY KEY (`release_id`, `identifier`)
        )
    ]])
    for _, r in ipairs(MySQL.query.await('SELECT identifier, card_id FROM ascard_wants') or {}) do addWant(r.identifier, r.card_id) end
    Releases.Load()
end)

-- only notable pulls are logged: numbered parallels, hits, error cards, Legendary and Mythic cards
function Community.LogPull(src, meta, itemName)
    if not meta or not meta.cardId then return end
    local card = Config.Cards[meta.cardId]
    local notable = meta.parallel or meta.insert or meta.error or (card and (card.type == 'legend' or card.type == 'century'))
    if not notable then return end
    local identifier = Framework.GetIdentifier(src)
    if not identifier then return end
    MySQL.insert('INSERT INTO ascard_pull_log (serial, identifier, name, card_id, item, title, value, pulled_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        { meta.serial or '', identifier, Framework.GetName(src) or '?', meta.cardId, itemName, Utils.CardTitle(meta, itemName):sub(1, 160),
          Utils.CardValue(meta, itemName), os.time() })
end

local function mask(name)
    if WK.showPullerNames then return name end
    name = tostring(name or '?')
    return name:sub(1, 1) .. '***' .. name:sub(-1)
end

function Community.Weekly()
    local since = os.time() - 7 * 86400
    local out = { sales = {}, pulls = {}, movers = Market.Movers(), now = os.time() }
    for _, r in ipairs(MySQL.query.await('SELECT title, price, sold_at, card_id, item, kind FROM ascard_sales WHERE sold_at >= ? ORDER BY price DESC LIMIT 10', { since }) or {}) do
        out.sales[#out.sales + 1] = { title = r.title, price = r.price, at = r.sold_at, cardId = r.card_id, item = r.item, kind = r.kind }
    end
    for _, r in ipairs(MySQL.query.await('SELECT title, value, pulled_at, card_id, item, name FROM ascard_pull_log WHERE pulled_at >= ? ORDER BY value DESC LIMIT 10', { since }) or {}) do
        out.pulls[#out.pulls + 1] = { title = r.title, value = r.value, at = r.pulled_at, cardId = r.card_id, item = r.item, by = mask(r.name) }
    end
    local st = MySQL.single.await('SELECT COUNT(*) AS n, COALESCE(SUM(price), 0) AS total FROM ascard_sales WHERE sold_at >= ?', { since })
    out.salesCount, out.salesTotal = st and st.n or 0, st and st.total or 0
    local pc = MySQL.scalar.await('SELECT COUNT(*) FROM ascard_pull_log WHERE pulled_at >= ?', { since })
    out.bigPulls = pc or 0
    out.cardOfWeek = out.sales[1]
    return out
end

--[[ ---------------------------------------------------------------------------
    RELEASE DAYS
--------------------------------------------------------------------------- ]]
Releases = { sold = {}, mine = {}, announced = {} }
local RC = Config.Releases or {}
local bootTime = os.time()

local function parseTime(s)
    if type(s) ~= 'string' then return nil end
    local y, mo, d, h, mi = s:match('^(%d+)%-(%d+)%-(%d+)%s+(%d+):(%d+)')
    if not y then return nil end
    return os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = tonumber(h), min = tonumber(mi), sec = 0 })
end

local function times(r)
    local s = r.startsIn and (bootTime + r.startsIn) or parseTime(r.startsAt) or bootTime
    local e = r.endsIn and (bootTime + r.endsIn) or parseTime(r.endsAt)
    return s, e
end

local function byId(id)
    for _, r in ipairs(RC.list or {}) do if r.id == id then return r end end
end

function Releases.Load()
    for _, row in ipairs(MySQL.query.await('SELECT release_id, identifier, qty FROM ascard_release_sales') or {}) do
        Releases.sold[row.release_id] = (Releases.sold[row.release_id] or 0) + row.qty
        Releases.mine[row.release_id] = Releases.mine[row.release_id] or {}
        Releases.mine[row.release_id][row.identifier] = row.qty
    end
    -- anything already live when the server starts isn't announced again
    local now = os.time()
    for _, r in ipairs(RC.list or {}) do
        local s = times(r)
        if s <= now then Releases.announced[r.id] = true end
    end
    Releases.ready = true
end

local function state(r)
    local now = os.time()
    local s, e = times(r)
    local left = math.max(0, (r.quantity or 0) - (Releases.sold[r.id] or 0))
    if now < s then return 'upcoming', s, e, left end
    if left <= 0 then return 'soldout', s, e, left end
    if e and now >= e then return 'ended', s, e, left end
    return 'live', s, e, left
end

function Releases.List(identifier)
    local out = {}
    if not RC.enabled then return { list = out, now = os.time() } end
    for _, r in ipairs(RC.list or {}) do
        local st, s, e, left = state(r)
        local pk = Config.Packs[r.item] or (Config.Boxes or {})[r.item] or {}
        out[#out + 1] = { id = r.id, label = r.label or pk.label or r.item, description = r.description, item = r.item, price = r.price,
            quantity = r.quantity, left = left, perPlayer = r.perPlayer, mine = (Releases.mine[r.id] or {})[identifier] or 0,
            state = st, startsAt = s, endsAt = e }
    end
    local order = { live = 1, upcoming = 2, soldout = 3, ended = 4 }
    table.sort(out, function(a, b) if order[a.state] ~= order[b.state] then return order[a.state] < order[b.state] end return a.startsAt < b.startsAt end)
    return { list = out, now = os.time() }
end

function Releases.Summary()
    local live, upcoming = 0, 0
    if not RC.enabled then return { live = 0, upcoming = 0 } end
    for _, r in ipairs(RC.list or {}) do
        local st = state(r)
        if st == 'live' then live = live + 1 elseif st == 'upcoming' then upcoming = upcoming + 1 end
    end
    return { live = live, upcoming = upcoming }
end

local buying = {}
function Releases.Buy(src, identifier, id, qty)
    if not RC.enabled or not Releases.ready then return nil, 'Release days are turned off.' end
    local r = byId(tostring(id))
    if not r then return nil, 'Release not found.' end
    qty = math.floor(tonumber(qty) or 1)
    if qty < 1 then return nil, 'Pick how many.' end
    local st, _, _, left = state(r)
    if st == 'upcoming' then return nil, 'This release isn’t on sale yet.' end
    if st ~= 'live' then return nil, 'This release has sold out or ended.' end
    local mine = (Releases.mine[r.id] or {})[identifier] or 0
    if r.perPlayer and mine + qty > r.perPlayer then
        return nil, mine >= r.perPlayer and ('You’ve bought your limit of %d.'):format(r.perPlayer) or ('You can buy %d more.'):format(r.perPlayer - mine)
    end
    if qty > left then return nil, ('Only %d left.'):format(left) end
    if buying[r.id] then return nil, 'Busy, try again.' end
    buying[r.id] = true
    local cost = (r.price or 0) * qty
    local acc = (Config.Auctions or {}).account or 'bank'
    if (Framework.GetMoney(src, acc) or 0) < cost or not Framework.RemoveMoney(src, acc, cost, 'ascard-release') then
        buying[r.id] = nil
        return nil, ('You need %s in your %s.'):format(Market.Money(cost), acc)
    end
    if Stats then Stats.Add(identifier, 'spent', cost) end
    Releases.sold[r.id] = (Releases.sold[r.id] or 0) + qty
    Releases.mine[r.id] = Releases.mine[r.id] or {}
    Releases.mine[r.id][identifier] = mine + qty
    MySQL.insert.await('INSERT INTO ascard_release_sales (release_id, identifier, qty) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE qty = qty + VALUES(qty)', { r.id, identifier, qty })
    buying[r.id] = nil
    local pk = Config.Packs[r.item] or (Config.Boxes or {})[r.item] or {}
    local label = pk.label or r.label or r.item
    if MoneyLog then MoneyLog.Add(identifier, 'release', -cost, ('%dx %s (%s)'):format(qty, label, r.id)) end
    local sealed = Seals and Seals.IsBox(r.item) and (Config.Seals or {}).enabled
    local function newMeta() return sealed and Seals.New(r.item) or {} end
    local lot = nil
    if qty > 1 then
        lot = {}
        for i = 1, qty do lot[i] = { item = r.item, metadata = newMeta(), title = label } end
    end
    local ok, locker = Auctions.Deliver(identifier, r.item, qty > 1 and {} or newMeta(), qty > 1 and ('%dx %s'):format(qty, label) or label, Auctions.LockerFor(identifier), 'drop', lot)
    return { bought = qty, locker = locker and locker.label or nil }
end

CreateThread(function()
    while not (Releases.ready and Market.ready) do Wait(1000) end
    while true do
        Wait(15000)
        if RC.enabled and RC.announce then
            for _, r in ipairs(RC.list or {}) do
                if not Releases.announced[r.id] and state(r) == 'live' then
                    Releases.announced[r.id] = true
                    Market.EachOnline(function(s)
                        Market.Notify(s, 'Release day', ('%s is on sale now in the Card Market app: %s each, %d available.'):format(r.label or r.item, Market.Money(r.price or 0), r.quantity or 0))
                    end)
                end
            end
        end
    end
end)
