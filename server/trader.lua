--[[ NPC TRADER (card swaps, no cash) and COLLECTOR DESK (cash for the day's wants).
     Covers when nobody is on duty at the player card shop. Rates and wants change daily. ]]
local TC = Config.Trader or {}
local CC = Config.Collector or {}
Trader = {}

local function online(s) return s and GetPlayerName(s) ~= nil end
local function name(s) return Framework.GetName(s) or '?' end
local function money(n) return Utils.Money(n) end

--[[ ---------------------------------------------------------------------------
    PLACE / ACTIVE
--------------------------------------------------------------------------- ]]
local function pedCoords()
    local c = (TC.ped or {}).coords
    if not c or (c.x == 0.0 and c.y == 0.0 and c.z == 0.0) then return nil end
    return vec3(c.x, c.y, c.z)
end

function Trader.NearTrader(src)
    local c = pedCoords()
    if not c then return false end
    local p = GetPlayerPed(src)
    return p ~= 0 and #(GetEntityCoords(p) - c) <= 5.0
end

function Trader.Active()
    if not TC.enabled or not pedCoords() then return false end
    if TC.coverWhenNoStaff ~= false and Cardshop and Cardshop.Staffed and Cardshop.Staffed() then return false end
    return true
end

CreateThread(function()
    while true do
        GlobalState.ascardTraderOn = Trader.Active()
        Wait(4000)
    end
end)

--[[ ---------------------------------------------------------------------------
    DAY / RATES  (same for everyone, changes at rollHour)
--------------------------------------------------------------------------- ]]
local function tz() return os.difftime(os.time(), os.time(os.date('!*t'))) end
function Trader.Day(now)
    now = now or os.time()
    return math.floor((now + tz() - (TC.rollHour or 6) * 3600) / 86400)
end
local function nextRoll(now)
    now = now or os.time()
    local d = Trader.Day(now)
    return (d + 1) * 86400 + (TC.rollHour or 6) * 3600 - tz()
end

local function rng(seed)
    local s = math.floor(seed) % 2147483647
    if s <= 0 then s = s + 2147483646 end
    local function nxt(n)
        s = (s * 16807) % 2147483647
        if n then return (s % n) + 1 end
        return s / 2147483647
    end
    nxt() nxt()
    return nxt
end

local function typeIds()
    local list = {}
    for _, t in ipairs(Config.Types) do list[#list + 1] = t.id end
    return list
end

function Trader.Rates(day)
    day = day or Trader.Day()
    local r = rng(day * 7919 + 13)
    local out = { quantity = {}, condition = {}, sidegrade = {} }
    local ids = typeIds()
    local Q = TC.quantity or {}
    for i, id in ipairs(ids) do
        local base = (Q.base or {})[id]
        local nextId = ids[i + 1]
        if base and nextId then
            local give = math.max(Q.minGive or 2, base + (r(3) - 2))
            out.quantity[#out.quantity + 1] = { from = id, to = nextId, give = give }
        end
    end
    local C = TC.condition or {}
    out.condition = { dupes = math.max(1, (C.dupes or 2) + (r(2 * (C.dupesRange or 1) + 1) - (C.dupesRange or 1) - 1)), steps = C.steps or 2 }
    local S = TC.sidegrade or {}
    local hot, pool = {}, {}
    for _, id in ipairs(ids) do pool[#pool + 1] = id end
    for _ = 1, math.min(S.hotTypes or 2, #pool) do
        local i = r(#pool)
        hot[table.remove(pool, i)] = true
    end
    for _, id in ipairs(ids) do
        out.sidegrade[#out.sidegrade + 1] = { type = id, give = hot[id] and 1 or (S.others or 2), hot = hot[id] or nil }
    end
    return out
end

--[[ ---------------------------------------------------------------------------
    CARDS
--------------------------------------------------------------------------- ]]
local function isPlain(m)
    return not (m.parallel or m.insert or m.error or m.foil or m.grade)
end

local function cardType(m) local c = Config.Cards[m.cardId] return c and c.type end

local function mine(src)
    local list = {}
    for _, item in ipairs(Inventory.GetItems(src, Utils.IsCardItem)) do
        local m = item.metadata
        if m.cardId and Config.Cards[m.cardId] then list[#list + 1] = item end
    end
    return list
end

local function findBySerial(items, serial)
    for _, it in ipairs(items) do if it.metadata.serial == serial then return it end end
end

local function lightCard(item)
    local m = item.metadata
    Condition.Ensure(m)
    local sc = type(m.cond) == 'table' and Condition.Scores(m.cond) or nil
    return {
        slot = item.slot, serial = m.serial, cardId = m.cardId, type = cardType(m), plain = isPlain(m),
        cond = sc and sc.overall or nil, display = Utils.BuildDisplay(m, item.name),
    }
end

local function poolFor(typeId, excluded)
    local list = {}
    for id, c in pairs(Config.Cards) do
        if c.type == typeId and not excluded[id] and not DB.IsSoldOut(id) and Seasonal.Active(c)
            and Series2.Visible(c.set) then
            list[#list + 1] = id
        end
    end
    return list
end

-- a card for the player: from what other players swapped in, else a fresh one
function Trader.Pick(src, typeId, excluded)
    excluded = excluded or {}
    local rows = MySQL.query.await('SELECT id, item, card_id, metadata FROM ascard_trader_stock WHERE type = ?', { typeId }) or {}
    local ok = {}
    for _, r in ipairs(rows) do if not excluded[r.card_id] then ok[#ok + 1] = r end end
    if #ok > 0 then
        local r = ok[math.random(#ok)]
        if (MySQL.update.await('DELETE FROM ascard_trader_stock WHERE id = ?', { r.id }) or 0) > 0 then
            return r.item, json.decode(r.metadata) or {}, true
        end
    end
    local pool = poolFor(typeId, excluded)
    if #pool == 0 then pool = poolFor(typeId, {}) end
    if #pool == 0 then return nil end
    local cardId = pool[math.random(#pool)]
    local meta = Cards.Mint(cardId, false, nil)
    if not meta then return nil end
    return Cards.ItemFor(cardId), meta, false
end

local function stock(item, meta)
    MySQL.insert('INSERT INTO ascard_trader_stock (item, card_id, type, metadata, added_at) VALUES (?, ?, ?, ?, ?)',
        { item, meta.cardId, cardType(meta) or 'player', json.encode(meta), os.time() })
end
local function trimStock()
    local n = MySQL.scalar.await('SELECT COUNT(*) FROM ascard_trader_stock') or 0
    if n > 400 then MySQL.update('DELETE FROM ascard_trader_stock ORDER BY id ASC LIMIT ?', { n - 350 }) end
end

--[[ ---------------------------------------------------------------------------
    DAILY LIMIT
--------------------------------------------------------------------------- ]]
local function used(identifier)
    return MySQL.scalar.await('SELECT n FROM ascard_trader_swaps WHERE identifier = ? AND day = ?', { identifier, Trader.Day() }) or 0
end
local function addUse(identifier)
    MySQL.query.await('INSERT INTO ascard_trader_swaps (identifier, day, n) VALUES (?, ?, 1) ON DUPLICATE KEY UPDATE n = n + 1', { identifier, Trader.Day() })
end

--[[ ---------------------------------------------------------------------------
    WANTS (collector desk)
--------------------------------------------------------------------------- ]]
local function clubsWithCards()
    local count = {}
    for _, c in pairs(Config.Cards) do
        if Series2.Visible(c.set) then count[c.club] = (count[c.club] or 0) + 1 end
    end
    local list = {}
    for k, n in pairs(count) do if n >= (CC.brandCards or 3) then list[#list + 1] = k end end
    table.sort(list)
    return list
end

function Trader.Brand(day)
    day = day or Trader.Day()
    local clubs = clubsWithCards()
    if #clubs == 0 then return nil end
    local week = math.floor((day + 4 - (CC.brandWeekDay or 1)) / 7)
    local r = rng(week * 104729 + 7)
    local club = clubs[r(#clubs)]
    local def = Config.Clubs[club] or {}
    return { club = club, label = def.label or club, bonus = CC.brandBonus or 0.2 }
end

local function liveCards()
    local list = {}
    for id, c in pairs(Config.Cards) do
        if Series2.Visible(c.set) and Seasonal.Active(c) then list[#list + 1] = id end
    end
    table.sort(list)
    return list
end

function Trader.Wants(day)
    day = day or Trader.Day()
    local cards, clubs = liveCards(), clubsWithCards()
    if #cards == 0 then return {} end
    local r = rng(day * 15485863 + 3)
    local out = {}
    local kinds = { 'card', 'slab', 'brand' }
    for i = 1, (CC.wantsPerDay or 3) do
        local kind = kinds[((i - 1) % #kinds) + 1]
        if kind == 'brand' and #clubs == 0 then kind = 'card' end
        local w = { id = 'w' .. i, kind = kind }
        if kind == 'brand' then
            local club = clubs[r(#clubs)]
            w.club, w.clubLabel, w.count = club, (Config.Clubs[club] or {}).label or club, CC.brandCards or 3
        else
            local id = cards[r(#cards)]
            w.cardId, w.label = id, Utils.FullName(Config.Cards[id])
            if kind == 'slab' then
                local g = CC.slabMinGrade or { 8, 9, 10 }
                w.minGrade = g[r(#g)]
            end
        end
        out[#out + 1] = w
    end
    return out
end

local function done(identifier, day)
    local set = {}
    for _, r in ipairs(MySQL.query.await('SELECT want FROM ascard_wants_done WHERE identifier = ? AND day = ?', { identifier, day }) or {}) do set[r.want] = true end
    return set
end

local function wantPay(kind, value, club, brand)
    local mult = (CC.pay or {})[kind] or 1.0
    if brand and club == brand.club then mult = mult * (1 + (brand.bonus or 0)) end
    return math.floor(value * mult + 0.5)
end

--[[ ---------------------------------------------------------------------------
    INFO
--------------------------------------------------------------------------- ]]
lib.callback.register('as-tradingcards:server:traderInfo', function(src)
    if not Trader.Active() then return nil, 'The trader isn’t here right now.' end
    if not Trader.NearTrader(src) then return nil, 'Get closer to the trader.' end
    local identifier = Framework.GetIdentifier(src)
    if not identifier then return nil end
    local day = Trader.Day()
    local cards = {}
    for _, it in ipairs(mine(src)) do cards[#cards + 1] = lightCard(it) end
    local slabs = {}
    for _, it in ipairs(Inventory.GetItems(src, function(n) return n == Config.Items.slab end)) do
        local m = it.metadata
        if m.cardId and Config.Cards[m.cardId] then slabs[#slabs + 1] = { slot = it.slot, serial = m.serial, cardId = m.cardId, grade = m.grade, display = Utils.BuildDisplay(m, it.name) } end
    end
    local brand = Trader.Brand(day)
    local doneSet = done(identifier, day)
    local wants = {}
    for _, w in ipairs(Trader.Wants(day)) do
        local row = { id = w.id, kind = w.kind, cardId = w.cardId, label = w.label, minGrade = w.minGrade, club = w.club, clubLabel = w.clubLabel, count = w.count, done = doneSet[w.id] or nil }
        local eligible = {}
        if w.kind == 'card' then
            for _, c in ipairs(cards) do
                if c.cardId == w.cardId then eligible[#eligible + 1] = c.serial end
            end
            if Config.Cards[w.cardId] then row.display = Utils.BuildDisplay({ cardId = w.cardId }, Cards.ItemFor(w.cardId)) end
        elseif w.kind == 'slab' then
            for _, s in ipairs(slabs) do if s.cardId == w.cardId and (s.grade or 0) >= w.minGrade then eligible[#eligible + 1] = s.serial end end
            if Config.Cards[w.cardId] then row.display = Utils.BuildDisplay({ cardId = w.cardId }, Cards.ItemFor(w.cardId)) end
        else
            for _, c in ipairs(cards) do if Config.Cards[c.cardId].club == w.club then eligible[#eligible + 1] = c.serial end end
        end
        row.eligible = eligible
        row.have = #eligible
        if w.cardId then row.value = Utils.CardValue({ cardId = w.cardId }, Cards.ItemFor(w.cardId)) end
        row.payNote = ('x%.2f market value%s'):format(((CC.pay or {})[w.kind]) or 1, (brand and (w.club == brand.club or (w.cardId and Config.Cards[w.cardId].club == brand.club))) and (' + ' .. math.floor((brand.bonus or 0) * 100) .. '% brand week') or '')
        wants[#wants + 1] = row
    end
    return {
        rates = Trader.Rates(day), used = used(identifier), limit = TC.swapsPerDay or 10, cards = cards, slabs = slabs,
        wants = wants, brand = brand, resetIn = math.max(0, nextRoll() - os.time()), types = (function()
            local t = {}
            for _, x in ipairs(Config.Types) do t[x.id] = x.label end
            return t
        end)(),
        wantsOn = CC.enabled ~= false, plainOnly = TC.plainOnly ~= false,
    }
end)

--[[ ---------------------------------------------------------------------------
    SWAPS
--------------------------------------------------------------------------- ]]
local function distinctSerials(list, n)
    if type(list) ~= 'table' or #list ~= n then return nil end
    local seen = {}
    for _, s in ipairs(list) do if type(s) ~= 'string' or seen[s] then return nil end seen[s] = true end
    return list
end

local function giveBack(src, item, meta)
    return Inventory.AddItem(src, item, 1, meta)
end

lib.callback.register('as-tradingcards:server:traderSwap', function(src, kind, d)
    if not Trader.Active() or not Trader.NearTrader(src) then return nil, 'The trader isn’t here right now.' end
    local identifier = Framework.GetIdentifier(src)
    if not identifier then return nil end
    d = type(d) == 'table' and d or {}
    if used(identifier) >= (TC.swapsPerDay or 10) then return nil, ('You’ve done %d swaps today. Come back tomorrow.'):format(TC.swapsPerDay or 10) end
    local rates = Trader.Rates()
    local items = mine(src)
    local plainOnly = TC.plainOnly ~= false

    local function takeAll(serials)
        local taken = {}
        for _, s in ipairs(serials) do
            local it = findBySerial(items, s)
            if not it then return nil, 'One of those cards has moved.' end
            if DB.IsStolen(s) then return nil, 'The trader won’t touch a stolen card.' end
            taken[#taken + 1] = it
        end
        return taken
    end
    local function removeAll(taken)
        local gone = {}
        for _, it in ipairs(taken) do
            DB.Seen(src, it.metadata)
            if Inventory.RemoveItem(src, it.name, 1, it.slot, Inventory.name == 'ox' and it.metadata or nil) then gone[#gone + 1] = it
            else
                for _, g in ipairs(gone) do Inventory.AddItem(src, g.name, 1, g.metadata) end
                return false
            end
        end
        return true
    end

    if kind == 'quantity' then
        local rate
        for _, q in ipairs(rates.quantity) do if q.from == d.from then rate = q end end
        if not rate then return nil, 'The trader doesn’t swap those.' end
        local serials = distinctSerials(d.serials, rate.give)
        if not serials then return nil, ('Hand over exactly %d cards.'):format(rate.give) end
        local taken, err = takeAll(serials)
        if not taken then return nil, err end
        for _, it in ipairs(taken) do
            if cardType(it.metadata) ~= rate.from then return nil, 'Those aren’t all the same type.' end
            if plainOnly and not isPlain(it.metadata) then return nil, 'The trader only takes plain cards (no foils, parallels, chase cards or errors).' end
        end
        local excluded = {}
        for _, it in ipairs(taken) do excluded[it.metadata.cardId] = true end
        local item, meta, fromStock = Trader.Pick(src, rate.to, excluded)
        if not item then return nil, 'The trader has nothing to offer for that right now.' end
        if not Inventory.CanCarry(src, item, 1) then if fromStock then stock(item, meta) end return nil, 'No room in your pockets.' end
        if not removeAll(taken) then if fromStock then stock(item, meta) end return nil, 'Those cards have moved.' end
        for _, it in ipairs(taken) do stock(it.name, it.metadata) end
        trimStock()
        Inventory.AddItem(src, item, 1, meta)
        DB.SetOwner(meta.serial, identifier, meta.cardId) DB.LogPull(identifier, meta.cardId, false)
        if SerialLog then SerialLog.Add(meta.serial, 'trader', 'Swapped with the card trader') end
        addUse(identifier)
        Framework.Notify(src, ('Swapped %d cards for %s.'):format(rate.give, Utils.CardTitle(meta, item)), 'success')
        return { title = Utils.CardTitle(meta, item), left = (TC.swapsPerDay or 10) - used(identifier) }
    end

    if kind == 'sidegrade' then
        local rate
        for _, q in ipairs(rates.sidegrade) do if q.type == d.type then rate = q end end
        if not rate then return nil, 'The trader doesn’t swap those.' end
        local serials = distinctSerials(d.serials, rate.give)
        if not serials then return nil, ('Hand over exactly %d card%s.'):format(rate.give, rate.give == 1 and '' or 's') end
        local taken, err = takeAll(serials)
        if not taken then return nil, err end
        for _, it in ipairs(taken) do
            if cardType(it.metadata) ~= rate.type then return nil, 'Those aren’t all that type.' end
            if plainOnly and not isPlain(it.metadata) then return nil, 'The trader only takes plain cards (no foils, parallels, chase cards or errors).' end
        end
        local excluded = {}
        for _, it in ipairs(taken) do excluded[it.metadata.cardId] = true end
        local item, meta, fromStock = Trader.Pick(src, rate.type, excluded)
        if not item then return nil, 'The trader has nothing different to offer.' end
        if not Inventory.CanCarry(src, item, 1) then if fromStock then stock(item, meta) end return nil, 'No room in your pockets.' end
        if not removeAll(taken) then if fromStock then stock(item, meta) end return nil, 'Those cards have moved.' end
        for _, it in ipairs(taken) do stock(it.name, it.metadata) end
        trimStock()
        Inventory.AddItem(src, item, 1, meta)
        DB.SetOwner(meta.serial, identifier, meta.cardId) DB.LogPull(identifier, meta.cardId, false)
        if SerialLog then SerialLog.Add(meta.serial, 'trader', 'Swapped with the card trader') end
        addUse(identifier)
        Framework.Notify(src, ('Swapped for %s.'):format(Utils.CardTitle(meta, item)), 'success')
        return { title = Utils.CardTitle(meta, item), left = (TC.swapsPerDay or 10) - used(identifier) }
    end

    if kind == 'condition' then
        local need = rates.condition.dupes
        local target = findBySerial(items, tostring(d.serial or ''))
        if not target then return nil, 'Pick the card to restore.' end
        if DB.IsStolen(target.metadata.serial) then return nil, 'The trader won’t touch a stolen card.' end
        local serials = distinctSerials(d.serials, need)
        if not serials then return nil, ('Hand over exactly %d copies of the same card.'):format(need) end
        for _, s in ipairs(serials) do if s == target.metadata.serial then return nil, 'The copies must be other cards.' end end
        local taken, err = takeAll(serials)
        if not taken then return nil, err end
        for _, it in ipairs(taken) do
            if it.metadata.cardId ~= target.metadata.cardId then return nil, 'The copies must be the same card.' end
            if plainOnly and not isPlain(it.metadata) then return nil, 'The copies must be plain (no foils, parallels, chase cards or errors).' end
        end
        Condition.Ensure(target.metadata)
        local meta = target.metadata
        local before = Condition.Scores(meta.cond).overall
        if before >= 10 then return nil, 'That card is already in perfect condition.' end
        if not removeAll(taken) then return nil, 'Those cards have moved.' end
        for _, it in ipairs(taken) do stock(it.name, it.metadata) end
        trimStock()
        local c = {}
        for k, v in pairs(meta.cond) do c[k] = v end
        local steps = rates.condition.steps or 2
        for _, k in ipairs({ 'cen', 'cor', 'edg', 'sur' }) do c[k] = math.min(10, (c[k] or 9) + steps) end
        for _, k in ipairs({ 'dust', 'finger', 'dirt', 'stain', 'whiten', 'fade' }) do c[k] = 0 end
        meta.cond = c
        meta.description = Utils.CardDescription(meta, target.name)
        -- the slot may have shifted after taking the copies: find it again by serial
        local again = findBySerial(mine(src), meta.serial)
        if not again then return nil, 'That card has moved.' end
        Inventory.SetMetadata(src, again.slot, meta)
        local after = Condition.Scores(c).overall
        if SerialLog then SerialLog.Add(meta.serial, 'restored', ('Restored by the card trader (%d to %d)'):format(before, after)) end
        addUse(identifier)
        Framework.Notify(src, ('%s restored: condition %d to %d.'):format(Utils.CardTitle(meta, target.name), before, after), 'success')
        return { title = Utils.CardTitle(meta, target.name), before = before, after = after, left = (TC.swapsPerDay or 10) - used(identifier) }
    end
    return nil, 'Unknown swap.'
end)

--[[ ---------------------------------------------------------------------------
    HAND IN A WANT
--------------------------------------------------------------------------- ]]
lib.callback.register('as-tradingcards:server:wantHand', function(src, wantId, serials)
    if CC.enabled == false or not Trader.Active() or not Trader.NearTrader(src) then return nil, 'The collector isn’t here right now.' end
    local identifier = Framework.GetIdentifier(src)
    if not identifier then return nil end
    local day = Trader.Day()
    local want
    for _, w in ipairs(Trader.Wants(day)) do if w.id == wantId then want = w end end
    if not want then return nil, 'That want has changed.' end
    if done(identifier, day)[want.id] then return nil, 'You already did that one today.' end
    if type(serials) ~= 'table' then return nil, 'Pick the card.' end
    local brand = Trader.Brand(day)
    local pool = want.kind == 'slab' and Inventory.GetItems(src, function(n) return n == Config.Items.slab end) or mine(src)
    local need = want.kind == 'brand' and want.count or 1
    if #serials ~= need then return nil, ('Hand over %d card%s.'):format(need, need == 1 and '' or 's') end
    local taken, seen, total = {}, {}, 0
    for _, s in ipairs(serials) do
        if type(s) ~= 'string' or seen[s] then return nil, 'Bad selection.' end
        seen[s] = true
        local it = findBySerial(pool, s)
        if not it or DB.IsStolen(s) then return nil, 'One of those cards has moved.' end
        local m = it.metadata
        if want.kind == 'card' and m.cardId ~= want.cardId then return nil, 'That’s not the card they want.' end
        if want.kind == 'slab' and (m.cardId ~= want.cardId or (m.grade or 0) < want.minGrade) then return nil, 'That slab doesn’t meet the grade.' end
        if want.kind == 'brand' and (Config.Cards[m.cardId] or {}).club ~= want.club then return nil, 'Those aren’t all from that club.' end
        taken[#taken + 1] = it
        local cclub = (Config.Cards[m.cardId] or {}).club
        total = total + wantPay(want.kind, Utils.CardValue(m, it.name), cclub, brand)
    end
    for i, it in ipairs(taken) do
        DB.Seen(src, it.metadata)
        if not Inventory.RemoveItem(src, it.name, 1, it.slot, Inventory.name == 'ox' and it.metadata or nil) then
            for j = 1, i - 1 do Inventory.AddItem(src, taken[j].name, 1, taken[j].metadata) end
            return nil, 'Those cards have moved.'
        end
    end
    MySQL.insert.await('INSERT IGNORE INTO ascard_wants_done (identifier, day, want) VALUES (?, ?, ?)', { identifier, day, want.id })
    for _, it in ipairs(taken) do
        if it.name ~= Config.Items.slab then stock(it.name, it.metadata) end
        if SerialLog then SerialLog.Add(it.metadata.serial, 'wants', 'Handed to the collector') end
    end
    Framework.AddMoney(src, 'cash', total, 'ascard-collector')
    if MoneyLog then MoneyLog.Add(src, 'wants', total, ('Collector want: %s'):format(want.kind)) end
    Framework.Notify(src, ('The collector pays you %s.'):format(money(total)), 'success')
    return { pay = total }
end)
