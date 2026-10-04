--[[ Binder covers, playmats, gifting a card as a parcel, and holding a card in your hand ]]
local function name(src) return Framework.GetName(src) or GetPlayerName(src) or '?' end
local function online(s) return s and GetPlayerName(s) ~= nil end

local function nearShop(src)
    if IsNearRole and IsNearRole(src, 'shop') then return true end
    return Cardshop and Cardshop.NearCounter and Cardshop.NearCounter(src) or false
end

--[[ ---------------------------------------------------------------------------
    COVERS AND MATS
--------------------------------------------------------------------------- ]]
lib.callback.register('as-tradingcards:server:skinsInfo', function(src)
    local identifier = Framework.GetIdentifier(src)
    if not identifier then return nil end
    local _, covers = Binder.Themes(identifier, nil)
    local row = MySQL.single.await('SELECT mat FROM ascard_prefs WHERE identifier = ?', { identifier })
    local mats = {}
    for _, m in ipairs(Config.Mats.list) do
        mats[#mats + 1] = { id = m.id, label = m.label, bg = m.bg, line = m.line, slot = m.slot, image = m.image, custom = m.custom }
    end
    return {
        covers = covers, mats = mats, myMat = (row and row.mat) or Config.Mats.default,
        slabs = (Config.Skins or {}).slabs, nearShop = nearShop(src),
    }
end)

lib.callback.register('as-tradingcards:server:buyCover', function(src, id)
    local identifier = Framework.GetIdentifier(src)
    if not identifier then return nil end
    if not nearShop(src) then return nil, 'Covers are sold at the card shop.' end
    for _, t in ipairs((Config.Skins or {}).binders or {}) do
        if t.id == id then
            if (t.price or 0) <= 0 or V2.HasUnlock(identifier, 'binder', id) then return nil, 'You already own that cover.' end
            if not Framework.Charge(src, t.price, 'ascard-cover') then return nil, 'You can’t afford that.' end
            V2.AddUnlock(identifier, 'binder', id)
            if Cardshop and Cardshop.Revenue then Cardshop.Revenue(t.price, 'Binder cover: ' .. t.label, src) end
            if MoneyLog then MoneyLog.Add(src, 'shop_buy', -t.price, 'Binder cover: ' .. t.label) end
            Framework.Notify(src, ('%s cover unlocked. Pick it on the binder screen.'):format(t.label), 'success')
            return true
        end
    end
    return nil, 'Unknown cover.'
end)

lib.callback.register('as-tradingcards:server:setMat', function(src, id)
    local identifier = Framework.GetIdentifier(src)
    if not identifier then return nil end
    local ok = false
    for _, m in ipairs(Config.Mats.list) do if m.id == id then ok = true end end
    if not ok then return nil, 'Unknown mat.' end
    MySQL.query.await('INSERT INTO ascard_prefs (identifier, mat) VALUES (?, ?) ON DUPLICATE KEY UPDATE mat = VALUES(mat)', { identifier, id })
    return true
end)

--[[ ---------------------------------------------------------------------------
    GIFTING (Postal Prime parcel with a message)
--------------------------------------------------------------------------- ]]
local G = Config.Gift or {}

lib.callback.register('as-tradingcards:server:giftTargets', function(src)
    if not G.enabled then return nil end
    local out = {}
    for _, s in ipairs(GetPlayers()) do
        s = tonumber(s)
        if s ~= src and Framework.GetIdentifier(s) then out[#out + 1] = { id = s, name = name(s) } end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return { players = out, fee = G.fee or 0, max = G.messageMax or 140 }
end)

lib.callback.register('as-tradingcards:server:giftSend', function(src, slot, serial, target, message, hideName)
    if not G.enabled then return nil, 'Gifting is off.' end
    target = tonumber(target)
    if not target or target == src or not online(target) then return nil, 'They’re not around right now.' end
    local item = Inventory.GetSlot(src, tonumber(slot))
    if not item or not Utils.IsCollectible(item.name) or (serial and item.metadata.serial ~= serial) then return nil, 'That card has moved.' end
    serial = item.metadata.serial
    if DB.IsStolen(serial) then return nil, 'That card is reported stolen.' end
    local from, to = Framework.GetIdentifier(src), Framework.GetIdentifier(target)
    if not from or not to then return nil, 'Something went wrong.' end
    message = tostring(message or ''):gsub('[%c<>]', ' '):sub(1, G.messageMax or 140)
    local fee = math.floor(G.fee or 0)
    if fee > 0 and not Framework.Charge(src, fee, 'ascard-gift') then return nil, 'You can’t cover the postage.' end
    local meta = item.metadata
    DB.Seen(src, meta)
    if not Inventory.RemoveItem(src, item.name, 1, item.slot, Inventory.name == 'ox' and meta or nil) then
        if fee > 0 then Framework.AddMoney(src, 'cash', fee, 'ascard-gift-refund') end
        return nil, 'That card has moved.'
    end
    local title = Utils.CardTitle(meta, item.name)
    local sender = hideName and (G.sender or 'A friend') or name(src)
    local locker = Auctions.LockerFor and Auctions.LockerFor(to) or nil
    local ok = Auctions.Deliver(to, item.name, meta, 'Gift: ' .. title, locker, 'gift', nil, message ~= '' and message or nil, sender)
    if not ok then
        -- the delivery row is saved and retried; only a database failure ends up here
        Inventory.AddItem(src, item.name, 1, meta)
        if fee > 0 then Framework.AddMoney(src, 'cash', fee, 'ascard-gift-refund') end
        return nil, 'The parcel couldn’t be made.'
    end
    DB.SetOwner(meta.serial, to, meta.cardId)
    if SerialLog then SerialLog.Add(meta.serial, 'gift', ('Gifted by %s to %s'):format(name(src), name(target))) end
    Framework.Notify(src, ('Gift sent to %s. It will arrive as a parcel.'):format(name(target)), 'success')
    Framework.Notify(target, ('%s is sending you a gift. Watch for a parcel.'):format(hideName and 'Someone' or name(src)), 'inform')
    return true
end)

--[[ ---------------------------------------------------------------------------
    CARD IN HAND  (props nearby players see)
--------------------------------------------------------------------------- ]]
local holding = {}   -- [src] = { serial, slot }

local function stillHolding(src)
    local h = holding[src]
    if not h then return nil end
    local item = Inventory.GetSlot(src, h.slot)
    if not item or item.metadata.serial ~= h.serial then holding[src] = nil return nil end
    return item
end

RegisterNetEvent('as-tradingcards:server:handHold', function(slot)
    local src = source
    if not (Config.HandProp or {}).enabled then return end
    local item = Inventory.GetSlot(src, tonumber(slot))
    if not item or not Utils.IsCollectible(item.name) then return end
    holding[src] = { serial = item.metadata.serial, slot = item.slot }
    TriggerClientEvent('as-tradingcards:client:handStart', src, item.slot)
end)

RegisterNetEvent('as-tradingcards:server:handShow', function()
    local src = source
    local item = stillHolding(src)
    if not item then return end
    local now = os.time()
    local display = Utils.BuildDisplay(item.metadata, item.name)
    local coords = GetEntityCoords(GetPlayerPed(src))
    local n, from = 0, name(src)
    for _, s in ipairs(GetPlayers()) do
        s = tonumber(s)
        if s ~= src then
            local p = GetPlayerPed(s)
            if p ~= 0 and #(GetEntityCoords(p) - coords) <= ((Config.HandProp or {}).showRange or 6.0) then
                TriggerClientEvent('as-tradingcards:client:peekCard', s, display, from, (Config.Show or {}).duration or 8000)
                n = n + 1
            end
        end
    end
    Framework.Notify(src, n > 0 and ('Showed your card to %d %s.'):format(n, n == 1 and 'person' or 'people') or 'Nobody close enough to see it.', n > 0 and 'success' or 'error')
end)

RegisterNetEvent('as-tradingcards:server:handStop', function() holding[source] = nil end)
AddEventHandler('playerDropped', function() holding[source] = nil end)
