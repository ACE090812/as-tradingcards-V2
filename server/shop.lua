-- Is the player standing near a ped that has this role? (stops remote buy/sell/grade exploits)
local closedNote = {}
function IsNearRole(src, role)
    local coords = GetEntityCoords(GetPlayerPed(src))
    -- someone is on duty at the player card shop: the NPC steps back (collecting graded cards still works at the counter)
    if Cardshop and Cardshop.Staffed and Cardshop.Staffed() then
        if role == 'grader' and Cardshop.NearCounter and Cardshop.NearCounter(src) then return true end
        if role ~= 'grader' then return false end
    end
    for _, ped in ipairs(Config.Peds) do
        for _, r in ipairs(ped.roles) do
            if r == role and #(coords - ped.coords.xyz) <= Config.InteractDistance + 3.0 then
                -- opening hours (config/admin.lua)
                if ShopOpen and not ShopOpen(src) then
                    if (closedNote[src] or 0) < os.time() - 2 then
                        closedNote[src] = os.time()
                        Framework.Notify(src, ('The card shop is closed. %s.'):format(ShopHoursText()), 'error')
                    end
                    return false
                end
                return true
            end
        end
    end
    return false
end
AddEventHandler('playerDropped', function() closedNote[source] = nil end)

-- same card still in the same slot? (slot numbers can change while a menu is open)
function GetVerifiedCollectible(src, slot, serial)
    local item = Inventory.GetSlot(src, tonumber(slot))
    if not item or not Utils.IsCollectible(item.name) then return nil end
    if serial and item.metadata.serial ~= serial then return nil end
    return item
end

--[[ ---------------------------------------------------------------------------
    BUY
--------------------------------------------------------------------------- ]]
lib.callback.register('as-tradingcards:server:getShop', function(src)
    if not IsNearRole(src, 'shop') then return nil end
    if AdminFlags and AdminFlags.shop then Framework.Notify(src, 'The card shop is closed by staff right now.', 'error') return nil end
    local list = {}
    for i, e in ipairs(Series2.ShopItems()) do
        list[i] = { item = e.item, label = e.label, price = e.price, left = Stock and Stock.Left(e.item) or nil }
    end
    return list, Stock and Stock.NextRestock() or nil
end)

lib.callback.register('as-tradingcards:server:buy', function(src, index, amount)
    if not IsNearRole(src, 'shop') then return false end
    if AdminFlags and AdminFlags.shop then Framework.Notify(src, 'The card shop is closed by staff right now.', 'error') return false end
    local entry = Series2.ShopItems()[tonumber(index)]
    amount = math.floor(tonumber(amount) or 0)
    if not entry or amount < 1 or amount > Config.Shop.maxPerPurchase then return false end

    local unique = (Config.Packs[entry.item] and Config.Scale and Config.Scale.uniquePacks)
        or (Seals and Seals.IsBox(entry.item) and (Config.Seals or {}).enabled)   -- every sealed box has its own seal number
    if not Inventory.CanCarry(src, entry.item, amount) or (unique and Inventory.FreeSlots(src) < amount) then
        Framework.Notify(src, L('no_space', unique and amount or 1), 'error')
        return false
    end

    if Stock and not Stock.Take(entry.item, amount) then
        local left = Stock.Left(entry.item) or 0
        Framework.Notify(src, left > 0 and ('Only %d left this week.'):format(left) or 'Sold out this week. Restock is on the way.', 'error')
        return false
    end

    local price = entry.price * amount
    if not Framework.Charge(src, price, 'ascard-shop') then
        if Stock then Stock.Give(entry.item, amount) end
        Framework.Notify(src, L('not_enough_money'), 'error')
        return false
    end

    if not Cards.GivePacks(src, entry.item, amount) then
        if Stock then Stock.Give(entry.item, amount) end
        Framework.AddMoney(src, 'cash', price, 'ascard-shop-refund')
        Framework.Notify(src, L('no_space', 1), 'error')
        return false
    end

    if Stats then Stats.Add(Framework.GetIdentifier(src), 'spent', price) end
    if MoneyLog then MoneyLog.Add(src, 'shop_buy', -price, ('%dx %s'):format(amount, entry.label)) end
    Framework.Notify(src, L('bought', amount, entry.label, Utils.Money(price)), 'success')
    return true
end)

