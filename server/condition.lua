--[[ Card condition: wear while carried, handling, water, drops, protection, cleaning bench ]]
if not (Config.Condition and Config.Condition.enabled) then return end

local CC = Config.Condition
local W = CC.wear
local ITEMS = CC.items
local sessions = {}      -- [src] = cleaning session
local lastWater = {}

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

-- write changed metadata back to the item (and keep the tooltip text in step)
local function save(inv, item)
    item.metadata.description = Utils.CardDescription(item.metadata, item.name)
    Inventory.SetMetadata(inv, item.slot, item.metadata)
end

local function isRawCard(item)
    return item and item.name and Utils.IsCardItem(item.name) and type(item.metadata) == 'table' and item.metadata.cardId
end

--[[ ---------------------------------------------------------------------------
    WEAR
--------------------------------------------------------------------------- ]]
local function applyWear(c, prot)
    if prot == 'toploader' then return false end
    local p = prot == 'sleeve' and W.sleeve or W.loose
    local changed = false
    if p.dust and (c.dust or 0) < 1 then c.dust = clamp((c.dust or 0) + p.dust * (0.5 + math.random()), 0, 1) changed = true end
    if p.scratchChance and math.random() < p.scratchChance then c.scratch = math.min(8, (c.scratch or 0) + 1) changed = true end
    if p.dingChance and math.random() < p.dingChance then c.ding = math.min(4, (c.ding or 0) + 1) changed = true end
    if p.whitenChance and math.random() < p.whitenChance then c.whiten = clamp((c.whiten or 0) + p.whiten, 0, 1) changed = true end
    if p.creaseChance and (c.crease or 0) == 0 and math.random() < p.creaseChance then c.crease = 1 changed = true end
    return changed
end

local function wearPlayer(src)
    for _, item in ipairs(Inventory.GetItems(src, Utils.IsCardItem)) do
        if isRawCard(item) then
            local changed = Condition.Ensure(item.metadata)
            if applyWear(item.metadata.cond, item.metadata.prot) then changed = true end
            if changed then save(src, item) end
        end
    end
end

CreateThread(function()
    while true do
        Wait(W.interval * 1000)
        for _, id in ipairs(GetPlayers()) do
            local src = tonumber(id)
            if not sessions[src] then pcall(wearPlayer, src) end
        end
    end
end)

-- viewing / showing a loose card leaves fingerprints
function ConditionHandle(src, item)
    if not isRawCard(item) then return end
    local meta = item.metadata
    local changed = Condition.Ensure(meta)
    if not meta.prot and math.random() < W.handleFingerprintChance then
        meta.cond.finger = clamp((meta.cond.finger or 0) + W.handleFingerprint, 0, 1)
        changed = true
    end
    if changed then save(src, item) end
end

