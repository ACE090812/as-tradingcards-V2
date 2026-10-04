--[[ Deck boxes. A deck box item (`ascard_deckbox`) holds up to Config.Battle.deckSize raw cards.
     The cards live in the ascard_decks table against the box id (like the binder), so giving the box away gives the cards.
     Rules: exactly deckSize cards to play, max `maxCopies` of one card, max `maxLegend` legend. Raw cards only. ]]
Decks = {}
local B = Config.Battle or {}
local ITEM = (B.deckItem) or 'ascard_deckbox'
Decks.Item = ITEM
local openDeck = {}   -- [src] = deckId

local function newId() return ('D%d%05d'):format(os.time(), math.random(0, 99999)) end

local function find(src, deckId)
    if not deckId then return nil end
    for _, item in ipairs(Inventory.GetItems(src, function(n) return n == ITEM end)) do
        if item.metadata.deckId == deckId then return item end
    end
end

function Decks.Rows(deckId)
    local out = {}
    for _, r in ipairs(MySQL.query.await('SELECT serial, card_id, item, metadata FROM ascard_decks WHERE box_id = ?', { deckId }) or {}) do
        out[#out + 1] = { serial = r.serial, cardId = r.card_id, item = r.item, meta = json.decode(r.metadata) or {} }
    end
    table.sort(out, function(a, b)
        local ca, cb = Config.Cards[a.cardId], Config.Cards[b.cardId]
        local ia, ib = ca and Utils.RarityIndex[ca.type] or 0, cb and Utils.RarityIndex[cb.type] or 0
        if ia ~= ib then return ia > ib end
        return a.serial < b.serial
    end)
    return out
end

-- returns ok, reason
function Decks.Validate(rows)
    if #rows ~= (B.deckSize or 30) then return false, ('needs exactly %d cards (has %d)'):format(B.deckSize or 30, #rows) end
    local copies, legends = {}, 0
    for _, r in ipairs(rows) do
        copies[r.cardId] = (copies[r.cardId] or 0) + 1
        if copies[r.cardId] > (B.maxCopies or 2) then return false, ('more than %d copies of one card'):format(B.maxCopies or 2) end
        local c = Config.Cards[r.cardId]
        if not c then return false, 'a card in the box no longer exists' end
        if c.type == (B.legendType or 'legend') then legends = legends + 1 end
        if legends > (B.maxLegend or 1) then return false, ('more than %d legend'):format(B.maxLegend or 1) end
    end
    return true
end

local function summary(rows)
    local ok, why = Decks.Validate(rows)
    return { count = #rows, valid = ok, why = why }
end

local function setLabel(src, item, rows)
    local meta = item.metadata
    meta.description = ('%d / %d cards'):format(#rows, B.deckSize or 30)
    Inventory.SetMetadata(src, item.slot, meta)
end

local function build(src, deckId)
    local item = find(src, deckId)
    if not item then return nil end
    local rows = Decks.Rows(deckId)
    local cards, copies, legends = {}, {}, 0
    for _, r in ipairs(rows) do
        cards[#cards + 1] = { serial = r.serial, cardId = r.cardId, display = Utils.BuildDisplay(r.meta, r.item) }
        copies[r.cardId] = (copies[r.cardId] or 0) + 1
        local c = Config.Cards[r.cardId]
        if c and c.type == (B.legendType or 'legend') then legends = legends + 1 end
    end
    local pocket = {}
    for _, it in ipairs(Inventory.GetItems(src, Utils.IsCardItem)) do
        local id = it.metadata.cardId
        if id and Config.Cards[id] and not DB.IsStolen(it.metadata.serial) then
            pocket[#pocket + 1] = { slot = it.slot, serial = it.metadata.serial, cardId = id, display = Utils.BuildDisplay(it.metadata, it.name) }
        end
    end
    table.sort(pocket, function(a, b)
        local ia, ib = Utils.RarityIndex[Config.Cards[a.cardId].type] or 0, Utils.RarityIndex[Config.Cards[b.cardId].type] or 0
        if ia ~= ib then return ia > ib end
        return a.slot < b.slot
    end)
    local ok, why = Decks.Validate(rows)
    return {
        id = deckId, name = item.metadata.label or 'Deck box', size = B.deckSize or 30, cards = cards, pocket = pocket,
        copies = copies, legends = legends, valid = ok, why = why,
        rules = { copies = B.maxCopies or 2, legend = B.maxLegend or 1, size = B.deckSize or 30 },
    }
end

function Decks.Open(src, item)
    local meta = item.metadata or {}
    if not meta.deckId then
        meta.deckId = newId()
        meta.description = ('0 / %d cards'):format(B.deckSize or 30)
        Inventory.SetMetadata(src, item.slot, meta)
    end
    openDeck[src] = meta.deckId
    local data = build(src, meta.deckId)
    if data then TriggerClientEvent('as-tradingcards:client:deckOpen', src, data) end
end

local function current(src)
    local id = openDeck[src]
    if id and find(src, id) then return id end
end

lib.callback.register('as-tradingcards:server:deckAdd', function(src, slot, serial)
    local id = current(src)
    if not id then return nil, 'Open your deck box first.' end
    local item = Inventory.GetSlot(src, tonumber(slot))
    if not item or not Utils.IsCardItem(item.name) or item.metadata.serial ~= serial then return nil, 'That card has moved.' end
    if DB.IsStolen(serial) then return nil, 'That card is reported stolen.' end
    local rows = Decks.Rows(id)
    if #rows >= (B.deckSize or 30) then return nil, 'The deck box is full.' end
    local cardId = item.metadata.cardId
    local card = Config.Cards[cardId]
    if not card then return nil, 'Unknown card.' end
    local same, legends = 0, 0
    for _, r in ipairs(rows) do
        if r.cardId == cardId then same = same + 1 end
        local c = Config.Cards[r.cardId]
        if c and c.type == (B.legendType or 'legend') then legends = legends + 1 end
    end
    if same >= (B.maxCopies or 2) then return nil, ('Only %d copies of one card are allowed.'):format(B.maxCopies or 2) end
    if card.type == (B.legendType or 'legend') and legends >= (B.maxLegend or 1) then return nil, ('Only %d legend per deck.'):format(B.maxLegend or 1) end
    DB.Seen(src, item.metadata)
    if not Inventory.RemoveItem(src, item.name, 1, item.slot, Inventory.name == 'ox' and item.metadata or nil) then return nil, 'That card has moved.' end
    MySQL.insert.await('INSERT INTO ascard_decks (box_id, serial, card_id, item, metadata) VALUES (?, ?, ?, ?, ?)',
        { id, serial, cardId, item.name, json.encode(item.metadata) })
    if SerialLog then SerialLog.Add(serial, 'deck', 'Put in a deck box') end
    local box = find(src, id)
    if box then setLabel(src, box, Decks.Rows(id)) end
    return build(src, id)
end)

lib.callback.register('as-tradingcards:server:deckRemove', function(src, serial)
    local id = current(src)
    if not id then return nil, 'Open your deck box first.' end
    local row = MySQL.single.await('SELECT item, metadata FROM ascard_decks WHERE box_id = ? AND serial = ?', { id, tostring(serial) })
    if not row then return nil, 'That card isn’t in the box.' end
    if not Inventory.CanCarry(src, row.item, 1) then return nil, 'No room in your pockets.' end
    if (MySQL.update.await('DELETE FROM ascard_decks WHERE box_id = ? AND serial = ?', { id, tostring(serial) }) or 0) == 0 then return nil, 'Already gone.' end
    Inventory.AddItem(src, row.item, 1, json.decode(row.metadata) or {})
    local box = find(src, id)
    if box then setLabel(src, box, Decks.Rows(id)) end
    return build(src, id)
end)

lib.callback.register('as-tradingcards:server:deckClear', function(src)
    local id = current(src)
    if not id then return nil, 'Open your deck box first.' end
    local rows = MySQL.query.await('SELECT serial, item, metadata FROM ascard_decks WHERE box_id = ?', { id }) or {}
    local freed = 0
    for _, r in ipairs(rows) do
        if Inventory.CanCarry(src, r.item, 1) and (MySQL.update.await('DELETE FROM ascard_decks WHERE box_id = ? AND serial = ?', { id, r.serial }) or 0) > 0 then
            Inventory.AddItem(src, r.item, 1, json.decode(r.metadata) or {})
            freed = freed + 1
        end
    end
    local box = find(src, id)
    if box then setLabel(src, box, Decks.Rows(id)) end
    local data = build(src, id)
    if data and freed < #rows then data.note = 'Some cards stayed in the box: no room in your pockets.' end
    return data
end)

lib.callback.register('as-tradingcards:server:deckRename', function(src, name)
    local id = current(src)
    if not id then return nil, 'Open your deck box first.' end
    local box = find(src, id)
    name = tostring(name or ''):gsub('[%c<>]', ''):sub(1, 32)
    box.metadata.label = name ~= '' and name or nil
    Inventory.SetMetadata(src, box.slot, box.metadata)
    return build(src, id)
end)

-- the lobby asks for your valid decks
function Decks.ForPlayer(src)
    local list = {}
    for _, item in ipairs(Inventory.GetItems(src, function(n) return n == ITEM end)) do
        local id = item.metadata.deckId
        if id then
            local rows = Decks.Rows(id)
            local s = summary(rows)
            list[#list + 1] = { id = id, name = item.metadata.label or 'Deck box', count = s.count, valid = s.valid, why = s.why }
        end
    end
    return list
end

AddEventHandler('playerDropped', function() openDeck[source] = nil end)