--[[ ---------------------------------------------------------------------------
    SELL
--------------------------------------------------------------------------- ]]
lib.callback.register('as-tradingcards:server:getSellable', function(src)
    if not Config.Buyer.enabled or not IsNearRole(src, 'buyer') then return nil end
    if AdminFlags and AdminFlags.sellBack then Framework.Notify(src, 'The shop isn’t buying cards right now.', 'error') return nil end
    local list = {}
    for _, item in ipairs(Inventory.GetItems(src, Utils.IsCollectible)) do
        list[#list + 1] = {
            slot = item.slot,
            serial = item.metadata.serial,
            title = Utils.CardTitle(item.metadata, item.name),
            rarity = Utils.BuildDisplay(item.metadata, item.name).rarity.label,
            price = Utils.CardValue(item.metadata, item.name),
        }
    end
    -- sealed product (worth more the longer the set has been out)
    local pay = (Config.Sealed or {}).buyerPays or 0.8
    for _, item in ipairs(Inventory.GetItems(src, function(n) return Utils.Sealed[n] end)) do
        local pk = Config.Packs[item.name] or (Config.Boxes or {})[item.name]
        list[#list + 1] = {
            slot = item.slot, sealed = true,
            title = ('%s (sealed)%s'):format(pk and pk.label or item.name, item.count > 1 and (' x' .. item.count) or ''),
            rarity = 'Sealed',
            price = math.floor(Utils.SealedValue(item.name) * pay),
        }
    end
    return list
end)

lib.callback.register('as-tradingcards:server:sell', function(src, slot, serial)
    if not Config.Buyer.enabled or not IsNearRole(src, 'buyer') then return false end
    if AdminFlags and AdminFlags.sellBack then Framework.Notify(src, 'The shop isn’t buying cards right now.', 'error') return false end
    local sealed = Inventory.GetSlot(src, tonumber(slot))
    if sealed and Utils.Sealed[sealed.name] then
        -- the clerk checks the wrap before buying a box
        if type(sealed.metadata) == 'table' and sealed.metadata.resealed then
            Framework.Notify(src, 'The clerk checks the seal number: this box isn’t factory sealed. They won’t buy it.', 'error')
            return false
        end
        local price = math.floor(Utils.SealedValue(sealed.name) * ((Config.Sealed or {}).buyerPays or 0.8))
        if not Inventory.RemoveItem(src, sealed.name, 1, sealed.slot) then return false end
        Framework.AddMoney(src, Config.Money.sellPaysTo, price, 'ascard-sell-sealed')
        if Stats then Stats.Add(Framework.GetIdentifier(src), 'sold', price) end
        if MoneyLog then MoneyLog.Add(src, 'sell_sealed', price, sealed.name .. (type(sealed.metadata) == 'table' and sealed.metadata.seal and (' seal ' .. sealed.metadata.seal) or '')) end
        if Seals and type(sealed.metadata) == 'table' then Seals.Opened(sealed.metadata, 'shop') end
        Framework.Notify(src, L('sold', ((Config.Boxes or {})[sealed.name] or Config.Packs[sealed.name] or {}).label or sealed.name, Utils.Money(price)), 'success')
        return true
    end
    local item = GetVerifiedCollectible(src, slot, serial)
    if not item then
        Framework.Notify(src, L('item_missing'), 'error')
        return false
    end

    if DB.IsStolen(item.metadata.serial) then
        Framework.Notify(src, L('buyer_stolen'), 'error')
        return false
    end
    local price = Utils.CardValue(item.metadata, item.name)
    DB.Seen(src, item.metadata)
    if not Inventory.RemoveItem(src, item.name, 1, item.slot, Inventory.name == 'ox' and item.metadata or nil) then
        Framework.Notify(src, L('item_missing'), 'error')
        return false
    end

    Framework.AddMoney(src, Config.Money.sellPaysTo, price, 'ascard-sell')
    if Stats then Stats.Add(Framework.GetIdentifier(src), 'sold', price) end
    if Repacks then Repacks.Add(item.name, item.metadata, price) end
    if MoneyLog then MoneyLog.Add(src, 'sell_back', price, ('%s (%s)'):format(Utils.CardTitle(item.metadata, item.name), item.metadata.serial or '?')) end
    if SerialLog then SerialLog.Add(item.metadata.serial, 'shop', ('Sold to the card shop for %s'):format(Utils.Money(price))) end
    Framework.Notify(src, L('sold', Utils.CardTitle(item.metadata, item.name), Utils.Money(price)), 'success')
    return true
end)
