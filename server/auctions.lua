--[[ Online auctions (phone app + website)
     - The item leaves the seller's inventory when it is listed (it is held by the auction house).
     - A bid takes the money straight away; being outbid gives it back.
     - Buy it now is there until the first bid. A reserve hides the lowest price the seller will take.
     - A bid in the last minutes pushes the end back (anti-snipe).
     - The winner's item, and unsold / cancelled items going back to the seller, go to a Postal Prime locker.
     - Money for someone who is offline waits in ascard_payouts and is paid the moment they are online. ]]
Auctions = { live = {} }

local AC = Config.Auctions or {}
local AL = Config.Alerts or {}
local account = AC.account or 'bank'

--[[ ---------------------------------------------------------------------------
    TABLES + LOAD
--------------------------------------------------------------------------- ]]
local pendingPay = {}   -- [identifier] = true while money is waiting for them

-- take money only if they actually have it (QB/QBX let bank accounts go negative otherwise)
local function take(src, amount, reason)
    if amount <= 0 then return true end
    if (Framework.GetMoney(src, account) or 0) < amount then return false end
    return Framework.RemoveMoney(src, account, amount, reason)
end

local function decodeRow(r)
    r.metadata = type(r.metadata) == 'string' and (json.decode(r.metadata) or {}) or (r.metadata or {})
    if type(r.lot) == 'string' then r.lot = json.decode(r.lot) end
    if type(r.lot) ~= 'table' or #r.lot == 0 then r.lot = nil end
    return r
end

-- adds a column to an existing table (older installs)
local function ensureColumn(tbl, col, def)
    local n = MySQL.scalar.await('SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?', { tbl, col })
    if (tonumber(n) or 0) == 0 then MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN `%s` %s'):format(tbl, col, def)) end
end

local offers = {}        -- [offerId] = pending offer row
local sellerStats = {}   -- [identifier] = { pos, neu, neg }

CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `ascard_auctions` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `seller` VARCHAR(64) NOT NULL,
            `seller_name` VARCHAR(80) NOT NULL,
            `seller_locker` VARCHAR(64) NULL,
            `item` VARCHAR(64) NOT NULL,
            `metadata` LONGTEXT NOT NULL,
            `card_id` VARCHAR(64) NULL,
            `serial` VARCHAR(64) NULL,
            `title` VARCHAR(160) NOT NULL,
            `kind` VARCHAR(16) NOT NULL DEFAULT 'card',
            `start_price` INT NOT NULL,
            `buy_now` INT NULL,
            `reserve` INT NULL,
            `fee` INT NOT NULL DEFAULT 0,
            `bid` INT NULL,
            `bidder` VARCHAR(64) NULL,
            `bidder_name` VARCHAR(80) NULL,
            `bidder_locker` VARCHAR(64) NULL,
            `bids` INT NOT NULL DEFAULT 0,
            `created_at` INT NOT NULL,
            `ends_at` INT NOT NULL,
            `status` VARCHAR(12) NOT NULL DEFAULT 'live',
            `final_price` INT NULL,
            `reminded` TINYINT(1) NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            KEY `status` (`status`),
            KEY `seller` (`seller`),
            KEY `bidder` (`bidder`)
        )
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `ascard_bids` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `auction_id` INT NOT NULL,
            `bidder` VARCHAR(64) NOT NULL,
            `bidder_name` VARCHAR(80) NOT NULL,
            `amount` INT NOT NULL,
            `at` INT NOT NULL,
            PRIMARY KEY (`id`),
            KEY `auction` (`auction_id`),
            KEY `bidder` (`bidder`)
        )
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `ascard_payouts` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `identifier` VARCHAR(64) NOT NULL,
            `amount` INT NOT NULL,
            `reason` VARCHAR(120) NOT NULL,
            `created_at` INT NOT NULL,
            PRIMARY KEY (`id`),
            KEY `identifier` (`identifier`)
        )
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `ascard_deliveries` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `identifier` VARCHAR(64) NOT NULL,
            `item` VARCHAR(64) NOT NULL,
            `metadata` LONGTEXT NOT NULL,
            `title` VARCHAR(160) NOT NULL,
            `locker` VARCHAR(64) NULL,
            `status` VARCHAR(12) NOT NULL DEFAULT 'pending',
            `reason` VARCHAR(16) NOT NULL DEFAULT 'won',
            `created_at` INT NOT NULL,
            PRIMARY KEY (`id`),
            KEY `identifier` (`identifier`),
            KEY `status` (`status`)
        )
    ]])
    ensureColumn('ascard_auctions', 'lot', 'LONGTEXT NULL')
    ensureColumn('ascard_deliveries', 'lot', 'LONGTEXT NULL')
    ensureColumn('ascard_deliveries', 'message', 'VARCHAR(200) NULL')
    ensureColumn('ascard_deliveries', 'sender', 'VARCHAR(80) NULL')
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `ascard_offers` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `auction_id` INT NOT NULL,
            `buyer` VARCHAR(64) NOT NULL,
            `buyer_name` VARCHAR(80) NOT NULL,
            `buyer_locker` VARCHAR(64) NULL,
            `amount` INT NOT NULL,
            `status` VARCHAR(12) NOT NULL DEFAULT 'pending',
            `created_at` INT NOT NULL,
            PRIMARY KEY (`id`),
            KEY `auction` (`auction_id`),
            KEY `buyer` (`buyer`)
        )
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `ascard_ratings` (
            `auction_id` INT NOT NULL,
            `seller` VARCHAR(64) NOT NULL,
            `buyer` VARCHAR(64) NOT NULL,
            `buyer_name` VARCHAR(80) NOT NULL,
            `score` TINYINT NOT NULL,
            `comment` VARCHAR(120) NULL,
            `created_at` INT NOT NULL,
            PRIMARY KEY (`auction_id`),
            KEY `seller` (`seller`)
        )
    ]])
    for _, r in ipairs(MySQL.query.await("SELECT * FROM ascard_offers WHERE status = 'pending'") or {}) do offers[r.id] = r end
    for _, r in ipairs(MySQL.query.await('SELECT seller, score, COUNT(*) AS n FROM ascard_ratings GROUP BY seller, score') or {}) do
        local st = sellerStats[r.seller] or { pos = 0, neu = 0, neg = 0 }
        sellerStats[r.seller] = st
        if r.score > 0 then st.pos = st.pos + r.n elseif r.score < 0 then st.neg = st.neg + r.n else st.neu = st.neu + r.n end
    end
    for _, r in ipairs(MySQL.query.await("SELECT * FROM ascard_auctions WHERE status = 'live'") or {}) do
        Auctions.live[r.id] = decodeRow(r)
    end
    for _, r in ipairs(MySQL.query.await('SELECT DISTINCT identifier FROM ascard_payouts') or {}) do pendingPay[r.identifier] = true end
    Auctions.ready = true
