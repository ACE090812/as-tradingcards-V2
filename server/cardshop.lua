--[[ PLAYER CARD SHOP (job `Config.CardShop.job`).
     Customers buy / sell at the counter, staff set prices, owner and managers handle the till and wholesale.
     While anyone is on duty the NPC shop and trader step back. Everything is stored against the job (not the person). ]]
local CS = Config.CardShop or {}
Cardshop = { staffSrc = {} }
if not CS.enabled then
    function Cardshop.Staffed() return false end
    return
end

local function online(s) return s and GetPlayerName(s) ~= nil end
local function name(s) return Framework.GetName(s) or GetPlayerName(s) or '?' end
local function money(n) return Utils.Money(n) end
local function round(n) return math.floor(n + 0.5) end

--[[ ---------------------------------------------------------------------------
    ROLES / DUTY
--------------------------------------------------------------------------- ]]
local function jobOf(src)
    local j = Framework.GetJob(src)
    if not j or j.name ~= CS.job then return nil end
    return j
end

-- 'owner' | 'manager' | 'staff' | nil (works on or off duty)
function Cardshop.Rank(src)
    local j = jobOf(src)
    if not j then return nil end
    local g = CS.grades or {}
    if j.grade >= (g.owner or 4) then return 'owner' end
    if j.grade >= (g.manager or 2) then return 'manager' end
    return 'staff'
end
local ORDER = { staff = 1, manager = 2, owner = 3 }
local function atLeast(src, need)
    local r = Cardshop.Rank(src)
    return r and ORDER[r] >= ORDER[need] or false
end

local function onDuty(src)
    local j = jobOf(src)
    return j and j.onduty == true or false
end

