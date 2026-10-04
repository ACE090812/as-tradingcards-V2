--[[ Pop report, weekly shop stock, pack scale, slab case and pack odds ]]

--[[ ---------------------------------------------------------------------------
    POP REPORT  (ascard_pop: card + version + grade -> how many graded)
--------------------------------------------------------------------------- ]]
Pop = { data = {} }   -- [cardId][variant][grade] = count

-- the version of a card the report counts separately
function Pop.Variant(meta)
    if meta.insert then return 'ins:' .. meta.insert end
    if meta.parallel then return 'par:' .. meta.parallel .. (meta.foil and ':foil' or '') end
    if meta.foil then return 'foil' end
    return 'base'
end

function Pop.VariantLabel(v)
    if v == 'base' then return 'Base' end
    if v == 'foil' then return Config.Foil.label end
    local kind, id, foil = v:match('^(%a+):([%w_]+):?(%a*)$')
    if kind == 'ins' then local t = Utils.InsertById[id] return t and t.label or id end
    if kind == 'par' then
        local p = Utils.ParallelById[id]
        local l = p and (p.maxPrints == 1 and (p.label .. ' 1/1') or ('%s /%d'):format(p.label, p.maxPrints)) or id
        return foil == 'foil' and (l .. ' ' .. Config.Foil.label) or l
    end
    return v
end

CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `ascard_pop` (
            `card_id` VARCHAR(64) NOT NULL,
            `variant` VARCHAR(40) NOT NULL,
            `grade` TINYINT NOT NULL,
            `count` INT NOT NULL DEFAULT 0,
            PRIMARY KEY (`card_id`, `variant`, `grade`)
        )
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `ascard_stock` (
            `item` VARCHAR(64) NOT NULL,
            `period` INT NOT NULL,
            `sold` INT NOT NULL DEFAULT 0,
            PRIMARY KEY (`item`)
        )
    ]])
    for _, r in ipairs(MySQL.query.await('SELECT card_id, variant, grade, `count` FROM ascard_pop') or {}) do
        Pop.data[r.card_id] = Pop.data[r.card_id] or {}
        Pop.data[r.card_id][r.variant] = Pop.data[r.card_id][r.variant] or {}
        Pop.data[r.card_id][r.variant][r.grade] = r.count
    end
    Stock.Load()
end)

function Pop.Add(meta)
    if not (Config.Pop and Config.Pop.enabled) or not meta.cardId or not meta.grade then return end
    local v = Pop.Variant(meta)
    local c = Pop.data[meta.cardId] or {}
    Pop.data[meta.cardId] = c
    c[v] = c[v] or {}
    c[v][meta.grade] = (c[v][meta.grade] or 0) + 1
    MySQL.insert('INSERT INTO ascard_pop (card_id, variant, grade, `count`) VALUES (?, ?, ?, 1) ON DUPLICATE KEY UPDATE `count` = `count` + 1',
        { meta.cardId, v, meta.grade })
end

-- { total, higher, same } for one slab: how rare is this exact grade?
function Pop.For(meta)
    local c = meta.cardId and Pop.data[meta.cardId]
    local row = c and c[Pop.Variant(meta)] or {}
    local total, higher = 0, 0
    for g, n in pairs(row) do
        total = total + n
        if g > (meta.grade or 0) then higher = higher + n end
    end
    return { total = total, same = row[meta.grade or 0] or 0, higher = higher, label = Pop.VariantLabel(Pop.Variant(meta)) }
end

