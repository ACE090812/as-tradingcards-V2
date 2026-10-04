--[[ Inventory pictures: each card item shows a picture of that card (ox_inventory).
     ox_inventory uses metadata.imageurl when it is set, so every card item gets:
       html/img/cards/<cardId>.webp                ->  a picture of the full card (preferred)
       html/img/players/<cardId>.png/.jpg/.webp   ->  nui://<this resource>/html/img/players/...
       otherwise Config.PhotoUrl (online)          ->  that URL
       no photo at all                             ->  html/img/items/<item>.png (card type picture)
     Cards already in inventories are updated when the resource starts and whenever an inventory is opened.
     Graded slabs show html/img/slabs/<cardId>.webp (the card inside a slab) unless Config.SlabPhotoIcon = false. ]]
CardImages = {}

local res = GetCurrentResourceName()
local EXT = { 'png', 'jpg', 'webp' }
local cache = {}

local slabCache = {}
function CardImages.GetSlab(cardId)
    if not cardId then return nil end
    local hit = slabCache[cardId]
    if hit ~= nil then return hit or nil end
    local path = ('html/img/slabs/%s.webp'):format(cardId)
    slabCache[cardId] = LoadResourceFile(res, path) and ('nui://%s/%s'):format(res, path) or false
    return slabCache[cardId] or nil
end

function CardImages.Get(cardId)
    if not cardId then return nil end
    local hit = cache[cardId]
    if hit ~= nil then return hit or nil end
    -- 1st choice: the picture of the whole card (html/img/cards/<id>.webp, made by the card renderer)
    local cardPic = ('html/img/cards/%s.webp'):format(cardId)
    if LoadResourceFile(res, cardPic) then
        cache[cardId] = ('nui://%s/%s'):format(res, cardPic)
        return cache[cardId]
    end
    for _, ext in ipairs(EXT) do
        local path = ('html/img/players/%s.%s'):format(cardId, ext)
        if LoadResourceFile(res, path) then
            cache[cardId] = ('nui://%s/%s'):format(res, path)
            return cache[cardId]
        end
    end
    local url = Config.PhotoUrl
    if type(url) == 'string' and url ~= '' then
        local s, e = url:find('{id}', 1, true)
        cache[cardId] = s and (url:sub(1, s - 1) .. cardId .. url:sub(e + 1)) or url
        return cache[cardId]
    end
    cache[cardId] = false
    return nil
end

local function wantsPhoto(name)
    if Utils.IsCardItem(name) then return true end
    return Config.SlabPhotoIcon == true and name == Config.Items.slab
end

-- sets metadata.imageurl on a metadata table; returns true if it changed
function CardImages.Apply(itemName, meta)
    if type(meta) ~= 'table' or not meta.cardId then return false end
    if not Utils.IsCardItem(itemName) and itemName ~= Config.Items.slab then return false end
    local url
    if itemName == Config.Items.slab then
        -- graded: a picture of this card inside the slab (html/img/slabs/<id>.webp)
        url = Config.SlabPhotoIcon ~= false and CardImages.GetSlab(meta.cardId) or nil
    else
        url = CardImages.Get(meta.cardId)
    end
    -- no photo yet: use this resource's own picture for the card type, so the slot is never blank
    if not url then url = ('nui://%s/html/img/items/%s.png'):format(res, itemName) end
    if meta.imageurl == url then return false end
    meta.imageurl = url
    return true
end

if Inventory.name ~= 'ox' then return end -- only ox_inventory supports per-item pictures

local ox = exports.ox_inventory

local function refreshInventory(inv)
    local items = ox:GetInventoryItems(inv)
    if not items then return end
    for _, item in pairs(items) do
        if item and item.name and type(item.metadata) == 'table' and CardImages.Apply(item.name, item.metadata) then
            ox:SetMetadata(inv, item.slot, item.metadata)
        end
    end
end
CardImages.Refresh = refreshInventory

local filter = {}
for name in pairs(Utils.CardItems) do filter[name] = true end
filter[Config.Items.slab] = true

-- new cards (packs, binder, grading, /givecard) get their picture as they are created
ox:registerHook('createItem', function(payload)
    local meta = payload.metadata
    if type(meta) == 'table' and CardImages.Apply(payload.item and payload.item.name, meta) then
        return meta
    end
end, { itemFilter = filter })

-- older cards get it the next time the inventory is opened (theirs, a stash, a trunk...)
pcall(function()
    ox:registerHook('openInventory', function(payload)
        if payload.inventoryId then SetTimeout(0, function() refreshInventory(payload.inventoryId) end) end
        if payload.source then SetTimeout(0, function() refreshInventory(payload.source) end) end
    end, {})
end)

-- everyone online: when the resource starts, then every 30 seconds (only changed cards are touched)
local function refreshAll()
    for _, id in ipairs(GetPlayers()) do refreshInventory(tonumber(id)) end
end
CreateThread(function()
    Wait(2000)
    while true do
        refreshAll()
        Wait(30000)
    end
end)

-- /cardimages: fix every online player's card pictures right now (admin)
lib.addCommand('cardimages', { help = 'Refresh the inventory pictures of card items', restricted = 'group.admin' }, function(src)
    cache = {}
    slabCache = {}
    refreshAll()
    if src > 0 then TriggerClientEvent('ox_lib:notify', src, { description = 'Card pictures refreshed', type = 'success' }) end
end)
