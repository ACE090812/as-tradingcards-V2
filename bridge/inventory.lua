-- Server-side inventory bridge: ox_inventory / qb-inventory (+ forks using QBCore player functions)
Inventory = { name = nil }

local function started(res) return GetResourceState(res) == 'started' end

do
    local cfg = Config.Inventory
    if cfg == 'ox' or (cfg == 'auto' and started('ox_inventory')) then
        Inventory.name = 'ox'
    elseif cfg == 'qb' or (cfg == 'auto' and (Framework.name == 'qb' or Framework.name == 'qbx')) then
        Inventory.name = 'qb'
    end
    if Framework.name == 'esx' and Inventory.name ~= 'ox' then
        print('^1[as-tradingcards] ESX requires ox_inventory (cards need item metadata)^0')
    end
    print(('^2[as-tradingcards] inventory: %s^0'):format(tostring(Inventory.name)))
end

local ox = Inventory.name == 'ox' and exports.ox_inventory or nil

local function qbPlayer(src) return Framework.GetPlayer(src) end

local function itemBox(src, name, action, count)
    if Inventory.name ~= 'qb' then return end
    local QBCore = Framework.GetQBCore()
    local shared = QBCore and QBCore.Shared.Items[name]
    if not shared and Framework.name == 'qbx' then
        shared = exports.ox_inventory:Items(name)
    end
    if shared then TriggerClientEvent(Config.QBItemBoxEvent, src, shared, action, count or 1) end
end

local function normalise(item)
    if not item then return nil end
    return {
        name = item.name,
        slot = item.slot,
        count = item.count or item.amount or 1,
        metadata = item.metadata or item.info or {},
    }
end

function Inventory.AddItem(src, name, count, metadata)
    if ox then
        local ok = ox:AddItem(src, name, count, metadata)
        return ok and true or false
    end
    local p = qbPlayer(src)
    if not p then return false end
    local ok = p.Functions.AddItem(name, count, false, metadata)
    if ok then itemBox(src, name, 'add', count) end
    return ok and true or false
end

-- slot/metadata optional (slot is strongly recommended for unique items)
function Inventory.RemoveItem(src, name, count, slot, metadata)
    if ox then
        return ox:RemoveItem(src, name, count, metadata, slot) and true or false
    end
    local p = qbPlayer(src)
    if not p then return false end
    local ok = p.Functions.RemoveItem(name, count, slot)
    if ok then itemBox(src, name, 'remove', count) end
    return ok and true or false
end

function Inventory.GetSlot(src, slot)
    if not slot then return nil end
    if ox then return normalise(ox:GetSlot(src, slot)) end
    local p = qbPlayer(src)
    if not p then return nil end
    return normalise(p.Functions.GetItemBySlot(slot) or p.PlayerData.items[slot])
end

-- Returns a list of normalised items; filter(name) -> bool optional
function Inventory.GetItems(src, filter)
    local raw
    if ox then
        raw = ox:GetInventoryItems(src) or {}
    else
        local p = qbPlayer(src)
        raw = p and p.PlayerData.items or {}
    end
    local list = {}
    for _, item in pairs(raw) do
        if item and item.name and (not filter or filter(item.name)) then
            list[#list + 1] = normalise(item)
        end
    end
    table.sort(list, function(a, b) return (a.slot or 0) < (b.slot or 0) end)
    return list
end

function Inventory.Count(src, name)
    if ox then return ox:GetItemCount(src, name) or 0 end
    local total = 0
    for _, item in ipairs(Inventory.GetItems(src, function(n) return n == name end)) do
        total = total + item.count
    end
    return total
end

function Inventory.FreeSlots(src)
    if ox then
        local inv = ox:GetInventory(src)
        if not inv then return 0 end
        local used = 0
        for _, item in pairs(inv.items or {}) do
            if item and item.name then used = used + 1 end
        end
        return (inv.slots or 0) - used
    end
    local p = qbPlayer(src)
    if not p then return 0 end
    local used = 0
    for _, item in pairs(p.PlayerData.items or {}) do
        if item and item.name then used = used + 1 end
    end
    return Config.QBMaxSlots - used
end

function Inventory.CanCarry(src, name, count)
    if ox then return ox:CanCarryItem(src, name, count) and true or false end
    return Inventory.FreeSlots(src) > 0
end

-- Replace an item's metadata in place
function Inventory.SetMetadata(src, slot, metadata)
    if ox then return ox:SetMetadata(src, slot, metadata) end
    local p = qbPlayer(src)
    if not p then return end
    local items = p.PlayerData.items
    if items and items[slot] then
        items[slot].info = metadata
        p.Functions.SetPlayerData('items', items)
    end
end