end)

--[[ ---------------------------------------------------------------------------
    MONEY: pay now, or hold it until they're online
--------------------------------------------------------------------------- ]]
function Auctions.Credit(identifier, amount, reason)
    amount = math.floor(amount or 0)
    if amount <= 0 or not identifier then return end
    local src = Market.SourceOf(identifier)
    if src and Framework.AddMoney(src, account, amount, 'ascard-auction') then return true end
    MySQL.insert.await('INSERT INTO ascard_payouts (identifier, amount, reason, created_at) VALUES (?, ?, ?, ?)',
        { identifier, amount, tostring(reason or 'Card auction'):sub(1, 120), os.time() })
    pendingPay[identifier] = true
    return false
end

local function payWaiting(src, identifier)
    if not pendingPay[identifier] then return end
    local rows = MySQL.query.await('SELECT id, amount FROM ascard_payouts WHERE identifier = ?', { identifier }) or {}
    local total = 0
    for _, r in ipairs(rows) do
        -- delete first: whoever deletes the row is the one who pays it (never twice)
        if (MySQL.update.await('DELETE FROM ascard_payouts WHERE id = ?', { r.id }) or 0) > 0 then
            if Framework.AddMoney(src, account, r.amount, 'ascard-auction') then
                total = total + r.amount
            else
                MySQL.insert.await('INSERT INTO ascard_payouts (identifier, amount, reason, created_at) VALUES (?, ?, ?, ?)', { identifier, r.amount, 'Card auction', os.time() })
                return
            end
        end
    end
    pendingPay[identifier] = nil
    if total > 0 and AL.paidOut then
        Market.Notify(src, 'Card Market', ('%s from your card auctions has been paid into your %s.'):format(Market.Money(total), account))
    end
end

--[[ ---------------------------------------------------------------------------
    DELIVERY (Postal Prime locker, or straight into the pockets without it)
--------------------------------------------------------------------------- ]]
local function postal() return GetResourceState('as-postalprime') == 'started' end

function Auctions.Lockers()
    if not postal() then return {} end
    local ok, list = pcall(function() return exports['as-postalprime']:getLockers() end)
    return ok and list or {}
end

local function validLocker(id)
    local list = Auctions.Lockers()
    for _, l in ipairs(list) do if l.id == id then return l end end
    return list[1]
end