-- whole report for one card (for the app / website)
function Pop.Report(cardId)
    local out, total = {}, 0
    for v, grades in pairs(Pop.data[cardId] or {}) do
        local row = { variant = v, label = Pop.VariantLabel(v), grades = {}, total = 0 }
        for g = 1, 10 do
            local n = grades[g] or 0
            row.grades[g] = n
            row.total = row.total + n
        end
        total = total + row.total
        out[#out + 1] = row
    end
    table.sort(out, function(a, b)
        if a.variant == 'base' then return true end
        if b.variant == 'base' then return false end
        return a.total > b.total
    end)
    return { rows = out, total = total }
end

--[[ ---------------------------------------------------------------------------
    WEEKLY STOCK
--------------------------------------------------------------------------- ]]
Stock = { sold = {}, period = {} }
local SC = Config.Stock or {}

-- number of the current stock week (changes at restockDay / restockHour)
local function currentPeriod()
    local now = os.time()
    local d = os.date('*t', now)
    -- seconds since the last restock moment
    local daysBack = (d.wday - 1 - (SC.restockDay or 5)) % 7
    local last = os.time({ year = d.year, month = d.month, day = d.day - daysBack, hour = SC.restockHour or 18, min = 0, sec = 0 })
    if last > now then last = last - 7 * 86400 end
    return math.floor(last / 3600), last + 7 * 86400
end

function Stock.Load()
    for _, r in ipairs(MySQL.query.await('SELECT item, period, sold FROM ascard_stock') or {}) do
        Stock.sold[r.item], Stock.period[r.item] = r.sold, r.period
    end
end

local function limit(item) return SC.enabled and SC.items and SC.items[item] or nil end

function Stock.Left(item)
    local max = limit(item)
    if not max then return nil end
    local p = currentPeriod()
    if Stock.period[item] ~= p then Stock.period[item], Stock.sold[item] = p, 0 end
    return math.max(0, max - (Stock.sold[item] or 0))
end

function Stock.NextRestock()
    local _, nextAt = currentPeriod()
    return nextAt
end

function Stock.Take(item, count)
    local left = Stock.Left(item)
    if left == nil then return true end
    if left < count then return false end
    Stock.sold[item] = (Stock.sold[item] or 0) + count
    MySQL.insert('INSERT INTO ascard_stock (item, period, sold) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE period = VALUES(period), sold = VALUES(sold)',
        { item, Stock.period[item], Stock.sold[item] })
    return true
end

function Stock.Give(item, count)   -- refund
    if limit(item) == nil then return end
    Stock.sold[item] = math.max(0, (Stock.sold[item] or 0) - count)
    MySQL.update('UPDATE ascard_stock SET sold = ? WHERE item = ?', { Stock.sold[item], item })
end

function Stock.List()
    local out = {}
    for _, e in ipairs(Series2.ShopItems()) do
        local left = Stock.Left(e.item)
        if left ~= nil then out[#out + 1] = { item = e.item, label = e.label, left = left, max = limit(e.item), price = e.price } end
    end
    return { items = out, nextRestock = Stock.NextRestock() }
end

--[[ ---------------------------------------------------------------------------
    PACK SCALE
--------------------------------------------------------------------------- ]]
local SCL = Config.Scale or {}

local function gaussian()
    local u1, u2 = math.max(1e-9, math.random()), math.random()
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
end

-- true grams of one pack: base + its own small difference (from its seal, so it never changes) + the hit
local function packGrams(meta)
    local g = SCL.baseGrams or 20.0
    local seal = tostring(meta.seal or '')
    if seal ~= '' then
        local h = 0
        for i = 1, #seal do h = (h * 31 + seal:byte(i)) % 1000003 end
        g = g + ((h % 1000) / 999 * 2 - 1) * (SCL.packSpread or 0.5)
    end
    if meta.hit then g = g + (SCL.hitGrams or 0.8) end
    return g
end

lib.callback.register('as-tradingcards:server:scaleList', function(src)
    if not SCL.enabled or Inventory.Count(src, SCL.item) < 1 then return nil end
    local out = {}
    for _, item in ipairs(Inventory.GetItems(src, function(n) return Config.Packs[n] ~= nil end)) do
        local pk = Config.Packs[item.name]
        out[#out + 1] = { slot = item.slot, label = pk.label, count = item.count, seal = item.metadata and item.metadata.seal }
    end
    return out
end)

local lastWeigh = {}
lib.callback.register('as-tradingcards:server:weigh', function(src, slot)
    if not SCL.enabled or Inventory.Count(src, SCL.item) < 1 then return nil end
    local now = GetGameTimer()
    if lastWeigh[src] and now - lastWeigh[src] < (SCL.time or 1500) * 0.8 then return nil end
    lastWeigh[src] = now
    local item = Inventory.GetSlot(src, tonumber(slot))
    if not item or not Config.Packs[item.name] then return nil end
    local grams = packGrams(item.metadata or {}) + gaussian() * (SCL.wobble or 0.15)
    return { grams = math.floor(grams * 10 + 0.5) / 10, label = Config.Packs[item.name].label, count = item.count }
end)
AddEventHandler('playerDropped', function() lastWeigh[source] = nil end)

--[[ ---------------------------------------------------------------------------
    SLAB CASE (ox_inventory stash that only takes slabs)
--------------------------------------------------------------------------- ]]
local SLC = Config.SlabCase or {}
SlabCase = {}

local function caseStash(id) return 'ascard_slabcase_' .. id end

local registered = {}
local function ensureStash(id, label)
    local stash = caseStash(id)
    if not registered[stash] then
        exports.ox_inventory:RegisterStash(stash, label or 'Slab Case', SLC.slots or 10, SLC.maxWeight or 5000, false)
        registered[stash] = true
    end
    return stash
end

function SlabCase.Open(src, item)
    if not SLC.enabled then return end
    if Inventory.name ~= 'ox' then return Framework.Notify(src, 'The slab case needs ox_inventory.', 'error') end
    local meta = item.metadata or {}
    if not meta.caseId then
        meta.caseId = ('C%d%04d'):format(os.time(), math.random(0, 9999))
        meta.description = ('Holds %d graded slabs'):format(SLC.slots or 10)
        Inventory.SetMetadata(src, item.slot, meta)
    end
    local stash = ensureStash(meta.caseId, meta.label)
    TriggerClientEvent('as-tradingcards:client:openSlabCase', src, stash)
end

-- slabs held in every case a player carries (for My cards)
function SlabCase.Contents(src)
    local out = {}
    if not SLC.enabled or Inventory.name ~= 'ox' then return out end
    for _, item in ipairs(Inventory.GetItems(src, function(n) return n == SLC.item end)) do
        local id = item.metadata and item.metadata.caseId
        if id then
            local stash = ensureStash(id)
            for _, s in pairs(exports.ox_inventory:GetInventoryItems(stash) or {}) do
                if s and s.name then out[#out + 1] = { name = s.name, metadata = s.metadata or {} } end
            end
        end
    end
    return out
end

if Inventory.name == 'ox' and SLC.enabled then
    CreateThread(function()
        exports.ox_inventory:registerHook('swapItems', function(p)
            local to = type(p.toInventory) == 'string' and p.toInventory or ''
            if to:find('^ascard_slabcase_') then
                local item = p.fromSlot
                if type(item) ~= 'table' or item.name ~= Config.Items.slab then
                    TriggerClientEvent('ox_lib:notify', p.source, { description = 'Only graded slabs fit in a slab case.', type = 'error' })
                    return false
                end
            end
        end, { inventoryFilter = { '^ascard_slabcase_' } })
    end)
end

--[[ ---------------------------------------------------------------------------
    PACK ODDS (for the website / app)
--------------------------------------------------------------------------- ]]
local function oneIn(p) if not p or p <= 0 then return nil end return math.floor(1 / p + 0.5) end

function PackOdds()
    local packs = {}
    local shopPrice = {}
    for _, e in ipairs(Config.Shop.items) do shopPrice[e.item] = e.price end
    local errChance = (Config.Errors or {}).chance or 0
    for name, pk in pairs(Config.Packs) do
        local total = 0
        for _, w in pairs(pk.weights or {}) do total = total + w end
        local types = {}
        for _, t in ipairs(Config.Types) do
            local w = (pk.weights or {})[t.id]
            if w and w > 0 then types[#types + 1] = { label = t.label, pct = math.floor(w / total * 1000 + 0.5) / 10 } end
        end
        local pars = {}
        for _, par in ipairs(Config.Parallels or {}) do
            pars[#pars + 1] = { label = par.maxPrints == 1 and (par.label .. ' 1/1') or ('%s /%d'):format(par.label, par.maxPrints), perPack = oneIn(par.chance * pk.cards) }
        end
        local guar = pk.guaranteed and ('%d %s or better'):format(pk.guaranteed.count, (Utils.RarityById[pk.guaranteed.minRarity] or {}).label or pk.guaranteed.minRarity) or nil
        packs[#packs + 1] = {
            item = name, label = pk.label, cards = pk.cards, price = shopPrice[name], types = types, guaranteed = guar,
            foil = pk.guaranteedFoil and ('%d guaranteed, then %d%% per card'):format(pk.guaranteedFoil, math.floor((pk.foilChance or 0) * 100 + 0.5))
                or ('%s%% per card'):format(math.floor((pk.foilChance or 0) * 1000 + 0.5) / 10),
            parallelGuaranteed = pk.guaranteedParallel or nil,
            parallels = pars,
            hit = oneIn(pk.insertChance),
            error = oneIn(errChance * pk.cards),
        }
    end
    table.sort(packs, function(a, b) return (a.price or 1e9) < (b.price or 1e9) end)
    local boxes = {}
    for name, bx in pairs(Config.Boxes or {}) do
        local parts = {}
        for _, g in ipairs(bx.gives) do parts[#parts + 1] = ('%d × %s'):format(g.count, (Config.Packs[g.item] or {}).label or g.item) end
        local ch = Config.CaseHits
        boxes[#boxes + 1] = { item = name, label = bx.label, price = shopPrice[name], contents = table.concat(parts, ', '),
            caseHit = ch and ch.enabled and ch.boxes and ch.boxes[name] or nil,
            hits = bx.guaranteedHits, bonus = bx.bonusCard and ('1 %s or better%s straight in'):format((Utils.RarityById[bx.bonusCard.minRarity] or {}).label or '', bx.bonusCard.foil and ' foil' or '') or nil,
            left = Stock.Left(name), max = limit(name) }
    end
    table.sort(boxes, function(a, b) return (a.price or 0) < (b.price or 0) end)
    local ins = {}
    local itotal = 0
    for _, t in ipairs((Config.Inserts or {}).types or {}) do if not t.caseHit then itotal = itotal + (t.weight or 0) end end
    for _, t in ipairs((Config.Inserts or {}).types or {}) do
        if not t.caseHit then
            ins[#ins + 1] = { label = t.label, max = t.maxPrints, share = itotal > 0 and math.floor(t.weight / itotal * 1000 + 0.5) / 10 or 0 }
        end
    end
    return { packs = packs, boxes = boxes, inserts = ins, stock = Stock.List() }
end

--[[ ---------------------------------------------------------------------------
    RENAME binders and slab cases (ox_inventory shows metadata.label as the item name)
--------------------------------------------------------------------------- ]]
local function renameable(name)
    return name == Config.Items.binder or (Config.SlabCase and name == Config.SlabCase.item)
end

function RenameItem(src, item, name)
    if not item or not renameable(item.name) then return nil end
    name = tostring(name or ''):gsub('~.-~', ''):gsub('[%c<>\\^]', ''):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 30)
    local meta = item.metadata or {}
    meta.label = name ~= '' and name or nil
    Inventory.SetMetadata(src, item.slot, meta)
    if item.name == (Config.SlabCase or {}).item and meta.caseId and Inventory.name == 'ox' then
        pcall(function()
            exports.ox_inventory:RegisterStash('ascard_slabcase_' .. meta.caseId, meta.label or 'Slab Case', Config.SlabCase.slots or 10, Config.SlabCase.maxWeight or 5000, false)
        end)
    end
    Framework.Notify(src, meta.label and ('Renamed to "%s"'):format(meta.label) or 'Name reset', 'success')
    return { name = meta.label }
end

lib.callback.register('as-tradingcards:server:rename', function(src, slot, name)
    local item = Inventory.GetSlot(src, tonumber(slot))
    if not item or not renameable(item.name) then return nil end
    return RenameItem(src, item, name)
end)

lib.callback.register('as-tradingcards:server:renameInfo', function(src, slot)
    local item = Inventory.GetSlot(src, tonumber(slot))
    if not item or not renameable(item.name) then return nil end
    return { name = item.metadata and item.metadata.label or '', kind = item.name == Config.Items.binder and 'binder' or 'slab case' }
end)