local staffed = false
local function scan()
    local list, any = {}, false
    for _, s in ipairs(GetPlayers()) do
        s = tonumber(s)
        if onDuty(s) then list[#list + 1] = s any = true end
    end
    Cardshop.staffSrc = list
    staffed = any
    GlobalState.ascardStaffed = any
end
function Cardshop.Staffed() return staffed end
CreateThread(function() while true do pcall(scan) Wait(4000) end end)

local function counterCoords()
    local c = (CS.counter or {}).coords
    if c and not (c.x == 0.0 and c.y == 0.0 and c.z == 0.0) then return vec3(c.x, c.y, c.z) end
    local ped = Config.Peds and Config.Peds[1]
    return ped and vec3(ped.coords.x, ped.coords.y, ped.coords.z) or nil
end
local function deskCoords()
    local c = (CS.managerDesk or {}).coords
    if c and not (c.x == 0.0 and c.y == 0.0 and c.z == 0.0) then return vec3(c.x, c.y, c.z) end
    return counterCoords()
end
local function near(src, c, extra)
    if not c then return false end
    local p = GetPlayerPed(src)
    return p ~= 0 and #(GetEntityCoords(p) - c) <= ((CS.counter or {}).radius or 1.6) + (extra or 2.5)
end
function Cardshop.NearCounter(src) return near(src, counterCoords()) end
local function nearDesk(src) return near(src, deskCoords()) or near(src, counterCoords()) end

--[[ ---------------------------------------------------------------------------
    LEDGER
--------------------------------------------------------------------------- ]]
local function ledger(src, kind, amount, detail)
    local id = src and Framework.GetIdentifier(src) or nil
    MySQL.insert('INSERT INTO ascard_shop_ledger (`at`, identifier, name, kind, amount, detail) VALUES (?, ?, ?, ?, ?, ?)',
        { os.time(), id, src and name(src) or nil, kind, math.floor(amount), tostring(detail or ''):sub(1, 200) })
end

local function staffRow(src)
    local id = Framework.GetIdentifier(src)
    MySQL.query.await('INSERT INTO ascard_shop_staff (identifier, name, last_on) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE name = VALUES(name), last_on = VALUES(last_on)', { id, name(src), os.time() })
    return id
end

function Cardshop.Revenue(amount, detail, src)
    if not staffed or amount <= 0 then return end
    Society.Add(amount, detail)
    ledger(src, 'sale', amount, detail)
end

--[[ ---------------------------------------------------------------------------
    PRICES
--------------------------------------------------------------------------- ]]
local function catalogue()
    local map = {}
    for _, e in ipairs(Series2.ShopItems()) do map[e.item] = e end
    return map
end
local function shopEntry(item) return catalogue()[item] end

local function itemLabel(item)
    local e = shopEntry(item)
    if e then return e.label end
    local pk = Config.Packs[item] or (Config.Boxes or {})[item]
    return pk and pk.label or item
end

-- market value of a stock row
local function marketOf(row)
    if row.kind == 'card' then
        local m = row.meta or json.decode(row.metadata or '{}') or {}
        return Utils.CardValue(m, row.item)
    end
    local e = shopEntry(row.item)
    if Utils.Sealed[row.item] then return Utils.SealedValue(row.item) end
    return e and e.price or 1
end

local function limits(market)
    return math.max(1, math.ceil(market * (CS.sellMin or 0.7))), math.max(1, math.floor(market * (CS.sellMax or 1.4)))
end

local function buyPct()
    local v = tonumber(V2.GetSetting('shop_buypct', tostring(CS.buyDefault or 0.6))) or 0.6
    return math.max(CS.buyMin or 0.5, math.min(CS.buyMax or 0.9, v))
end
local function buying() return V2.GetSetting('shop_buying', '1') == '1' end

--[[ ---------------------------------------------------------------------------
    STOCK
--------------------------------------------------------------------------- ]]
local function stockRows()
    local out = {}
    for _, r in ipairs(MySQL.query.await('SELECT id, kind, item, qty, metadata, price, cost FROM ascard_shop_stock ORDER BY kind, item, id') or {}) do
        r.meta = r.metadata and json.decode(r.metadata) or nil
        out[#out + 1] = r
    end
    return out
end

local function stockItemAdd(item, qty, price, cost)
    local row = MySQL.single.await("SELECT id FROM ascard_shop_stock WHERE kind = 'item' AND item = ?", { item })
    if row then
        MySQL.update.await('UPDATE ascard_shop_stock SET qty = qty + ?, cost = ? WHERE id = ?', { qty, cost or 0, row.id })
    else
        MySQL.insert.await("INSERT INTO ascard_shop_stock (kind, item, qty, price, cost, added_at) VALUES ('item', ?, ?, ?, ?, ?)", { item, qty, price, cost or 0, os.time() })
    end
end

local function rowView(r)
    local market = marketOf(r)
    local lo, hi = limits(market)
    local v = {
        id = r.id, kind = r.kind, item = r.item, qty = r.qty, price = r.price, market = market, min = lo, max = hi,
        label = r.kind == 'card' and Utils.CardTitle(r.meta or {}, r.item) or itemLabel(r.item),
    }
    if r.kind == 'card' then v.display = Utils.BuildDisplay(r.meta or {}, r.item) end
    return v
end

--[[ ---------------------------------------------------------------------------
    SERVING (who gets the commission)
--------------------------------------------------------------------------- ]]
local function servedBy(customer)
    local best, bd = nil, 1e9
    local p = GetPlayerPed(customer)
    local c = p ~= 0 and GetEntityCoords(p) or nil
    for _, s in ipairs(Cardshop.staffSrc) do
        if s ~= customer then
            local sp = GetPlayerPed(s)
            local d = (c and sp ~= 0) and #(GetEntityCoords(sp) - c) or 1e8
            if d < bd then best, bd = s, d end
        end
    end
    return best
end

local function payCommission(staff, saleValue, what)
    local pct = (CS.pay or {}).commission or 0
    if not staff or pct <= 0 then return 0 end
    local amount = math.floor(saleValue * pct)
    if amount <= 0 then return 0 end
    if not Society.Remove(amount, 'commission') then return 0 end
    Framework.AddMoney(staff, (CS.pay or {}).account or 'bank', amount, 'ascard-shop-commission')
    local id = staffRow(staff)
    MySQL.update('UPDATE ascard_shop_staff SET sales = sales + 1, sold_value = sold_value + ?, earned = earned + ? WHERE identifier = ?', { saleValue, amount, id })
    ledger(staff, 'commission', -amount, ('Commission: %s'):format(what or 'sale'))
    Framework.Notify(staff, ('Commission %s'):format(money(amount)), 'success')
    return amount
end

--[[ ---------------------------------------------------------------------------
    CUSTOMER
--------------------------------------------------------------------------- ]]
local function sellables(src)
    local pct, out = buyPct(), {}
    for _, item in ipairs(Inventory.GetItems(src, Utils.IsCollectible)) do
        local m = item.metadata
        if m.cardId and not DB.IsStolen(m.serial) then
            local value = Utils.CardValue(m, item.name)
            out[#out + 1] = { slot = item.slot, serial = m.serial, title = Utils.CardTitle(m, item.name), market = value, offer = math.floor(value * pct), display = Utils.BuildDisplay(m, item.name) }
        end
    end
    for _, item in ipairs(Inventory.GetItems(src, function(n) return Utils.Sealed[n] end)) do
        if not (type(item.metadata) == 'table' and item.metadata.resealed) then
            local value = Utils.SealedValue(item.name)
            out[#out + 1] = { slot = item.slot, sealed = true, title = itemLabel(item.name), market = value, offer = math.floor(value * pct) }
        end
    end
    return out
end

lib.callback.register('as-tradingcards:server:shopRole', function(src)
    return { rank = Cardshop.Rank(src), onduty = onDuty(src), staffed = staffed }
end)

lib.callback.register('as-tradingcards:server:shopCustomer', function(src)
    if not Cardshop.NearCounter(src) then return nil, 'Get closer to the counter.' end
    if not staffed then return nil, 'Nobody is on duty right now.' end
    if AdminFlags and AdminFlags.shop then return nil, 'The card shop is closed by staff right now.' end
    local rows, items = stockRows(), {}
    for _, r in ipairs(rows) do if r.qty > 0 then items[#items + 1] = rowView(r) end end
    local server = servedBy(src)
    return {
        items = items, servedBy = server and name(server) or nil, buying = buying(), pct = buyPct(), sell = buying() and sellables(src) or {},
        grading = (CS.grading or {}).enabled ~= false, shop = Config.Shop.label or 'Card shop',
    }
end)

lib.callback.register('as-tradingcards:server:shopBuy', function(src, id, amount)
    if not Cardshop.NearCounter(src) or not staffed then return nil, 'The shop isn’t serving right now.' end
    if AdminFlags and AdminFlags.shop then return nil, 'The card shop is closed by staff right now.' end
    amount = math.floor(tonumber(amount) or 1)
    id = tonumber(id)
    local r = id and MySQL.single.await('SELECT id, kind, item, qty, metadata, price FROM ascard_shop_stock WHERE id = ?', { id })
    if not r or r.qty < 1 then return nil, 'That’s sold out.' end
    r.meta = r.metadata and json.decode(r.metadata) or nil
    if r.kind == 'card' then amount = 1 end
    amount = math.max(1, math.min(amount, Config.Shop.maxPerPurchase or 20, r.qty))
    local total = r.price * amount
    local unique = r.kind == 'item' and ((Config.Packs[r.item] and Config.Scale and Config.Scale.uniquePacks) or (Seals and Seals.IsBox(r.item) and (Config.Seals or {}).enabled))
    if not Inventory.CanCarry(src, r.item, amount) or (unique and Inventory.FreeSlots(src) < amount) then return nil, L('no_space', unique and amount or 1) end
    -- take the stock first (race-free), then the money
    if (MySQL.update.await('UPDATE ascard_shop_stock SET qty = qty - ? WHERE id = ? AND qty >= ?', { amount, r.id, amount }) or 0) == 0 then return nil, 'Someone just bought that.' end
    if not Framework.Charge(src, total, 'ascard-player-shop') then
        MySQL.update.await('UPDATE ascard_shop_stock SET qty = qty + ? WHERE id = ?', { amount, r.id })
        return nil, L('not_enough_money')
    end
    if r.kind == 'card' then
        if not Inventory.AddItem(src, r.item, 1, r.meta or {}) then
            MySQL.update.await('UPDATE ascard_shop_stock SET qty = qty + 1 WHERE id = ?', { r.id })
            Framework.AddMoney(src, 'cash', total, 'ascard-player-shop-refund')
            return nil, L('no_space', 1)
        end
        if r.meta and r.meta.serial then
            DB.SetOwner(r.meta.serial, Framework.GetIdentifier(src), r.meta.cardId)
            if SerialLog then SerialLog.Add(r.meta.serial, 'shop', ('Bought from the player card shop for %s'):format(money(total))) end
        end
    else
        if not Cards.GivePacks(src, r.item, amount) then
            MySQL.update.await('UPDATE ascard_shop_stock SET qty = qty + ? WHERE id = ?', { amount, r.id })
            Framework.AddMoney(src, 'cash', total, 'ascard-player-shop-refund')
            return nil, L('no_space', 1)
        end
    end
    MySQL.update('DELETE FROM ascard_shop_stock WHERE qty <= 0 AND kind = ?', { 'card' })
    Society.Add(total, 'sale')
    local label = r.kind == 'card' and Utils.CardTitle(r.meta or {}, r.item) or itemLabel(r.item)
    ledger(src, 'sale', total, ('%dx %s'):format(amount, label))
    payCommission(servedBy(src), total, label)
    if Stats then Stats.Add(Framework.GetIdentifier(src), 'spent', total) end
    if MoneyLog then MoneyLog.Add(src, 'cardshop', -total, ('%dx %s'):format(amount, label)) end
    Framework.Notify(src, L('bought', amount, label, money(total)), 'success')
    return true
end)

lib.callback.register('as-tradingcards:server:shopSell', function(src, slot, serial)
    if not Cardshop.NearCounter(src) or not staffed then return nil, 'The shop isn’t serving right now.' end
    if not buying() then return nil, 'The shop isn’t buying right now.' end
    if AdminFlags and AdminFlags.sellBack then return nil, 'The shop isn’t buying cards right now.' end
    local item = Inventory.GetSlot(src, tonumber(slot))
    if not item then return nil, L('item_missing') end
    local isSealed = Utils.Sealed[item.name]
    if not isSealed and not Utils.IsCollectible(item.name) then return nil, 'They don’t buy that.' end
    local meta = type(item.metadata) == 'table' and item.metadata or {}
    if not isSealed and (meta.serial ~= serial) then return nil, L('item_missing') end
    if isSealed and meta.resealed then return nil, 'They check the seal number: that box isn’t factory sealed.' end
    if not isSealed and DB.IsStolen(meta.serial) then return nil, L('buyer_stolen') end
    local market = isSealed and Utils.SealedValue(item.name) or Utils.CardValue(meta, item.name)
    local price = math.floor(market * buyPct())
    if price < 1 then return nil, 'Not worth anything.' end
    if Society.Balance() < price then return nil, 'The shop can’t afford that right now.' end
    if not isSealed then DB.Seen(src, meta) end
    if not Inventory.RemoveItem(src, item.name, 1, item.slot, (Inventory.name == 'ox' and not isSealed) and meta or nil) then return nil, L('item_missing') end
    if not Society.Remove(price, 'buy from player') then
        Inventory.AddItem(src, item.name, 1, meta)
        return nil, 'The shop can’t afford that right now.'
    end
    Framework.AddMoney(src, Config.Money.sellPaysTo, price, 'ascard-player-shop-sell')
    local title
    if isSealed then
        stockItemAdd(item.name, 1, market, price)
        title = itemLabel(item.name)
        if Seals and meta.seal then Seals.Opened(meta, 'shop') end
    else
        local card = Config.Cards[meta.cardId] or {}
        MySQL.insert.await("INSERT INTO ascard_shop_stock (kind, item, qty, metadata, price, cost, added_at) VALUES ('card', ?, 1, ?, ?, ?, ?)", { item.name, json.encode(meta), market, price, os.time() })
        title = Utils.CardTitle(meta, item.name)
        if SerialLog then SerialLog.Add(meta.serial, 'shop', ('Sold to the player card shop for %s'):format(money(price))) end
    end
    ledger(src, 'buy', -price, ('Bought %s from %s'):format(title, name(src)))
    if Stats then Stats.Add(Framework.GetIdentifier(src), 'sold', price) end
    if MoneyLog then MoneyLog.Add(src, 'cardshop', price, ('Sold %s to the card shop'):format(title)) end
    Framework.Notify(src, L('sold', title, money(price)), 'success')
    return true
end)

--[[ ---------------------------------------------------------------------------
    MANAGER
--------------------------------------------------------------------------- ]]
local function manageInfo(src)
    local rank = Cardshop.Rank(src)
    local rows, items = stockRows(), {}
    for _, r in ipairs(rows) do items[#items + 1] = rowView(r) end
    local since = os.time() - 86400
    local sold = MySQL.single.await("SELECT COUNT(*) AS n, COALESCE(SUM(amount),0) AS v FROM ascard_shop_ledger WHERE kind = 'sale' AND `at` > ?", { since }) or { n = 0, v = 0 }
    local bought = MySQL.single.await("SELECT COUNT(*) AS n FROM ascard_shop_ledger WHERE kind = 'buy' AND `at` > ?", { since }) or { n = 0 }
    local staff = {}
    for _, s in ipairs(GetPlayers()) do
        s = tonumber(s)
        local j = jobOf(s)
        if j then staff[#staff + 1] = { id = s, name = name(s), grade = j.grade, rank = Cardshop.Rank(s), onduty = j.onduty } end
    end
    local stats = MySQL.query.await('SELECT name, minutes, sales, sold_value, earned FROM ascard_shop_staff ORDER BY sold_value DESC LIMIT 20') or {}
    local led = MySQL.query.await('SELECT `at`, name, kind, amount, detail FROM ascard_shop_ledger ORDER BY id DESC LIMIT 60') or {}
    local cat = {}
    local pct = (CS.wholesaleCatalogue or {}).pct or 0.7
    local allow = (CS.wholesaleCatalogue or {}).items or {}
    local allowSet = {}
    for _, i in ipairs(allow) do allowSet[i] = true end
    for _, e in ipairs(Series2.ShopItems()) do
        if #allow == 0 or allowSet[e.item] then cat[#cat + 1] = { item = e.item, label = e.label, cost = math.floor(e.price * pct), market = e.price } end
    end
    return {
        rank = rank, till = Society.Balance(), tillMode = Society.mode, items = items, sold = sold, bought = bought.n, staff = staff, stats = stats, ledger = led,
        buying = buying(), pct = buyPct(), buyMin = CS.buyMin, buyMax = CS.buyMax, sellMin = CS.sellMin, sellMax = CS.sellMax,
        canWithdraw = atLeast(src, CS.withdraw or 'manager'), canOrder = atLeast(src, CS.wholesale or 'owner'), canPrice = atLeast(src, 'manager'),
        catalogue = cat, maxPer = (CS.wholesaleCatalogue or {}).maxPerItem or 200, onDuty = staffed, npcOn = not staffed,
        pay = CS.pay, name = name(src),
    }
end

lib.callback.register('as-tradingcards:server:shopManage', function(src)
    if not Cardshop.Rank(src) then return nil, 'You don’t work here.' end
    if not nearDesk(src) then return nil, 'Use the shop desk.' end
    return manageInfo(src)
end)

lib.callback.register('as-tradingcards:server:shopSetPrice', function(src, id, price)
    if not atLeast(src, 'manager') or not nearDesk(src) then return nil, 'Managers and the owner set prices.' end
    id, price = tonumber(id), math.floor(tonumber(price) or 0)
    local r = id and MySQL.single.await('SELECT id, kind, item, metadata FROM ascard_shop_stock WHERE id = ?', { id })
    if not r then return nil, 'That row is gone.' end
    local lo, hi = limits(marketOf(r))
    if price < lo or price > hi then return nil, ('Prices must stay between %s and %s for this item.'):format(money(lo), money(hi)) end
    MySQL.update.await('UPDATE ascard_shop_stock SET price = ? WHERE id = ?', { price, id })
    return manageInfo(src)
end)

lib.callback.register('as-tradingcards:server:shopSetBuy', function(src, pct, on)
    if not atLeast(src, 'manager') or not nearDesk(src) then return nil, 'Managers and the owner set the buy list.' end
    pct = tonumber(pct) or buyPct()
    if pct < (CS.buyMin or 0.5) - 1e-6 or pct > (CS.buyMax or 0.9) + 1e-6 then return nil, ('The buy price must be %d%% to %d%% of market.'):format((CS.buyMin or 0.5) * 100, (CS.buyMax or 0.9) * 100) end
    V2.SetSetting('shop_buypct', pct)
    V2.SetSetting('shop_buying', on and '1' or '0')
    return manageInfo(src)
end)

lib.callback.register('as-tradingcards:server:shopWithdraw', function(src, amount)
    if not atLeast(src, CS.withdraw or 'manager') or not nearDesk(src) then return nil, 'You can’t take money from the till.' end
    amount = math.floor(tonumber(amount) or 0)
    if amount < 1 then return nil, 'Enter an amount.' end
    if Society.Balance() < amount then return nil, 'The till doesn’t have that much.' end
    if not Society.Remove(amount, 'withdraw') then return nil, 'The till doesn’t have that much.' end
    Framework.AddMoney(src, 'bank', amount, 'ascard-shop-withdraw')
    ledger(src, 'withdraw', -amount, 'Withdrawn')
    if MoneyLog then MoneyLog.Add(src, 'cardshop', amount, 'Withdrew from the shop till') end
    return manageInfo(src)
end)

lib.callback.register('as-tradingcards:server:shopDeposit', function(src, amount)
    if not atLeast(src, 'manager') or not nearDesk(src) then return nil, 'You can’t add to the till.' end
    amount = math.floor(tonumber(amount) or 0)
    if amount < 1 then return nil, 'Enter an amount.' end
    if not Framework.Charge(src, amount, 'ascard-shop-deposit') then return nil, 'You don’t have that much.' end
    Society.Add(amount, 'deposit')
    ledger(src, 'deposit', amount, 'Deposited')
    if MoneyLog then MoneyLog.Add(src, 'cardshop', -amount, 'Deposited into the shop till') end
    return manageInfo(src)
end)

lib.callback.register('as-tradingcards:server:shopOrder', function(src, item, qty)
    if not atLeast(src, CS.wholesale or 'owner') or not nearDesk(src) then return nil, 'Only the owner orders stock.' end
    qty = math.floor(tonumber(qty) or 0)
    local pct = (CS.wholesaleCatalogue or {}).pct or 0.7
    local maxPer = (CS.wholesaleCatalogue or {}).maxPerItem or 200
    local allow = (CS.wholesaleCatalogue or {}).items or {}
    local entry = shopEntry(item)
    if not entry then return nil, 'Not in the catalogue.' end
    if #allow > 0 then local ok for _, i in ipairs(allow) do if i == item then ok = true end end if not ok then return nil, 'Not in the catalogue.' end end
    if qty < 1 or qty > maxPer then return nil, ('Order 1 to %d.'):format(maxPer) end
    local have = MySQL.scalar.await("SELECT qty FROM ascard_shop_stock WHERE kind = 'item' AND item = ?", { item }) or 0
    if have + qty > maxPer * 2 then return nil, 'That would overfill the stockroom.' end
    local cost = math.floor(entry.price * pct) * qty
    if Society.Balance() < cost then return nil, ('The till needs %s for that order.'):format(money(cost)) end
    if not Society.Remove(cost, 'wholesale') then return nil, 'The till can’t cover it.' end
    stockItemAdd(item, qty, entry.price, math.floor(entry.price * pct))
    ledger(src, 'wholesale', -cost, ('%dx %s'):format(qty, entry.label))
    if MoneyLog then MoneyLog.Add(src, 'cardshop', 0, ('Wholesale order: %dx %s for %s'):format(qty, entry.label, money(cost))) end
    return manageInfo(src)
end)

--[[ ---------------------------------------------------------------------------
    GRADING FOR CUSTOMERS (staff submit)
--------------------------------------------------------------------------- ]]
local gradeReq, nextReq = {}, 0

lib.callback.register('as-tradingcards:server:shopGradeNearby', function(src)
    if not onDuty(src) or not Cardshop.NearCounter(src) then return nil, 'Clock on and stand at the counter.' end
    local out, me = {}, GetEntityCoords(GetPlayerPed(src))
    for _, s in ipairs(GetPlayers()) do
        s = tonumber(s)
        if s ~= src then
            local p = GetPlayerPed(s)
            if p ~= 0 and #(GetEntityCoords(p) - me) <= ((CS.grading or {}).nearby or 6.0) then out[#out + 1] = { id = s, name = name(s) } end
        end
    end
    return out
end)

lib.callback.register('as-tradingcards:server:shopGradeAsk', function(src, customer)
    customer = tonumber(customer)
    if not onDuty(src) or not Cardshop.NearCounter(src) then return nil, 'Clock on and stand at the counter.' end
    if (CS.grading or {}).enabled == false or not Config.Grading.enabled then return nil, 'Grading is off.' end
    if not online(customer) or not Cardshop.NearCounter(customer) then return nil, 'They need to be at the counter.' end
    nextReq = nextReq + 1
    gradeReq[nextReq] = { staff = src, customer = customer, at = os.time() }
    local cards = {}
    for _, item in ipairs(Inventory.GetItems(customer, Utils.IsCardItem)) do
        if not DB.IsStolen(item.metadata.serial) then
            cards[#cards + 1] = { slot = item.slot, serial = item.metadata.serial, title = Utils.CardTitle(item.metadata, item.name) }
        end
    end
    local tiers = {}
    for i, t in ipairs(Config.Grading.tiers or {}) do tiers[i] = { id = t.id, label = t.label, fee = t.fee, time = Utils.FormatTime(t.time) } end
    if #tiers == 0 then tiers[1] = { id = 'standard', label = 'Standard', fee = Config.Grading.fee, time = Utils.FormatTime(Config.Grading.time) } end
    TriggerClientEvent('as-tradingcards:client:gradeAsk', customer, { req = nextReq, staff = name(src), cards = cards, tiers = tiers, needCase = Config.Grading.requireCase, hasCase = Inventory.Count(customer, Config.Items.case) > 0 })
    Framework.Notify(src, ('Asked %s which card to send for grading.'):format(name(customer)), 'inform')
    return true
end)

lib.callback.register('as-tradingcards:server:shopGradeConfirm', function(src, req, slot, serial, tierId)
    local r = gradeReq[tonumber(req)]
    if not r or r.customer ~= src or os.time() - r.at > 120 then return nil, 'That request ran out.' end
    gradeReq[tonumber(req)] = nil
    if not online(r.staff) or not onDuty(r.staff) then return nil, 'The staff member has gone.' end
    if not Cardshop.NearCounter(src) then return nil, 'Stay at the counter.' end
    local ok, fee = Grading.Submit(src, slot, serial, tierId, true)
    if not ok then return nil, fee end
    Society.Add(fee, 'grading')
    ledger(r.staff, 'grading', fee, ('Grading for %s'):format(name(src)))
    MySQL.insert('INSERT INTO ascard_shop_gradings (`at`, staff, customer, serial, fee) VALUES (?, ?, ?, ?, ?)', { os.time(), Framework.GetIdentifier(r.staff), Framework.GetIdentifier(src), serial, fee })
    payCommission(r.staff, fee, 'grading fee')
    Framework.Notify(r.staff, ('%s sent a card for grading (%s)'):format(name(src), money(fee)), 'success')
    return true
end)

--[[ ---------------------------------------------------------------------------
    PAYROLL (hourly, paid from the till)
--------------------------------------------------------------------------- ]]
CreateThread(function()
    V2.Wait()
    local every = ((CS.pay or {}).every or 15)
    while true do
        Wait(every * 60000)
        local hourly = (CS.pay or {}).hourly or 0
        if hourly > 0 then
            local amount = math.floor(hourly * every / 60)
            for _, s in ipairs(Cardshop.staffSrc) do
                if online(s) and onDuty(s) then
                    local id = staffRow(s)
                    MySQL.update('UPDATE ascard_shop_staff SET minutes = minutes + ? WHERE identifier = ?', { every, id })
                    if amount > 0 then
                        if Society.Remove(amount, 'wages') then
                            Framework.AddMoney(s, (CS.pay or {}).account or 'bank', amount, 'ascard-shop-wage')
                            MySQL.update('UPDATE ascard_shop_staff SET earned = earned + ? WHERE identifier = ?', { amount, id })
                            ledger(s, 'wage', -amount, 'Wages')
                        else
                            Framework.Notify(s, 'The till couldn’t pay your wages this time.', 'error')
                            ledger(s, 'wage_missed', 0, 'The till couldn’t cover wages')
                        end
                    end
                end
            end
        end
        MySQL.update('DELETE FROM ascard_shop_ledger WHERE `at` < ?', { os.time() - (CS.ledgerKeepDays or 60) * 86400 })
    end
end)
