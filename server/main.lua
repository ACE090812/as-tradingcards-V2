local busy = {}
local showCooldown = {}

local function log(msg, ...)
    if Config.Debug then print(('[as-tradingcards] ' .. msg):format(...)) end
end

--[[ ---------------------------------------------------------------------------
    PACK OPENING  (everything decided server-side)
--------------------------------------------------------------------------- ]]
-- puts minted cards in the player's inventory (drops any that don't fit)
local function handOver(src, list)
    local failed = {}
    for _, c in ipairs(list) do
        if not Inventory.AddItem(src, c.item, 1, c.meta) then failed[#failed + 1] = { c.item, 1, c.meta } end
        if AnnouncePull then AnnouncePull(src, c.meta, c.item) end
        if Community then Community.LogPull(src, c.meta, c.item) end
    end
    -- inventory filled up mid-way: drop the rest at the player's feet (ox) so nothing is lost
    if #failed > 0 then
        if Inventory.name == 'ox' then
            local coords = GetEntityCoords(GetPlayerPed(src))
            exports.ox_inventory:CustomDrop('Trading Cards', failed, coords)
            Framework.Notify(src, 'Inventory full - some cards were dropped on the floor', 'error')
        else
            print(('^1[as-tradingcards] %s (%s) could not receive %d cards (inventory full)^0'):format(GetPlayerName(src), src, #failed))
            Framework.Notify(src, 'Inventory full - contact staff, some cards could not be given', 'error')
        end
    end
end

--[[ cards waiting to be turned over on the pack screen: [src] = { token, identifier, at, cards = { {item, meta, given} } } ]]
local pendingPacks = {}

local function flushPack(src)
    local p = pendingPacks[src]
    if not p then return end
    pendingPacks[src] = nil
    local rest = {}
    for _, c in ipairs(p.cards) do if not c.given then c.given = true rest[#rest + 1] = c end end
    if #rest > 0 then handOver(src, rest) end
end

-- mints the cards; gives them now, or (deferred) one by one as they're turned over. Returns displays + token
local function giveCards(src, rolls, deferred)
    local displays, minted = {}, {}
    local identifier = Framework.GetIdentifier(src)

    for _, roll in ipairs(rolls) do
        local meta = Cards.Mint(roll.cardId, roll.foil, roll.parallel, { insert = roll.insert, error = roll.error })
        local itemName = Cards.ItemFor(roll.cardId)
        if meta and itemName then
            minted[#minted + 1] = { item = itemName, meta = meta }
            displays[#displays + 1] = Utils.BuildDisplay(meta, itemName)
            if identifier then DB.LogPull(identifier, roll.cardId, roll.foil) DB.SetOwner(meta.serial, identifier, roll.cardId) end
            if Stats and identifier then Stats.Pull(identifier, meta, itemName) end
        end
    end

    if not deferred or #minted == 0 then
        handOver(src, minted)
        return displays
    end
    flushPack(src)   -- anything left from a pack before this one
    local token = ('%d%04d'):format(os.time(), math.random(0, 9999))
    pendingPacks[src] = { token = token, identifier = identifier, at = os.time(), cards = minted }
    return displays, token
end

RegisterNetEvent('as-tradingcards:server:packTake', function(token, index)
    local src = source
    local p = pendingPacks[src]
    if not p or p.token ~= tostring(token) then return end
    local c = p.cards[tonumber(index) or 0]
    if not c or c.given then return end
    c.given = true
    handOver(src, { c })
    for _, x in ipairs(p.cards) do if not x.given then return end end
    pendingPacks[src] = nil
end)

RegisterNetEvent('as-tradingcards:server:packDone', function(token)
    local src = source
    local p = pendingPacks[src]
    if p and (token == nil or p.token == tostring(token)) then flushPack(src) end
end)

-- safety net: never leave cards in limbo
CreateThread(function()
    while true do
        Wait(10000)
        local limit = (Config.PackOpening and Config.PackOpening.giveAllAfter) or 120
        for src, p in pairs(pendingPacks) do
            if os.time() - p.at >= limit then flushPack(src) end
        end
    end
end)

-- left the server mid-pack: the unturned cards go to their parcel locker
AddEventHandler('playerDropped', function()
    local src = source
    local p = pendingPacks[src]
    if not p then return end
    pendingPacks[src] = nil
    local lot = {}
    for _, c in ipairs(p.cards) do if not c.given then lot[#lot + 1] = { item = c.item, metadata = c.meta, title = Utils.CardTitle(c.meta, c.item) } end end
    if #lot == 0 or not p.identifier then return end
    if Auctions and Auctions.Deliver then
        Auctions.Deliver(p.identifier, lot[1].item, lot[1].metadata, ('%d cards from a pack you were opening'):format(#lot), Auctions.LockerFor(p.identifier), 'pack', #lot > 1 and lot or nil)
    else
        print(('^1[as-tradingcards] %s left mid-pack, %d cards not given^0'):format(p.identifier, #lot))
    end
end)

local function openPack(src, item)
    local pack = Config.Packs[item.name]
    if not pack or not DB.Ready then return end
    if busy[src] then return Framework.Notify(src, L('already_busy'), 'error') end
    if not Series2.Visible(pack.set) then return Framework.Notify(src, 'These packs aren’t out yet.', 'error') end

    -- space check (the pack frees a slot if it was the last one)
    local need = pack.cards
    local slotData = Inventory.GetSlot(src, item.slot)
    if slotData and slotData.name == item.name and slotData.count <= 1 then need = need - 1 end
    local free = Inventory.FreeSlots(src)
    if free < need then
        return Framework.Notify(src, L('no_space', need), 'error')
    end

    busy[src] = true
    local done = lib.callback.await('as-tradingcards:client:packProgress', src, pack.label)
    if not done then
        busy[src] = nil
        return
    end

    -- pack must still be there after the progress bar
    local removed = false
    slotData = Inventory.GetSlot(src, item.slot)
    if slotData and slotData.name == item.name then
        removed = Inventory.RemoveItem(src, item.name, 1, item.slot)
    elseif Inventory.Count(src, item.name) > 0 then
        removed = Inventory.RemoveItem(src, item.name, 1)
    end
    if not removed then
        busy[src] = nil
        return Framework.Notify(src, L('item_missing'), 'error')
    end

    -- packs from our shop/boxes were decided when made; others roll their hit now
    local pmeta = slotData and slotData.metadata or item.metadata or {}
    local hit = pmeta.hit == true
    if not pmeta.rolled and math.random() < (pack.insertChance or 0) then hit = true end
    local rolls = Cards.RollPack(item.name, { hit = hit or pmeta.caseHit == true, caseHit = pmeta.caseHit == true })
    local deferred = Config.PackOpening and Config.PackOpening.giveOnReveal
    local displays, token = giveCards(src, rolls or {}, deferred)
    log('%s opened %s -> %d cards', GetPlayerName(src), item.name, #displays)
    if Stats then Stats.Add(Framework.GetIdentifier(src), 'packs', 1) end

    TriggerClientEvent('as-tradingcards:client:openPack', src, {
        label = pack.label,
        art = pack.art or Config.PackArt,
        cards = displays,
        token = token,
    })
    busy[src] = nil
end

--[[ ---------------------------------------------------------------------------
    VIEW / SHOW CARD
--------------------------------------------------------------------------- ]]
local function viewCard(src, item)
    DB.Seen(src, item.metadata)
    if ConditionHandle then ConditionHandle(src, item) end
    local display = Utils.BuildDisplay(item.metadata, item.name)
    local tools = ConditionTools and ConditionTools(src) or nil
    TriggerClientEvent('as-tradingcards:client:viewCard', src, display, item.slot, Config.Show.enabled, tools)
end

RegisterNetEvent('as-tradingcards:server:showCard', function(slot)
    local src = source
    if not Config.Show.enabled then return end
    slot = tonumber(slot)

    local now = os.time()
    if showCooldown[src] and now - showCooldown[src] < Config.Show.cooldown then
        return Framework.Notify(src, L('show_cooldown'), 'error')
    end

    local item = Inventory.GetSlot(src, slot)
    if not item or not Utils.IsCollectible(item.name) then
        return Framework.Notify(src, L('item_missing'), 'error')
    end
    showCooldown[src] = now
    if ConditionHandle then ConditionHandle(src, item) end

    local display = Utils.BuildDisplay(item.metadata, item.name)
    local coords = GetEntityCoords(GetPlayerPed(src))
    local name = Framework.GetName(src)
    local count = 0

    for _, p in ipairs(lib.getNearbyPlayers(coords, Config.Show.radius) or {}) do
        if p.id ~= src then
            count = count + 1
            TriggerClientEvent('as-tradingcards:client:peekCard', p.id, display, name, Config.Show.duration)
        end
    end

    if count == 0 then
        Framework.Notify(src, L('nobody_near'), 'error')
    else
        Framework.Notify(src, L('shown_to', count), 'success')
    end
end)

--[[ ---------------------------------------------------------------------------
    USABLE ITEMS
--------------------------------------------------------------------------- ]]
--[[ ---------------------------------------------------------------------------
    BOOSTER BOX
--------------------------------------------------------------------------- ]]
local function openBox(src, item)
    local bx = Config.BoosterBox
    if busy[src] then return Framework.Notify(src, L('already_busy'), 'error') end
    if not Inventory.CanCarry(src, bx.gives.item, bx.gives.count) then
        return Framework.Notify(src, L('no_space', 1), 'error')
    end

    busy[src] = true
    local done = lib.callback.await('as-tradingcards:client:boxProgress', src, bx.label)
    if not done then busy[src] = nil return end

    local removed = false
    local slotData = Inventory.GetSlot(src, item.slot)
    if slotData and slotData.name == item.name then
        removed = Inventory.RemoveItem(src, item.name, 1, item.slot)
    elseif Inventory.Count(src, item.name) > 0 then
        removed = Inventory.RemoveItem(src, item.name, 1)
    end
    if not removed then
        busy[src] = nil
        return Framework.Notify(src, L('item_missing'), 'error')
    end

    local bmeta = (slotData and type(slotData.metadata) == 'table') and slotData.metadata or {}
    if bmeta.resealed and Seals then
        -- someone shrink-wrapped this: you get exactly the packs they put in
        local n = Seals.OpenResealed(src, bmeta)
        Framework.Notify(src, ('%s opened: %d packs. The wrap felt a bit loose...'):format(bx.label, n), 'inform')
        busy[src] = nil
        return
    end
    if Seals then Seals.Opened(bmeta) end

    if Cards.GivePacks(src, bx.gives.item, bx.gives.count) then
        local pack = Config.Packs[bx.gives.item]
        Framework.Notify(src, L('box_opened', bx.gives.count, pack and pack.label or bx.gives.item), 'success')
    else
        Inventory.AddItem(src, item.name, 1, bmeta) -- give the box back
        Framework.Notify(src, L('no_space', 1), 'error')
    end
    busy[src] = nil
end

--[[ ---------------------------------------------------------------------------
    BLASTERS, HOBBY BOXES, TINS  (Config.Boxes)
--------------------------------------------------------------------------- ]]
local function openProduct(src, item)
    local bx = Config.Boxes[item.name]
    if busy[src] then return Framework.Notify(src, L('already_busy'), 'error') end
    local unique = Config.Scale and Config.Scale.uniquePacks
    local packSlots = 0
    for _, g in ipairs(bx.gives) do packSlots = packSlots + ((unique and Config.Packs[g.item]) and g.count or 2) end
    if type(item.metadata) == 'table' and item.metadata.resealed then packSlots = #(item.metadata.contents or {}) end
    local slotsNeeded = packSlots + (bx.bonusCard and 1 or 0)
    if Inventory.FreeSlots(src) < slotsNeeded - 1 then return Framework.Notify(src, L('no_space', slotsNeeded), 'error') end

    busy[src] = true
    local done = lib.callback.await('as-tradingcards:client:boxProgress', src, bx.label, bx.duration)
    if not done then busy[src] = nil return end

    local slotData = Inventory.GetSlot(src, item.slot)
    local removed = slotData and slotData.name == item.name and Inventory.RemoveItem(src, item.name, 1, item.slot)
        or (Inventory.Count(src, item.name) > 0 and Inventory.RemoveItem(src, item.name, 1))
    if not removed then busy[src] = nil return Framework.Notify(src, L('item_missing'), 'error') end

    local bmeta = (slotData and slotData.name == item.name and type(slotData.metadata) == 'table') and slotData.metadata or (type(item.metadata) == 'table' and item.metadata) or {}
    if bmeta.resealed and Seals then
        local n = Seals.OpenResealed(src, bmeta)
        Framework.Notify(src, ('%s opened: %d packs. The wrap felt a bit loose...'):format(bx.label, n), 'inform')
        busy[src] = nil
        return
    end
    if Seals then Seals.Opened(bmeta) end

    local parts = {}
    for i, g in ipairs(bx.gives) do
        local ch = Config.CaseHits
        local caseHit = (i == 1 and ch and ch.enabled and ch.boxes and ch.boxes[item.name] and math.random() < 1 / ch.boxes[item.name]) and 1 or nil
        Cards.GivePacks(src, g.item, g.count, i == 1 and bx.guaranteedHits or nil, caseHit)
        local pk = Config.Packs[g.item]
        parts[#parts + 1] = ('%dx %s'):format(g.count, pk and pk.label or g.item)
    end

    -- tins: one limited card straight in
    if bx.bonusCard then
        local minIdx = Utils.RarityIndex[bx.bonusCard.minRarity] or 1
        local pool = {}
        for id, c in pairs(Config.Cards) do
            if (Utils.RarityIndex[c.rarity] or 0) >= minIdx and not DB.IsSoldOut(id) then pool[#pool + 1] = id end
        end
        if #pool > 0 then
            local cardId = pool[math.random(#pool)]
            local meta = Cards.Mint(cardId, bx.bonusCard.foil, nil)
            local itemName = Cards.ItemFor(cardId)
            if meta and Inventory.AddItem(src, itemName, 1, meta) then
                parts[#parts + 1] = Utils.CardTitle(meta, itemName)
                local id = Framework.GetIdentifier(src)
                if id then DB.LogPull(id, cardId, bx.bonusCard.foil) DB.SetOwner(meta.serial, id, cardId) end
            end
        end
    end
    Framework.Notify(src, ('%s opened: %s'):format(bx.label, table.concat(parts, ', ')), 'success')
    busy[src] = nil
end

local function useItem(src, item)
    if Config.Packs[item.name] then return openPack(src, item) end
    if Config.BoosterBox.enabled and item.name == Config.BoosterBox.item then return openBox(src, item) end
    if Config.Boxes and Config.Boxes[item.name] then return openProduct(src, item) end
    if Utils.IsCollectible(item.name) then return viewCard(src, item) end
    if item.name == Config.Items.binder then return Binder.Open(src, item) end
    if Config.Scale and Config.Scale.enabled and item.name == Config.Scale.item then return TriggerClientEvent('as-tradingcards:client:useScale', src) end
    if Config.SlabCase and Config.SlabCase.enabled and item.name == Config.SlabCase.item then return SlabCase.Open(src, item) end
    if Config.Appraisal and item.name == Config.Appraisal.item then return Appraisal.View(src, item) end
    if Config.Seals and Config.Seals.enabled and item.name == Config.Seals.shrinkwrap then return TriggerClientEvent('as-tradingcards:client:useShrinkwrap', src) end
    if item.name == Decks.Item then return Decks.Open(src, item) end
    if item.name == ((Config.Battle or {}).table or {}).item then return Battle and Battle.UseTableItem and Battle.UseTableItem(src) end
end

--[[ ox_inventory: items point at this export in their definition
     server = { export = '<this resource name>.useItem' }
     (framework usable-item hooks don't fire reliably through ox on QBX) ]]
exports('useItem', function(event, item, inventory, slot)
    if event ~= 'usingItem' then return end
    local src = inventory and inventory.id
    if type(src) ~= 'number' then return false end
    local data = Inventory.GetSlot(src, slot)
    if data and data.name == item.name then
        -- run outside ox's callback so the progress bar / DB calls don't hold it up
        CreateThread(function() useItem(src, data) end)
    end
    return false -- we handle removal ourselves; stops ox consuming the item
end)

CreateThread(function()
    while not Framework.name do Wait(500) end
    if Inventory.name == 'ox' then return end -- handled by the export above

    local names = { Decks.Item, ((Config.Battle or {}).table or {}).item, Config.Items.slab, Config.Items.binder, Config.BoosterBox.item, Config.Scale and Config.Scale.item, Config.SlabCase and Config.SlabCase.item, Config.Appraisal and Config.Appraisal.item, Config.Seals and Config.Seals.shrinkwrap }
    for packName in pairs(Config.Packs) do names[#names + 1] = packName end
    for boxName in pairs(Config.Boxes or {}) do names[#names + 1] = boxName end
    for _, t in ipairs(Config.Types) do names[#names + 1] = t.item end

    for _, name in ipairs(names) do
        Framework.RegisterUsableItem(name, useItem)
    end
end)

AddEventHandler('playerDropped', function()
    busy[source] = nil
    showCooldown[source] = nil
end)