-- the client reports swimming / heavy rain (it can only hurt the player's own cards)
RegisterNetEvent('as-tradingcards:server:wet', function(kind)
    local src = source
    local now = os.time()
    if lastWater[src] and now - lastWater[src] < W.waterCheck - 2 then return end
    lastWater[src] = now
    local chance = kind == 'swim' and W.swimWaterChance or kind == 'rain' and W.rainWaterChance or 0
    if chance <= 0 then return end
    for _, item in ipairs(Inventory.GetItems(src, Utils.IsCardItem)) do
        if isRawCard(item) and not item.metadata.prot then
            Condition.Ensure(item.metadata)
            if (item.metadata.cond.water or 0) == 0 and math.random() < chance then
                item.metadata.cond.water = 1
                save(src, item)
            end
        end
    end
end)

-- dropping a loose card on the floor can ding or crease it
if Inventory.name == 'ox' then
    local filter = {}
    for name in pairs(Utils.CardItems) do filter[name] = true end
    exports.ox_inventory:registerHook('swapItems', function(p)
        if p.toType ~= 'drop' and p.toInventory ~= 'newdrop' then return end
        local item = p.fromSlot
        if type(item) ~= 'table' or not isRawCard(item) or item.metadata.prot then return end
        Condition.Ensure(item.metadata)
        local c, changed = item.metadata.cond, false
        if math.random() < W.dropDingChance then c.ding = math.min(4, (c.ding or 0) + 1) changed = true end
        if (c.crease or 0) == 0 and math.random() < W.dropCreaseChance then c.crease = 1 changed = true end
        if changed then item.metadata.description = Utils.CardDescription(item.metadata, item.name) end
    end, { itemFilter = filter })
end

--[[ ---------------------------------------------------------------------------
    PROTECTION  (penny sleeve -> toploader)
--------------------------------------------------------------------------- ]]
function ConditionTools(src)
    return {
        sleeve = Inventory.Count(src, ITEMS.sleeve) > 0,
        toploader = Inventory.Count(src, ITEMS.toploader) > 0,
        loupe = Inventory.Count(src, ITEMS.loupe) > 0,
    }
end

lib.callback.register('as-tradingcards:server:protect', function(src, slot, serial, action)
    local item = GetVerifiedCollectible(src, slot, serial)
    if not isRawCard(item) then return false end
    local meta = item.metadata
    Condition.Ensure(meta)

    if action == 'sleeve' then
        if meta.prot then return false end
        if not Inventory.RemoveItem(src, ITEMS.sleeve, 1) then Framework.Notify(src, L('need_sleeve'), 'error') return false end
        meta.prot = 'sleeve'
    elseif action == 'toploader' then
        if meta.prot ~= 'sleeve' then Framework.Notify(src, L('toploader_needs_sleeve'), 'error') return false end
        if not Inventory.RemoveItem(src, ITEMS.toploader, 1) then Framework.Notify(src, L('need_toploader'), 'error') return false end
        meta.prot = 'toploader'
    elseif action == 'remove' then
        if meta.prot == 'toploader' then
            if not Inventory.AddItem(src, ITEMS.toploader, 1) then Framework.Notify(src, L('no_space', 1), 'error') return false end
            meta.prot = 'sleeve'
        elseif meta.prot == 'sleeve' then
            if not Inventory.AddItem(src, ITEMS.sleeve, 1) then Framework.Notify(src, L('no_space', 1), 'error') return false end
            meta.prot = nil
        else
            return false
        end
    else
        return false
    end

    save(src, item)
    return { card = Utils.BuildDisplay(meta, item.name), tools = ConditionTools(src) }
end)

--[[ ---------------------------------------------------------------------------
    CLEANING BENCH
--------------------------------------------------------------------------- ]]
local function nearBench(src, index)
    local b = CC.benches[tonumber(index) or 0]
    if not b then return false end
    return #(GetEntityCoords(GetPlayerPed(src)) - b.coords.xyz) <= 4.0
end

local function toolItem(src, name, maxUses)
    for _, it in ipairs(Inventory.GetItems(src, function(n) return n == name end)) do
        local uses = tonumber(it.metadata.uses) or maxUses
        if uses > 0 then return it, uses end
    end
end

lib.callback.register('as-tradingcards:server:cleanList', function(src, bench)
    if not nearBench(src, bench) then return nil end
    local cloth, clothUses = toolItem(src, ITEMS.cloth, CC.clothUses)
    if not cloth then Framework.Notify(src, L('need_cloth'), 'error') return nil end
    local _, sprayUses = toolItem(src, ITEMS.spray, CC.sprayUses)
    local list = {}
    for _, item in ipairs(Inventory.GetItems(src, Utils.IsCardItem)) do
        if isRawCard(item) then
            if Condition.Ensure(item.metadata) then save(src, item) end
            list[#list + 1] = {
                slot = item.slot, serial = item.metadata.serial,
                title = Utils.CardTitle(item.metadata, item.name),
                glance = Condition.Glance(item.metadata.cond),
                prot = item.metadata.prot,
            }
        end
    end
    return { cards = list, cloth = clothUses, spray = sprayUses or 0 }
end)

lib.callback.register('as-tradingcards:server:cleanStart', function(src, bench, slot, serial)
    if not nearBench(src, bench) then return nil end
    local item = GetVerifiedCollectible(src, slot, serial)
    if not isRawCard(item) then return nil end
    if item.metadata.prot then Framework.Notify(src, L('clean_take_out'), 'error') return nil end
    local _, clothUses = toolItem(src, ITEMS.cloth, CC.clothUses)
    if not clothUses then Framework.Notify(src, L('need_cloth'), 'error') return nil end
    local _, sprayUses = toolItem(src, ITEMS.spray, CC.sprayUses)
    Condition.Ensure(item.metadata)
    sessions[src] = { bench = bench, slot = item.slot, serial = serial }
    return {
        card = Utils.BuildDisplay(item.metadata, item.name),
        tools = { cloth = clothUses, spray = sprayUses or 0, clothMax = CC.clothUses, sprayMax = CC.sprayUses },
        loupe = Inventory.Count(src, ITEMS.loupe) > 0,
    }
end)

-- result: remaining share (0-1) of each cleanable layer, new scratches, whether the spray was used
lib.callback.register('as-tradingcards:server:cleanFinish', function(src, result)
    local s = sessions[src]
    sessions[src] = nil
    if not s or type(result) ~= 'table' or not nearBench(src, s.bench) then return false end
    local item = GetVerifiedCollectible(src, s.slot, s.serial)
    if not isRawCard(item) then return false end

    local cloth = toolItem(src, ITEMS.cloth, CC.clothUses)
    if not cloth then return false end
    local spray = result.sprayed and toolItem(src, ITEMS.spray, CC.sprayUses) or nil

    local c = item.metadata.cond
    local function keep(key, frac) -- can only ever go down
        frac = clamp(tonumber(frac) or 1, 0, 1)
        local v = (c[key] or 0) * frac
        c[key] = v < 0.04 and 0 or math.floor(v * 100 + 0.5) / 100
    end
    keep('dust', result.dust)
    keep('finger', result.finger)
    if spray then
        keep('dirt', result.dirt)
        keep('stain', result.stain)
    end
    local newScratches = clamp(math.floor(tonumber(result.scratch) or 0), 0, 3)
    if newScratches > 0 then c.scratch = math.min(8, (c.scratch or 0) + newScratches) end
    save(src, item)

    -- wear the tools
    local function use(tool, maxUses)
        local uses = (tonumber(tool.metadata.uses) or maxUses) - 1
        if uses <= 0 then
            Inventory.RemoveItem(src, tool.name, 1, tool.slot)
        else
            tool.metadata.uses = uses
            tool.metadata.durability = math.floor(uses / maxUses * 100)
            tool.metadata.description = ('%d/%d uses left'):format(uses, maxUses)
            Inventory.SetMetadata(src, tool.slot, tool.metadata)
        end
    end
    use(cloth, CC.clothUses)
    if spray then use(spray, CC.sprayUses) end

    local sc = Condition.Scores(c)
    Framework.Notify(src, L('clean_done', sc.surface), 'success')
    return { card = Utils.BuildDisplay(item.metadata, item.name) }
end)

lib.callback.register('as-tradingcards:server:cleanCancel', function(src)
    sessions[src] = nil
    return true
end)

AddEventHandler('playerDropped', function()
    sessions[source] = nil
    lastWater[source] = nil
end)
