--[[ The binder is a real binder: a stack of 9-sleeve pages.
     Any card can go in any sleeve - duplicates, parallels, whatever you like -
     and cards can be moved between sleeves or taken back out.
     Contents belong to the binder item (metadata.binderId), so giving someone
     your binder gives them the cards inside it.
     DB rows: ascard_binder.card_id holds the sleeve key "s<number>". ]]
Binder = {}

local PER_PAGE = 9
local openBinder = {}   -- [src] = binderId the player currently has open

local function capacity() return (Config.Binder and Config.Binder.pages or 20) * PER_PAGE end

-- setId -> sorted list of cards
local setCards = {}
for _, card in pairs(Config.Cards) do
    setCards[card.set] = setCards[card.set] or {}
    table.insert(setCards[card.set], card)
end
for _, list in pairs(setCards) do
    table.sort(list, function(a, b) return (a.number or 0) < (b.number or 0) end)
end

-- cover themes (Config.Skins.binders). Returns the active theme + the full list with owned flags.
function Binder.Themes(identifier, activeId)
    local unlocked = V2 and V2.Unlocks and identifier and V2.Unlocks(identifier, 'binder') or {}
    local list, active = {}, nil
    for i, t in ipairs((Config.Skins or {}).binders or {}) do
        local row = { id = t.id, label = t.label, price = t.price or 0, owned = (t.price or 0) <= 0 or unlocked[t.id] == true,
            cover = t.cover, edge = t.edge, ring = t.ring, title = t.title, spine = t.spine }
        list[#list + 1] = row
        if t.id == activeId or (not active and i == 1) then active = row end
    end
    if active and not active.owned then active = list[1] end
    return active, list
end

local function newBinderId()
    return ('B%d%05d'):format(os.time(), math.random(0, 99999))
end

local function key(n) return 's' .. n end

-- Finds the binder item with this id in the player's inventory
local function findBinder(src, binderId)
    if not binderId then return nil end
    for _, item in ipairs(Inventory.GetItems(src, function(n) return n == Config.Items.binder end)) do
        if item.metadata.binderId == binderId then return item end
    end
end

-- sleeves: [number] = { item, metadata }. Older binders keyed by card id get moved into sleeves.
local function loadSleeves(binderId)
    local rows = DB.GetBinder(binderId)
    local sleeves, legacy = {}, {}
    for k, v in pairs(rows) do
        local n = tonumber(tostring(k):match('^s(%d+)$'))
        if n then sleeves[n] = v else legacy[#legacy + 1] = { key = k, row = v } end
    end
    for _, l in ipairs(legacy) do
        for n = 1, capacity() do
            if not sleeves[n] then
                if DB.BinderRemove(binderId, l.key) and DB.BinderInsert(binderId, key(n), l.row.item, l.row.metadata) then
                    sleeves[n] = l.row
                end
                break
            end
        end
    end
    return sleeves
end

local function firstFree(sleeves)
    for n = 1, capacity() do
        if not sleeves[n] then return n end
    end
end

local function countFilled(sleeves)
    local n = 0
    for _ in pairs(sleeves) do n = n + 1 end
    return n
end

-- keeps the binder's inventory tooltip in step with what's inside
local function updateBinderLabel(src, binderId, sleeves)
    local item = findBinder(src, binderId)
    if not item then return end
    local meta = item.metadata
    meta.description = ('%d / %d sleeves filled'):format(countFilled(sleeves), capacity())
    Inventory.SetMetadata(src, item.slot, meta)
end

local function buildData(src, binderId)
    local identifier = Framework.GetIdentifier(src)
    if not identifier then return nil end

    local sleeves = loadSleeves(binderId)

    -- what's in the binder
    local filled, inBinder = {}, {}
    for n, v in pairs(sleeves) do
        filled[#filled + 1] = { slot = n, display = Utils.BuildDisplay(v.metadata, v.item) }
        if v.metadata.cardId then inBinder[v.metadata.cardId] = true end
    end

    -- loose cards in the inventory
    local inventory = {}
    for _, item in ipairs(Inventory.GetItems(src, Utils.IsCardItem)) do
        local id = item.metadata.cardId
        if id and Config.Cards[id] then
            inventory[#inventory + 1] = {
                slot = item.slot,
                serial = item.metadata.serial,
                cardId = id,
                owned = inBinder[id] == true,   -- already have this player in the binder
                display = Utils.BuildDisplay(item.metadata, item.name),
            }
        end
    end
    table.sort(inventory, function(a, b)
        local na, nb = Config.Cards[a.cardId].number or 0, Config.Cards[b.cardId].number or 0
        if na ~= nb then return na < nb end
        return (a.slot or 0) < (b.slot or 0)
    end)

    -- set progress: at least one of every player, any version, anywhere in the binder
    local sets = {}
    for setId, set in pairs(Config.Sets) do
        if (not Series2) or Series2.Visible(setId) then
            local have, total, missing = 0, 0, {}
            for _, card in ipairs(setCards[setId] or {}) do
                total = total + 1
                if inBinder[card.id] then have = have + 1 else missing[#missing + 1] = Utils.CardCode(card) end
            end
            sets[#sets + 1] = {
                id = setId, label = set.label, have = have, total = total,
            }
        end
    end
    table.sort(sets, function(a, b) return a.label < b.label end)

    local item = findBinder(src, binderId)
    local name = item and item.metadata and item.metadata.label or nil
    local theme, themes = Binder.Themes(identifier, item and item.metadata and item.metadata.theme)
    return { pages = math.floor(capacity() / PER_PAGE), filled = filled, inventory = inventory, sets = sets, name = name, theme = theme, themes = themes }, sleeves
end

function Binder.Open(src, item)
    local meta = item.metadata or {}
    local binderId = meta.binderId
    if not binderId then
        -- first use: give this binder its own id
        binderId = newBinderId()
        meta.binderId = binderId
        meta.description = ('0 / %d sleeves filled'):format(capacity())
        Inventory.SetMetadata(src, item.slot, meta)
    end
    openBinder[src] = binderId
    local data = buildData(src, binderId)
    if data then TriggerClientEvent('as-tradingcards:client:openBinder', src, data) end
end

-- player must still be holding the binder they opened
local function activeBinder(src)
    local binderId = openBinder[src]
    if binderId and findBinder(src, binderId) then return binderId end
    Framework.Notify(src, L('item_missing'), 'error')
end

local function validSleeve(n)
    n = tonumber(n)
    if n and n >= 1 and n <= capacity() and n == math.floor(n) then return n end
end

local function respond(src, binderId)
    local data, sleeves = buildData(src, binderId)
    updateBinderLabel(src, binderId, sleeves)
    return data
end

-- put a card from the inventory into a sleeve (target = sleeve number, or nil for the first empty one)
lib.callback.register('as-tradingcards:server:binderInsert', function(src, invSlot, serial, target)
    local binderId = activeBinder(src)
    if not binderId then return nil end

    local item = GetVerifiedCollectible(src, invSlot, serial)
    if not item or not Utils.IsCardItem(item.name) or not Config.Cards[item.metadata.cardId or ''] then
        Framework.Notify(src, L('item_missing'), 'error')
        return (buildData(src, binderId))
    end

    local sleeves = loadSleeves(binderId)
    local n = target and validSleeve(target) or firstFree(sleeves)
    if not n then
        Framework.Notify(src, L('binder_full'), 'error')
        return (buildData(src, binderId))
    end
    if sleeves[n] then
        Framework.Notify(src, L('binder_filled'), 'error')
        return (buildData(src, binderId))
    end

    if not Inventory.RemoveItem(src, item.name, 1, item.slot, Inventory.name == 'ox' and item.metadata or nil) then
        Framework.Notify(src, L('item_missing'), 'error')
        return (buildData(src, binderId))
    end

    if not DB.BinderInsert(binderId, key(n), item.name, item.metadata) then
        -- sleeve got filled in the meantime: hand the card back
        Inventory.AddItem(src, item.name, 1, item.metadata)
        Framework.Notify(src, L('binder_filled'), 'error')
    end

    return respond(src, binderId)
end)

-- take a card out of a sleeve and back into the inventory
lib.callback.register('as-tradingcards:server:binderRemove', function(src, n)
    local binderId = activeBinder(src)
    n = validSleeve(n)
    if not binderId or not n then return nil end

    local inside = loadSleeves(binderId)[n]
    if not inside then return (buildData(src, binderId)) end

    if Inventory.FreeSlots(src) < 1 then
        Framework.Notify(src, L('no_space', 1), 'error')
        return (buildData(src, binderId))
    end

    if DB.BinderRemove(binderId, key(n)) then
        if not Inventory.AddItem(src, inside.item, 1, inside.metadata) then
            DB.BinderInsert(binderId, key(n), inside.item, inside.metadata) -- put it back
            Framework.Notify(src, L('no_space', 1), 'error')
        end
    end

    return respond(src, binderId)
end)

-- move a card to another sleeve (swaps if that sleeve is taken)
lib.callback.register('as-tradingcards:server:binderMove', function(src, from, to)
    local binderId = activeBinder(src)
    from, to = validSleeve(from), validSleeve(to)
    if not binderId or not from or not to or from == to then return binderId and (buildData(src, binderId)) or nil end

    local sleeves = loadSleeves(binderId)
    local a, b = sleeves[from], sleeves[to]
    if not a then return (buildData(src, binderId)) end

    if DB.BinderRemove(binderId, key(from)) then
        if b and DB.BinderRemove(binderId, key(to)) then
            DB.BinderInsert(binderId, key(from), b.item, b.metadata)
        end
        if not DB.BinderInsert(binderId, key(to), a.item, a.metadata) then
            DB.BinderInsert(binderId, key(from), a.item, a.metadata)
        end
    end

    return (buildData(src, binderId))
end)

AddEventHandler('playerDropped', function()
    openBinder[source] = nil
end)

-- rename the binder that's open (from the binder screen)
lib.callback.register('as-tradingcards:server:binderRename', function(src, name)
    local binderId = openBinder[src]
    local item = binderId and findBinder(src, binderId)
    if not item then return nil end
    return RenameItem(src, item, name)
end)

-- pick a cover for the binder that's open
lib.callback.register('as-tradingcards:server:binderTheme', function(src, id)
    local binderId = openBinder[src]
    local item = binderId and findBinder(src, binderId)
    if not item then return nil end
    local identifier = Framework.GetIdentifier(src)
    local _, list = Binder.Themes(identifier, nil)
    for _, t in ipairs(list) do
        if t.id == id then
            if not t.owned then Framework.Notify(src, 'You don’t own that cover. The card shop sells them.', 'error') return nil end
            local meta = item.metadata
            meta.theme = t.id
            meta.image = 'ascard_binder_' .. t.id
            Inventory.SetMetadata(src, item.slot, meta)
            return t
        end
    end
    return nil
end)