local function sendDelivery(row)
    local meta = type(row.metadata) == 'string' and (json.decode(row.metadata) or {}) or row.metadata
    local lot = type(row.lot) == 'string' and json.decode(row.lot) or row.lot
    if type(lot) ~= 'table' or #lot == 0 then lot = { { item = row.item, metadata = meta, title = row.title } } end
    if postal() then
        local locker = validLocker(row.locker)
        if not locker then return false end
        local d = AC.delivery or {}
        local ok, err = pcall(function()
            return exports['as-postalprime']:createParcel(row.identifier, {
                ref = 'ASC-D' .. row.id,
                sender = row.sender or d.sender or 'LS Card Exchange',
                message = row.message,
                note = row.message,
                lockerId = locker.id,
                prepSeconds = d.prepSeconds or 300,
                expireSeconds = d.expireSeconds or 172800,
                items = (function()
                    local list = {}
                    for _, it in ipairs(lot) do
                        list[#list + 1] = { item = it.item, label = tostring(it.title or it.item):sub(1, 60), icon = Utils.Sealed[it.item] and '📦' or '🃏', qty = 1, metadata = it.metadata or {} }
                    end
                    return list
                end)(),
            })
        end)
        -- pcall -> (ran, createParcel's ok, createParcel's reason)
        if ok and err == true then
            MySQL.update.await("UPDATE ascard_deliveries SET status = 'sent', locker = ? WHERE id = ?", { locker.id, row.id })
            return true, locker
        end
        return false
    end
    -- no Postal Prime: hand it over when they're online
    local src = Market.SourceOf(row.identifier)
    if not src or Inventory.FreeSlots(src) < #lot then return false end
    if (MySQL.update.await("UPDATE ascard_deliveries SET status = 'given' WHERE id = ? AND status = 'pending'", { row.id }) or 0) == 0 then return false end
    for _, it in ipairs(lot) do
        if not Inventory.AddItem(src, it.item, 1, it.metadata or {}) then
            print(('^1[as-tradingcards] delivery %d: could not add %s for %s^0'):format(row.id, it.item, row.identifier))
        end
    end
    Market.Notify(src, 'Card Market', ('%s has been added to your pockets.'):format(row.title))
    return true
end

-- reason: 'won' | 'returned' | 'drop'. lot = optional list of { item, metadata, title } sent together in one parcel
function Auctions.Deliver(identifier, item, meta, title, locker, reason, lot, message, sender)
    local id = MySQL.insert.await('INSERT INTO ascard_deliveries (identifier, item, metadata, title, locker, reason, created_at, lot, message, sender) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        { identifier, item, json.encode(meta or {}), tostring(title):sub(1, 160), locker, reason or 'won', os.time(), lot and json.encode(lot) or nil, message, sender })
    if not id then return false end
    local ok, l = sendDelivery({ id = id, identifier = identifier, item = item, metadata = meta or {}, title = tostring(title), locker = locker, lot = lot, message = message, sender = sender })
    return ok, l
end

local function deliverAuction(a, to, locker, reason)
    return Auctions.Deliver(to, a.item, a.metadata, a.title, locker, reason, a.lot)
end
Auctions.LockerFor = function(identifier) return nil end   -- set below

-- a parcel that sat in the locker too long comes back as a new parcel (the card is never lost)
AddEventHandler('as-postalprime:parcelExpired', function(cid, ref)
    local id = tonumber(tostring(ref or ''):match('^ASC%-D(%d+)$'))
    if not id then return end
    MySQL.update.await("UPDATE ascard_deliveries SET status = 'pending' WHERE id = ? AND status = 'sent'", { id })
end)
AddEventHandler('as-postalprime:parcelCollected', function(cid, ref)
    local id = tonumber(tostring(ref or ''):match('^ASC%-D(%d+)$'))
    if not id then return end
    MySQL.update("UPDATE ascard_deliveries SET status = 'collected' WHERE id = ?", { id })
end)

--[[ ---------------------------------------------------------------------------
    PREFERENCES (delivery locker, watch list)
--------------------------------------------------------------------------- ]]
local prefsCache = {}
function Auctions.Prefs(identifier)
    if prefsCache[identifier] then return prefsCache[identifier] end
    local row = MySQL.single.await('SELECT locker, watch FROM ascard_market_prefs WHERE identifier = ?', { identifier })
    local p = { locker = row and row.locker or nil, watch = row and row.watch and json.decode(row.watch) or {} }
    prefsCache[identifier] = p
    return p
end
local function savePrefs(identifier, p)
    prefsCache[identifier] = p
    MySQL.insert('INSERT INTO ascard_market_prefs (identifier, locker, watch) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE locker = VALUES(locker), watch = VALUES(watch)',
        { identifier, p.locker, json.encode(p.watch or {}) })
end
function Auctions.SetLocker(identifier, lockerId)
    local l = validLocker(lockerId)
    if not l or l.id ~= lockerId then return nil, 'Pick a locker from the list.' end
    local p = Auctions.Prefs(identifier)
    p.locker = l.id
    savePrefs(identifier, p)
    return { locker = l.id }
end
local function lockerFor(identifier)
    local p = Auctions.Prefs(identifier)
    local l = validLocker(p.locker)
    return l and l.id or p.locker
end
Auctions.LockerFor = lockerFor
function Auctions.ToggleWatch(identifier, auctionId)
    auctionId = tonumber(auctionId)
    local p = Auctions.Prefs(identifier)
    local watch, found = {}, false
    for _, id in ipairs(p.watch or {}) do
        if id == auctionId then found = true elseif Auctions.live[id] then watch[#watch + 1] = id end
    end
    if not found then
        if not Auctions.live[auctionId] then return nil, 'That auction has ended.' end
        if #watch >= (AC.maxBidsWatching or 50) then return nil, 'Your watch list is full.' end
        watch[#watch + 1] = auctionId
    end
    p.watch = watch
    savePrefs(identifier, p)
    return { watching = not found }
end
local function isWatching(identifier, auctionId)
    for _, id in ipairs(Auctions.Prefs(identifier).watch or {}) do if id == auctionId then return true end end
    return false
end

--[[ ---------------------------------------------------------------------------
    VIEWS
--------------------------------------------------------------------------- ]]
local function minNext(a)
    if not a.bid then return a.start_price end
    return a.bid + math.max(AC.minIncrement or 1, math.ceil(a.bid * (AC.minIncrementPct or 0)))
end

local function initials(name)
    name = tostring(name or '?')
    local first = name:sub(1, 1)
    local last = name:sub(-1)
    return first .. '***' .. last
end

local function kindOf(item, meta)
    if Utils.Sealed[item] then return 'sealed' end
    if meta.grade then return 'graded' end
    if meta.insert then return 'insert' end
    if meta.parallel then return 'parallel' end
    return 'card'
end

local function thumb(a)
    local m = a.metadata or {}
    return {
        cardId = m.cardId, graded = m.grade ~= nil, grade = m.grade, foil = m.foil or nil,
        parallel = m.parallel and Utils.ParallelById[m.parallel] and Utils.ParallelById[m.parallel].label or nil,
        insert = m.insert and Utils.InsertById[m.insert] and Utils.InsertById[m.insert].label or nil,
        error = m.error and Utils.ErrorById[m.error] and Utils.ErrorById[m.error].label or nil,
        rookie = m.cardId and Utils.Rookie[m.cardId] or nil,
        item = a.item,
    }
end

local function ratingOf(seller)
    local st = sellerStats[seller]
    if not st then return nil end
    local rated = st.pos + st.neg
    return { pct = rated > 0 and math.floor(st.pos / rated * 100 + 0.5) or 100, count = st.pos + st.neu + st.neg }
end
Auctions.RatingOf = ratingOf

local function pendingOffers(auctionId)
    local list = {}
    for _, o in pairs(offers) do if o.auction_id == auctionId then list[#list + 1] = o end end
    table.sort(list, function(x, y) return x.amount > y.amount end)
    return list
end

function Auctions.View(a, identifier, full)
    local v = {
        id = a.id, title = a.title, kind = a.kind, item = a.item, thumb = thumb(a),
        bid = a.bid, bids = a.bids, start = a.start_price, minNext = minNext(a),
        buyNow = (a.buy_now and a.bids == 0 and a.status == 'live') and a.buy_now or nil,
        hasReserve = a.reserve ~= nil, reserveMet = a.reserve == nil or (a.bid ~= nil and a.bid >= a.reserve),
        endsAt = a.ends_at, status = a.status, seller = a.seller_name,
        yours = identifier ~= nil and a.seller == identifier or nil,
        winning = identifier ~= nil and a.bidder == identifier or nil,
        serial = a.serial, finalPrice = a.final_price,
        lotCount = a.lot and #a.lot or nil,
        sellerRating = ratingOf(a.seller),
    }
    if v.buyNow and (AC.offers or {}).enabled then
        v.canOffer = true
        local po = pendingOffers(a.id)
        if v.yours then v.offerCount = #po end
        for _, o in ipairs(po) do if o.buyer == identifier then v.myOffer = o.amount end end
    end
    if full then
        if a.lot then
            v.lot = {}
            for _, it in ipairs(a.lot) do
                local m = it.metadata or {}
                v.lot[#v.lot + 1] = { title = it.title, thumb = thumb({ metadata = m, item = it.item }), kind = kindOf(it.item, m),
                    value = (m.cardId and Utils.CardValue(m, it.item)) or (Utils.Sealed[it.item] and Utils.SealedValue(it.item)) or 0, cardId = m.cardId }
            end
        end
        if v.yours and v.canOffer then
            v.offers = {}
            for _, o in ipairs(pendingOffers(a.id)) do v.offers[#v.offers + 1] = { id = o.id, name = initials(o.buyer_name), amount = o.amount, at = o.created_at } end
        end
        if v.canOffer then v.minOffer = math.max(a.start_price, math.ceil(a.buy_now * ((AC.offers or {}).minPercent or 0.5))) end
        local m = a.metadata or {}
        v.watching = identifier and isWatching(identifier, a.id) or false
        v.value = (m.cardId and Utils.CardValue(m, a.item)) or (Utils.Sealed[a.item] and Utils.SealedValue(a.item)) or nil
        if v.lot then v.value = 0 for _, it in ipairs(v.lot) do v.value = v.value + (it.value or 0) end end
        if m.grade then
            v.grade = { grade = m.grade, label = Config.Grading.labels[m.grade], sub = m.sub, cert = m.cert }
            v.pop = Pop and Pop.For(m) or nil
        elseif type(m.cond) == 'table' then
            local s = Condition.Scores(m.cond)
            v.condition = { glance = Condition.Glance(m.cond), prot = Condition.ProtLabel(m.prot) }
            v.condition.overall = s.overall
        end
        v.print = m.print
        local card = m.cardId and Config.Cards[m.cardId]
        v.maxPrints = card and card.maxPrints or nil
        v.stolen = a.serial and DB.IsStolen(a.serial) or false
        v.history = {}
        for _, b in ipairs(MySQL.query.await('SELECT bidder, bidder_name, amount, `at` FROM ascard_bids WHERE auction_id = ? ORDER BY id DESC LIMIT 20', { a.id }) or {}) do
            v.history[#v.history + 1] = { name = (identifier and b.bidder == identifier) and 'You' or initials(b.bidder_name), amount = b.amount, at = b.at }
        end
    end
    return v
end

function Auctions.CountForCard(cardId)
    local n = 0
    for _, a in pairs(Auctions.live) do if a.card_id == cardId then n = n + 1 end end
    return n
end

function Auctions.Browse(identifier, q)
    q = q or {}
    local text = tostring(q.search or ''):lower()
    local kind = q.kind ~= '' and q.kind or nil
    local list = {}
    for _, a in pairs(Auctions.live) do
        if (not kind or a.kind == kind) and (not q.cardId or a.card_id == q.cardId)
            and (text == '' or a.title:lower():find(text, 1, true)) then
            list[#list + 1] = a
        end
    end
    local sort = q.sort or 'ending'
    local function price(a) return a.bid or a.start_price end
    if sort == 'ending' then table.sort(list, function(x, y) return x.ends_at < y.ends_at end)
    elseif sort == 'new' then table.sort(list, function(x, y) return x.created_at > y.created_at end)
    elseif sort == 'low' then table.sort(list, function(x, y) return price(x) < price(y) end)
    elseif sort == 'high' then table.sort(list, function(x, y) return price(x) > price(y) end)
    elseif sort == 'bids' then table.sort(list, function(x, y) return x.bids > y.bids end)
    end
    local per = 20
    local page = math.max(1, math.floor(tonumber(q.page) or 1))
    local rows = {}
    for i = (page - 1) * per + 1, math.min(#list, page * per) do rows[#rows + 1] = Auctions.View(list[i], identifier) end
    return { rows = rows, total = #list, page = page, pages = math.max(1, math.ceil(#list / per)), now = os.time() }
end

function Auctions.Get(identifier, id)
    id = tonumber(id)
    local a = Auctions.live[id]
    if not a then
        local r = MySQL.single.await('SELECT * FROM ascard_auctions WHERE id = ?', { id })
        if not r then return nil, 'Auction not found.' end
        a = decodeRow(r)
    end
    local v = Auctions.View(a, identifier, true)
    v.now = os.time()
    return v
end

function Auctions.Mine(identifier)
    local out = { selling = {}, bidding = {}, watching = {}, ended = {}, now = os.time() }
    local bidOn = {}
    for _, r in ipairs(MySQL.query.await('SELECT DISTINCT auction_id FROM ascard_bids WHERE bidder = ?', { identifier }) or {}) do bidOn[r.auction_id] = true end
    for id, a in pairs(Auctions.live) do
        if a.seller == identifier then out.selling[#out.selling + 1] = Auctions.View(a, identifier)
        elseif bidOn[id] then out.bidding[#out.bidding + 1] = Auctions.View(a, identifier) end
    end
    for _, id in ipairs(Auctions.Prefs(identifier).watch or {}) do
        local a = Auctions.live[id]
        if a then out.watching[#out.watching + 1] = Auctions.View(a, identifier) end
    end
    for _, r in ipairs(MySQL.query.await([[
        SELECT * FROM ascard_auctions WHERE status <> 'live' AND (seller = ? OR bidder = ?) ORDER BY ends_at DESC LIMIT 25
    ]], { identifier, identifier }) or {}) do
        local v = Auctions.View(decodeRow(r), identifier)
        v.won = r.status == 'sold' and r.bidder == identifier or nil
        if v.won and (AC.ratings or {}).enabled then
            local rated = MySQL.scalar.await('SELECT score FROM ascard_ratings WHERE auction_id = ?', { r.id })
            if rated then v.rated = rated
            elseif os.time() - (r.ends_at or 0) <= ((AC.ratings or {}).days or 14) * 86400 then v.canRate = true end
        end
        out.ended[#out.ended + 1] = v
    end
    local byEnd = function(x, y) return x.endsAt < y.endsAt end
    table.sort(out.selling, byEnd) table.sort(out.bidding, byEnd) table.sort(out.watching, byEnd)
    out.offers = {}
    for _, o in pairs(offers) do
        local a = Auctions.live[o.auction_id]
        if o.buyer == identifier and a then
            local v = Auctions.View(a, identifier)
            v.offerAmount = o.amount
            out.offers[#out.offers + 1] = v
        end
    end
    out.deliveries = {}
    for _, d in ipairs(MySQL.query.await("SELECT id, title, status, reason, locker, created_at FROM ascard_deliveries WHERE identifier = ? ORDER BY id DESC LIMIT 10", { identifier }) or {}) do
        out.deliveries[#out.deliveries + 1] = { title = d.title, status = d.status, reason = d.reason, at = d.created_at }
    end
    return out
end

--[[ ---------------------------------------------------------------------------
    LISTING
--------------------------------------------------------------------------- ]]
function Auctions.Sellable(src)
    local out = {}
    for _, item in ipairs(Inventory.GetItems(src, Utils.IsCollectible)) do
        local m = item.metadata or {}
        out[#out + 1] = {
            slot = item.slot, serial = m.serial, item = item.name, title = Utils.CardTitle(m, item.name),
            kind = kindOf(item.name, m), value = Utils.CardValue(m, item.name), stolen = DB.IsStolen(m.serial) or nil,
            thumb = thumb({ metadata = m, item = item.name }),
        }
    end
    if AC.allowSealed then
        for _, item in ipairs(Inventory.GetItems(src, function(n) return Utils.Sealed[n] end)) do
            local pk = Config.Packs[item.name] or (Config.Boxes or {})[item.name] or {}
            out[#out + 1] = {
                slot = item.slot, item = item.name, kind = 'sealed', title = (pk.label or item.name) .. ' (sealed)',
                count = item.count, value = Utils.SealedValue(item.name), thumb = { item = item.name },
            }
        end
    end
    local durations = {}
    for _, d in ipairs(AC.durations or {}) do durations[#durations + 1] = { id = d.id, label = d.label, fee = d.fee } end
    return { items = out, durations = durations, finalValueFee = AC.finalValueFee or 0 }
end

local function durationById(id)
    for _, d in ipairs(AC.durations or {}) do if d.id == id then return d end end
end

local function countSelling(identifier)
    local n = 0
    for _, a in pairs(Auctions.live) do if a.seller == identifier then n = n + 1 end end
    return n
end

function Auctions.Create(src, identifier, data)
    if not AC.enabled or (AdminFlags and AdminFlags.auctions) then return nil, 'The auction house is closed right now.' end
    data = data or {}
    local dur = durationById(data.duration)
    if not dur then return nil, 'Pick how long the auction runs.' end
    local start = math.floor(tonumber(data.start) or 0)
    local buyNow = data.buyNow and math.floor(tonumber(data.buyNow) or 0) or nil
    local reserve = data.reserve and math.floor(tonumber(data.reserve) or 0) or nil
    if buyNow == 0 then buyNow = nil end
    if reserve == 0 then reserve = nil end
    local maxP = AC.maxPrice or 10000000
    if start < (AC.minStart or 1) or start > maxP then return nil, ('The starting price must be at least %s.'):format(Market.Money(AC.minStart or 1)) end
    if buyNow and (buyNow <= start or buyNow > maxP) then return nil, 'Buy it now must be higher than the starting price.' end
    if reserve and (reserve <= start or reserve > maxP) then return nil, 'The reserve must be higher than the starting price.' end
    if reserve and buyNow and reserve > buyNow then return nil, 'The reserve can’t be higher than buy it now.' end
    if countSelling(identifier) >= (AC.maxActivePerPlayer or 10) then return nil, ('You can have %d auctions running at once.'):format(AC.maxActivePerPlayer or 10) end

    -- one item, or a lot of several
    local picks = {}
    if type(data.slots) == 'table' and #data.slots > 0 then
        if #data.slots < 2 then return nil, 'A lot needs at least 2 items.' end
        if #data.slots > (AC.maxLot or 10) then return nil, ('A lot can hold up to %d items.'):format(AC.maxLot or 10) end
        for _, p in ipairs(data.slots) do picks[#picks + 1] = { slot = tonumber(type(p) == 'table' and p.slot or p), serial = type(p) == 'table' and p.serial or nil } end
    else
        picks[1] = { slot = tonumber(data.slot), serial = data.serial }
    end
    local seen, items = {}, {}
    for _, p in ipairs(picks) do
        if not p.slot or seen[p.slot] then return nil, 'Pick each item once.' end
        seen[p.slot] = true
        local item = Inventory.GetSlot(src, p.slot)
        if not item then return nil, 'That item is no longer in your pockets.' end
        local sealed = Utils.Sealed[item.name] and AC.allowSealed
        if not sealed then
            if not Utils.IsCollectible(item.name) then return nil, 'You can only auction trading cards and sealed product.' end
            if p.serial and item.metadata.serial ~= p.serial then return nil, 'A card moved in your pockets. Try again.' end
            if DB.IsStolen(item.metadata.serial) then return nil, 'A card in this listing has been reported stolen and can’t be listed.' end
        end
        local m = item.metadata or {}
        local t
        if sealed then
            local pk = Config.Packs[item.name] or (Config.Boxes or {})[item.name] or {}
            t = (pk.label or item.name) .. ' (sealed)'
        else
            t = Utils.CardTitle(m, item.name)
        end
        items[#items + 1] = { slot = item.slot, item = item.name, metadata = m, title = t, sealed = sealed,
            value = sealed and Utils.SealedValue(item.name) or Utils.CardValue(m, item.name) }
    end

    if not take(src, dur.fee, 'ascard-auction-fee') then
        return nil, ('You need %s in your %s for the listing fee.'):format(Market.Money(dur.fee), account)
    end
    local removed = {}
    for _, it in ipairs(items) do DB.Seen(src, it.metadata) end
    for _, it in ipairs(items) do
        if Inventory.RemoveItem(src, it.item, 1, it.slot, (Inventory.name == 'ox' and not it.sealed) and it.metadata or nil) then
            removed[#removed + 1] = it
        else
            for _, back in ipairs(removed) do Inventory.AddItem(src, back.item, 1, back.metadata) end
            if dur.fee > 0 then Framework.AddMoney(src, account, dur.fee, 'ascard-auction-fee-refund') end
            return nil, 'An item is no longer in your pockets.'
        end
    end

    table.sort(items, function(x, y) return x.value > y.value end)
    local head = items[1]
    local item, meta, title = { name = head.item }, head.metadata, head.title
    local lot = nil
    if #items > 1 then
        lot = {}
        for _, it in ipairs(items) do lot[#lot + 1] = { item = it.item, metadata = it.metadata, title = it.title } end
        local custom = tostring(data.title or ''):gsub('[%c<>]', ''):sub(1, 60)
        title = custom ~= '' and ('Lot: ' .. custom) or ('Lot of %d: %s + %d more'):format(#items, head.title, #items - 1)
    end
    local now = os.time()
    local row = {
        seller = identifier, seller_name = Framework.GetName(src), seller_locker = lockerFor(identifier),
        item = item.name, metadata = meta, card_id = (not lot) and meta.cardId or nil, serial = (not lot) and meta.serial or nil, title = title:sub(1, 160),
        kind = lot and 'lot' or kindOf(item.name, meta), start_price = start, buy_now = buyNow, reserve = reserve, fee = dur.fee,
        bids = 0, created_at = now, ends_at = now + dur.seconds, status = 'live', reminded = 0, lot = lot,
    }
    local id = MySQL.insert.await([[
        INSERT INTO ascard_auctions (seller, seller_name, seller_locker, item, metadata, card_id, serial, title, kind,
            start_price, buy_now, reserve, fee, bids, created_at, ends_at, status, lot)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, 'live', ?)
    ]], { row.seller, row.seller_name, row.seller_locker, row.item, json.encode(meta), row.card_id, row.serial, row.title, row.kind,
          start, buyNow, reserve, dur.fee, now, row.ends_at, lot and json.encode(lot) or nil })
    if not id then
        for _, it in ipairs(items) do Inventory.AddItem(src, it.item, 1, it.metadata) end
        if dur.fee > 0 then Framework.AddMoney(src, account, dur.fee, 'ascard-auction-fee-refund') end
        return nil, 'The auction house is busy. Try again.'
    end
    row.id = id
    Auctions.live[id] = row
    if MoneyLog and dur.fee > 0 then MoneyLog.Add(src, 'listing_fee', -dur.fee, ('#%d %s'):format(id, row.title)) end
    if Wants and Wants.OnListed then pcall(Wants.OnListed, row) end
    return { id = id }
end

--[[ ---------------------------------------------------------------------------
    BIDDING
--------------------------------------------------------------------------- ]]
local busy = {}   -- one bid at a time per auction (money calls can yield)

function Auctions.Bid(src, identifier, id, amount)
    id = tonumber(id)
    local a = Auctions.live[id]
    if AdminFlags and AdminFlags.auctions then return nil, 'Bidding is paused by staff right now.' end
    if not a or a.status ~= 'live' or a.ends_at <= os.time() then return nil, 'This auction has ended.' end
    if a.seller == identifier and not AC.allowSelfBid then return nil, 'You can’t bid on your own auction.' end
    amount = math.floor(tonumber(amount) or 0)
    local need = minNext(a)
    if amount < need then return nil, ('The lowest bid you can make is %s.'):format(Market.Money(need)) end
    if amount > (AC.maxPrice or 10000000) then return nil, 'That bid is too high.' end
    if a.buy_now and a.bids == 0 and amount >= a.buy_now then return Auctions.BuyNow(src, identifier, id) end
    if busy[id] then return nil, 'Someone else is bidding right now. Try again.' end
    busy[id] = true

    local prevBidder, prevBid = a.bidder, a.bid
    local charge = (prevBidder == identifier) and (amount - prevBid) or amount
    if not take(src, charge, 'ascard-auction-bid') then
        busy[id] = nil
        return nil, ('You need %s in your %s to place that bid.'):format(Market.Money(charge), account)
    end

    local now = os.time()
    local anti = AC.antiSnipe or {}
    local extended = false
    if anti.window and a.ends_at - now <= anti.window then
        a.ends_at = math.max(a.ends_at, now + (anti.extend or anti.window))
        extended = true
    end
    a.bid, a.bidder, a.bidder_name, a.bidder_locker = amount, identifier, Framework.GetName(src), lockerFor(identifier)
    a.bids = a.bids + 1
    MySQL.update.await('UPDATE ascard_auctions SET bid = ?, bidder = ?, bidder_name = ?, bidder_locker = ?, bids = ?, ends_at = ? WHERE id = ?',
        { a.bid, a.bidder, a.bidder_name, a.bidder_locker, a.bids, a.ends_at, id })
    MySQL.insert('INSERT INTO ascard_bids (auction_id, bidder, bidder_name, amount, `at`) VALUES (?, ?, ?, ?, ?)', { id, identifier, a.bidder_name, amount, now })
    busy[id] = nil

    if prevBidder and prevBidder ~= identifier then
        Auctions.Credit(prevBidder, prevBid, 'Outbid: ' .. a.title)
        if AL.outbid then
            Market.NotifyId(prevBidder, 'You’ve been outbid', ('%s is now %s. Your %s bid has been returned.'):format(a.title, Market.Money(amount), Market.Money(prevBid)))
        end
    end
    if a.bids == 1 then
        Market.NotifyId(a.seller, 'First bid', ('%s has a bid of %s.'):format(a.title, Market.Money(amount)))
        Auctions.ClearOffers(a, 'someone bid, so buy it now and offers ended')
    end
    return { bid = amount, endsAt = a.ends_at, extended = extended }
end

function Auctions.BuyNow(src, identifier, id)
    id = tonumber(id)
    local a = Auctions.live[id]
    if not a or a.status ~= 'live' or a.ends_at <= os.time() then return nil, 'This auction has ended.' end
    if AdminFlags and AdminFlags.auctions then return nil, 'Buying is paused by staff right now.' end
    if not a.buy_now or a.bids > 0 then return nil, 'Buy it now is no longer available.' end
    if a.seller == identifier and not AC.allowSelfBid then return nil, 'You can’t buy your own auction.' end
    if busy[id] then return nil, 'Someone else is bidding right now. Try again.' end
    busy[id] = true
    if not take(src, a.buy_now, 'ascard-auction-bin') then
        busy[id] = nil
        return nil, ('You need %s in your %s.'):format(Market.Money(a.buy_now), account)
    end
    a.bid, a.bidder, a.bidder_name, a.bidder_locker = a.buy_now, identifier, Framework.GetName(src), lockerFor(identifier)
    a.bids = 1
    MySQL.insert('INSERT INTO ascard_bids (auction_id, bidder, bidder_name, amount, `at`) VALUES (?, ?, ?, ?, ?)', { id, identifier, a.bidder_name, a.buy_now, os.time() })
    a.reserve = nil
    Auctions.Settle(a, true)
    busy[id] = nil
    return { bought = true, price = a.final_price }
end

function Auctions.Cancel(identifier, id)
    id = tonumber(id)
    local a = Auctions.live[id]
    if not a or a.seller ~= identifier then return nil, 'Auction not found.' end
    if a.bids > 0 then return nil, 'You can’t cancel an auction that has bids.' end
    if busy[id] then return nil, 'Try again in a moment.' end
    Auctions.live[id] = nil
    a.status = 'cancelled'
    MySQL.update.await("UPDATE ascard_auctions SET status = 'cancelled' WHERE id = ?", { id })
    Auctions.ClearOffers(a, 'the seller cancelled the listing')
    deliverAuction(a, a.seller, a.seller_locker, 'returned')
    return { cancelled = true }
end

-- staff removal (admin panel): refunds the top bidder and any offers, sends the item back to the seller
function Auctions.AdminCancel(id, reason)
    id = tonumber(id)
    local a = id and Auctions.live[id]
    if not a then return nil, 'That auction isn’t live.' end
    if busy[id] then return nil, 'Someone is bidding right now. Try again.' end
    Auctions.live[id] = nil
    a.status = 'cancelled'
    MySQL.update.await("UPDATE ascard_auctions SET status = 'cancelled' WHERE id = ?", { id })
    Auctions.ClearOffers(a, 'staff removed the listing')
    if a.bidder and a.bid then
        Auctions.Credit(a.bidder, a.bid, 'Auction removed: ' .. a.title)
        Market.NotifyId(a.bidder, 'Auction removed', ('%s was removed by staff. Your %s bid has been returned.'):format(a.title, Market.Money(a.bid)))
    end
    deliverAuction(a, a.seller, a.seller_locker, 'returned')
    if MoneyLog then MoneyLog.Add(a.seller, 'admin', 0, ('Auction #%d removed: %s. %s'):format(id, a.title, reason or '')) end
    Market.NotifyId(a.seller, 'Listing removed', ('%s was removed by staff. It’s being sent back to your locker.'):format(a.title))
    return true
end

--[[ ---------------------------------------------------------------------------
    SETTLING
--------------------------------------------------------------------------- ]]
function Auctions.Settle(a, bought, keepOfferId)
    if a.status ~= 'live' then return end
    Auctions.live[a.id] = nil
    Auctions.ClearOffers(a, 'the item sold', keepOfferId)
    local sold = a.bidder ~= nil and a.bid ~= nil and (a.reserve == nil or a.bid >= a.reserve)
    if sold then
        a.status, a.final_price = 'sold', a.bid
        MySQL.update.await("UPDATE ascard_auctions SET status = 'sold', final_price = ?, bid = ?, bidder = ?, bidder_name = ?, bidder_locker = ?, bids = ?, ends_at = ? WHERE id = ?",
            { a.bid, a.bid, a.bidder, a.bidder_name, a.bidder_locker, a.bids, bought and os.time() or a.ends_at, a.id })
        local fee = math.floor(a.bid * (AC.finalValueFee or 0))
        Auctions.Credit(a.seller, a.bid - fee, 'Sold: ' .. a.title)
        if Stats then Stats.Add(a.seller, 'auction_earned', a.bid - fee) Stats.Add(a.bidder, 'auction_spent', a.bid) end
        if MoneyLog then
            MoneyLog.Add(a.bidder, 'auction_buy', -a.bid, ('#%d %s'):format(a.id, a.title))
            MoneyLog.Add(a.seller, 'auction_sale', a.bid - fee, ('#%d %s (fee %s)'):format(a.id, a.title, Market.Money(fee)))
        end
        if SerialLog then
            local items = a.lot or { { item = a.item, metadata = a.metadata } }
            for _, it in ipairs(items) do
                local m = it.metadata or {}
                if m.serial then SerialLog.Add(m.serial, 'auction', ('Sold at auction #%d for %s%s'):format(a.id, Market.Money(a.bid), a.lot and (' (lot of %d)'):format(#items) or '')) end
            end
        end
        if a.lot then Market.RecordSale(a.item, {}, a.bid, a.title, 'lot') else Market.RecordSale(a.item, a.metadata, a.bid, a.title, a.kind) end
        local ok, locker = deliverAuction(a, a.bidder, a.bidder_locker, 'won')
        local where = locker and locker.label and (' It’s on its way to ' .. locker.label .. '.') or ''
        if AL.won then
            Market.NotifyId(a.bidder, bought and 'Bought it' or 'You won', ('%s for %s.%s'):format(a.title, Market.Money(a.bid), where))
        end
        if AL.sold then
            Market.NotifyId(a.seller, 'Sold', ('%s sold for %s. You get %s after fees.'):format(a.title, Market.Money(a.bid), Market.Money(a.bid - fee)))
        end
    else
        a.status = 'unsold'
        MySQL.update.await("UPDATE ascard_auctions SET status = 'unsold' WHERE id = ?", { a.id })
        if a.bidder and a.bid then
            Auctions.Credit(a.bidder, a.bid, 'Reserve not met: ' .. a.title)
            Market.NotifyId(a.bidder, 'Reserve not met', ('%s didn’t reach its reserve. Your %s has been returned.'):format(a.title, Market.Money(a.bid)))
        end
        deliverAuction(a, a.seller, a.seller_locker, 'returned')
        if AL.unsold then
            Market.NotifyId(a.seller, 'Not sold', ('%s didn’t sell. It’s being sent back to your locker.'):format(a.title))
        end
    end
end

--[[ ---------------------------------------------------------------------------
    OFFERS (on buy it now listings, before any bids)
--------------------------------------------------------------------------- ]]
local OF = AC.offers or {}

-- status: 'declined' | 'expired' | 'cancelled'. Refunds the buyer.
function Auctions.EndOffer(o, status, message)
    if not offers[o.id] then return end
    offers[o.id] = nil
    MySQL.update.await('UPDATE ascard_offers SET status = ? WHERE id = ?', { status, o.id })
    Auctions.Credit(o.buyer, o.amount, 'Offer returned')
    if message then Market.NotifyId(o.buyer, 'Offer ' .. status, message) end
end

function Auctions.ClearOffers(a, why, keepId)
    for _, o in ipairs(pendingOffers(a.id)) do
        if o.id ~= keepId then
            Auctions.EndOffer(o, 'cancelled', ('Your %s offer on %s was returned: %s.'):format(Market.Money(o.amount), a.title, why))
        end
    end
end

function Auctions.MakeOffer(src, identifier, id, amount)
    if not OF.enabled then return nil, 'Offers are turned off.' end
    if AdminFlags and AdminFlags.auctions then return nil, 'Offers are paused by staff right now.' end
    id = tonumber(id)
    local a = Auctions.live[id]
    if not a or a.ends_at <= os.time() then return nil, 'This auction has ended.' end
    if not a.buy_now or a.bids > 0 then return nil, 'This listing no longer takes offers.' end
    if a.seller == identifier then return nil, 'You can’t make an offer on your own listing.' end
    amount = math.floor(tonumber(amount) or 0)
    local min = math.max(a.start_price, math.ceil(a.buy_now * (OF.minPercent or 0.5)))
    if amount < min then return nil, ('The lowest offer the seller takes is %s.'):format(Market.Money(min)) end
    if amount >= a.buy_now then return nil, 'That’s the buy it now price or more. Just buy it now.' end
    local existing
    local count = 0
    for _, o in pairs(offers) do
        if o.auction_id == id then
            count = count + 1
            if o.buyer == identifier then existing = o end
        end
    end
    if not existing and count >= (OF.maxPending or 10) then return nil, 'This listing has too many offers waiting. Try later.' end
    if busy[id] then return nil, 'Try again in a moment.' end
    busy[id] = true
    local charge = existing and (amount - existing.amount) or amount
    if charge > 0 and not take(src, charge, 'ascard-auction-offer') then
        busy[id] = nil
        return nil, ('You need %s in your %s to make that offer.'):format(Market.Money(charge), account)
    end
    if charge < 0 then Framework.AddMoney(src, account, -charge, 'ascard-auction-offer') end
    local now = os.time()
    if existing then
        existing.amount, existing.created_at = amount, now
        MySQL.update.await('UPDATE ascard_offers SET amount = ?, created_at = ? WHERE id = ?', { amount, now, existing.id })
    else
        local o = { auction_id = id, buyer = identifier, buyer_name = Framework.GetName(src), buyer_locker = lockerFor(identifier), amount = amount, status = 'pending', created_at = now }
        o.id = MySQL.insert.await('INSERT INTO ascard_offers (auction_id, buyer, buyer_name, buyer_locker, amount, status, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
            { id, identifier, o.buyer_name, o.buyer_locker, amount, 'pending', now })
        if not o.id then busy[id] = nil Framework.AddMoney(src, account, amount, 'ascard-auction-offer') return nil, 'Try again.' end
        offers[o.id] = o
    end
    busy[id] = nil
    Market.NotifyId(a.seller, 'New offer', ('Someone offered %s for %s (buy it now %s). Answer it in the Card Market app.'):format(Market.Money(amount), a.title, Market.Money(a.buy_now)))
    return { offered = amount }
end

function Auctions.AnswerOffer(identifier, offerId, accept)
    local o = offers[tonumber(offerId)]
    if not o then return nil, 'That offer has gone.' end
    local a = Auctions.live[o.auction_id]
    if not a or a.seller ~= identifier then return nil, 'That offer has gone.' end
    if not accept then
        Auctions.EndOffer(o, 'declined', ('The seller declined your %s offer on %s. Your money has been returned.'):format(Market.Money(o.amount), a.title))
        return { declined = true }
    end
    if a.bids > 0 or a.ends_at <= os.time() then return nil, 'Too late: the listing has a bid or has ended.' end
    if busy[a.id] then return nil, 'Try again in a moment.' end
    busy[a.id] = true
    offers[o.id] = nil
    MySQL.update.await("UPDATE ascard_offers SET status = 'accepted' WHERE id = ?", { o.id })
    a.bid, a.bidder, a.bidder_name, a.bidder_locker = o.amount, o.buyer, o.buyer_name, o.buyer_locker or lockerFor(o.buyer)
    a.bids, a.reserve = 1, nil
    MySQL.insert('INSERT INTO ascard_bids (auction_id, bidder, bidder_name, amount, `at`) VALUES (?, ?, ?, ?, ?)', { a.id, o.buyer, o.buyer_name, o.amount, os.time() })
    Auctions.Settle(a, true, o.id)
    busy[a.id] = nil
    return { accepted = true, price = o.amount }
end

--[[ ---------------------------------------------------------------------------
    SELLER RATINGS
--------------------------------------------------------------------------- ]]
function Auctions.Rate(identifier, auctionId, score, comment)
    local RT = AC.ratings or {}
    if not RT.enabled then return nil, 'Ratings are turned off.' end
    auctionId = tonumber(auctionId)
    score = math.floor(tonumber(score) or 0)
    if score ~= 1 and score ~= 0 and score ~= -1 then return nil, 'Pick positive, neutral or negative.' end
    local r = MySQL.single.await("SELECT seller, bidder, bidder_name, status, ends_at FROM ascard_auctions WHERE id = ?", { auctionId })
    if not r or r.status ~= 'sold' or r.bidder ~= identifier then return nil, 'You can only rate sellers you bought from.' end
    if os.time() - (r.ends_at or 0) > (RT.days or 14) * 86400 then return nil, 'It’s too late to rate this sale.' end
    comment = tostring(comment or ''):gsub('[%c<>]', ''):sub(1, 120)
    local ok = MySQL.update.await('INSERT IGNORE INTO ascard_ratings (auction_id, seller, buyer, buyer_name, score, comment, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { auctionId, r.seller, identifier, r.bidder_name or '?', score, comment ~= '' and comment or nil, os.time() })
    if not ok or ok == 0 then return nil, 'You’ve already rated this sale.' end
    local st = sellerStats[r.seller] or { pos = 0, neu = 0, neg = 0 }
    sellerStats[r.seller] = st
    if score > 0 then st.pos = st.pos + 1 elseif score < 0 then st.neg = st.neg + 1 else st.neu = st.neu + 1 end
    Market.NotifyId(r.seller, 'New rating', ('A buyer left you a %s rating.'):format(score > 0 and 'positive' or score < 0 and 'negative' or 'neutral'))
    return { rated = score }
end

-- a seller's page: rating, recent feedback, what they're selling now (found through one of their auctions)
function Auctions.Seller(identifier, auctionId)
    local r = MySQL.single.await('SELECT seller, seller_name FROM ascard_auctions WHERE id = ?', { tonumber(auctionId) })
    if not r then return nil, 'Seller not found.' end
    local st = sellerStats[r.seller] or { pos = 0, neu = 0, neg = 0 }
    local out = { name = r.seller_name, rating = ratingOf(r.seller), pos = st.pos, neu = st.neu, neg = st.neg, feedback = {}, live = {}, now = os.time() }
    for _, f in ipairs(MySQL.query.await([[
        SELECT r.score, r.comment, r.created_at, r.buyer_name, a.title, a.final_price FROM ascard_ratings r
        LEFT JOIN ascard_auctions a ON a.id = r.auction_id WHERE r.seller = ? ORDER BY r.created_at DESC LIMIT 15
    ]], { r.seller }) or {}) do
        out.feedback[#out.feedback + 1] = { score = f.score, comment = f.comment, at = f.created_at, buyer = initials(f.buyer_name), title = f.title, price = f.final_price }
    end
    for _, a in pairs(Auctions.live) do if a.seller == r.seller then out.live[#out.live + 1] = Auctions.View(a, identifier) end end
    table.sort(out.live, function(x, y) return x.endsAt < y.endsAt end)
    local sold = MySQL.single.await("SELECT COUNT(*) AS n, COALESCE(SUM(final_price), 0) AS total FROM ascard_auctions WHERE seller = ? AND status = 'sold'", { r.seller })
    out.sold = sold and sold.n or 0
    return out
end

CreateThread(function()
    while not (Auctions.ready and Market.ready) do Wait(500) end
    local lastSlow = 0
    while true do
        local now = os.time()
        for _, a in pairs(Auctions.live) do
            if a.ends_at <= now and not busy[a.id] then
                local ok, err = pcall(Auctions.Settle, a)
                if not ok then print(('^1[as-tradingcards] settling auction %d failed: %s^0'):format(a.id, tostring(err))) end
            elseif AL.endingSoon and a.reminded == 0 and a.ends_at - now <= AL.endingSoon then
                a.reminded = 1
                MySQL.update('UPDATE ascard_auctions SET reminded = 1 WHERE id = ?', { a.id })
                local told = {}
                for _, r in ipairs(MySQL.query.await('SELECT DISTINCT bidder FROM ascard_bids WHERE auction_id = ?', { a.id }) or {}) do told[r.bidder] = true end
                Market.EachOnline(function(s, id)
                    if id ~= a.seller and (told[id] or isWatching(id, a.id)) then
                        Market.Notify(s, 'Ending soon', ('%s ends in %d minutes. Current bid %s.'):format(a.title, math.max(1, math.floor((a.ends_at - now) / 60)),
                            Market.Money(a.bid or a.start_price)))
                    end
                end)
            end
        end
        -- every minute: money and parcels waiting for players who are online now, old offers
        if now - lastSlow >= ((AC.delivery or {}).retrySeconds or 60) then
            lastSlow = now
            local life = ((AC.offers or {}).expireHours or 24) * 3600
            for oid, o in pairs(offers) do
                if now - o.created_at >= life then Auctions.EndOffer(o, 'expired', 'The seller didn’t answer your offer in time. Your money has been returned.') end
            end
            Market.EachOnline(function(s, id) payWaiting(s, id) end)
            for _, d in ipairs(MySQL.query.await("SELECT * FROM ascard_deliveries WHERE status = 'pending' LIMIT 50") or {}) do
                if postal() or Market.SourceOf(d.identifier) then pcall(sendDelivery, d) end
            end
        end
        Wait((AC.sweepSeconds or 10) * 1000)
    end
end)
