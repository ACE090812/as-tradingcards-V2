Cards = {}

-- pools[setId][rarityId] = { card, card, ... }
local pools = {}
for id, card in pairs(Config.Cards) do
    pools[card.set] = pools[card.set] or {}
    pools[card.set][card.rarity] = pools[card.set][card.rarity] or {}
    table.insert(pools[card.set][card.rarity], card)
end

local function available(setId, rarityId, reserved)
    local list = {}
    for _, card in ipairs((pools[setId] or {})[rarityId] or {}) do
        local extra = reserved[card.id] or 0
        if (not card.maxPrints or (DB.GetPrinted(card.id) + extra) < card.maxPrints) and (not card.seasonal or Seasonal.Active(card)) then
            list[#list + 1] = card
        end
    end
    return list
end

local function pickCard(list)
    local weights = {}
    for i, card in ipairs(list) do weights[i] = card.weight end
    return list[Utils.WeightedPick(weights)]
end

local function rollOne(pack, minIdx, reserved)
    local weights = {}
    for rarityId, w in pairs(pack.weights) do
        local idx = Utils.RarityIndex[rarityId]
        if idx and idx >= minIdx and #available(pack.set, rarityId, reserved) > 0 then
            weights[rarityId] = w
        end
    end

    -- everything at/above the guarantee is sold out -> fall back to any rarity
    if not next(weights) and minIdx > 1 then return rollOne(pack, 1, reserved) end

    local rarityId = Utils.WeightedPick(weights)
    if not rarityId then return nil end

    local card = pickCard(available(pack.set, rarityId, reserved))
    if not card then return nil end

    reserved[card.id] = (reserved[card.id] or 0) + 1
    return {
        cardId = card.id,
        rarity = rarityId,
        foil = math.random() < (pack.foilChance or 0),
        parallel = Cards.RollParallel(card.id, reserved),
    }
end

-- Checks rarest first; a parallel only drops while that player's run isn't used up
function Cards.RollParallel(cardId, reserved)
    local list = Config.Parallels or {}
    for i = #list, 1, -1 do
        local par = list[i]
        if math.random() < (par.chance or 0) then
            local key = DB.ParallelKey(cardId, par.id)
            local extra = reserved and reserved[key] or 0
            if DB.ParallelLeft(cardId, par) - extra > 0 then
                if reserved then reserved[key] = extra + 1 end
                return par.id
            end
        end
    end
end

-- picks an insert type that still has prints left for this card
local function rollInsertType(cardId, reserved, caseHit)
    local list = {}
    for _, t in ipairs(Config.Inserts.types) do
        local key = cardId .. ':ins:' .. t.id
        local wanted
        if caseHit then wanted = t.id == ((Config.CaseHits or {}).insert or 'legendsgame')
        else wanted = not t.caseHit and (t.weight or 0) > 0 end
        if wanted and DB.GetPrinted(key) + (reserved[key] or 0) < t.maxPrints then list[#list + 1] = t end
    end
    if #list == 0 then return nil end
    local w = {}
    for i, t in ipairs(list) do w[i] = math.max(t.weight or 0, 1) end
    local t = list[Utils.WeightedPick(w)]
    local key = cardId .. ':ins:' .. t.id
    reserved[key] = (reserved[key] or 0) + 1
    return t.id
end

-- a chase card: any card type (weighted), with an insert that still has prints left
local function rollInsertCard(pack, reserved, caseHit)
    for _ = 1, caseHit and 30 or 10 do
        local typeId = Utils.WeightedPick(caseHit and (Config.CaseHits or {}).cardWeights or Config.Inserts.cardWeights)
        local list = available(pack.set, typeId, reserved)
        local card = #list > 0 and list[math.random(#list)]
        if card then
            local ins = rollInsertType(card.id, reserved, caseHit)
            if ins then
                reserved[card.id] = (reserved[card.id] or 0) + 1
                return { cardId = card.id, rarity = card.rarity, insert = ins }
            end
        end
    end
end

-- Rolls a whole pack. Returns list sorted low -> high rarity (best card revealed last).
-- opts.hit = this pack holds an autograph / relic
function Cards.RollPack(packName, opts)
    local pack = Config.Packs[packName]
    if not pack then return nil end
    opts = opts or {}

    local results, reserved = {}, {}
    local g = pack.guaranteed or { count = 0 }
    local minGuaranteed = Utils.RarityIndex[g.minRarity or ''] or 1
    if opts.caseHit then opts.hit = true end
    local slots = pack.cards - (opts.hit and 1 or 0)

    for i = 1, slots do
        local minIdx = (i > slots - (g.count or 0)) and minGuaranteed or 1
        local roll = rollOne(pack, minIdx, reserved)
        if roll then results[#results + 1] = roll end
    end

    -- guaranteed foil / parallel
    if pack.guaranteedFoil then
        local foils = 0
        for _, r in ipairs(results) do if r.foil then foils = foils + 1 end end
        for i = 1, math.min(#results, pack.guaranteedFoil - foils) do results[#results - i + 1].foil = true end
    end
    if pack.guaranteedParallel then
        local has = false
        for _, r in ipairs(results) do if r.parallel then has = true end end
        if not has and #results > 0 then
            local r = results[#results]
            local par = Config.Parallels[1]
            if par and DB.ParallelLeft(r.cardId, par) > 0 then r.parallel = par.id end
        end
    end

    -- rare misprints
    local ec = Config.Errors
    if ec and ec.chance > 0 then
        local w = {}
        for i, e in ipairs(ec.kinds) do w[i] = e.weight end
        for _, r in ipairs(results) do
            if math.random() < ec.chance then r.error = ec.kinds[Utils.WeightedPick(w)].id end
        end
    end

    if opts.hit then
        local hit = opts.caseHit and rollInsertCard(pack, reserved, true) or nil
        hit = hit or rollInsertCard(pack, reserved)
        if hit then results[#results + 1] = hit else
            local r = rollOne(pack, 1, reserved) if r then results[#results + 1] = r end
        end
    end

    local function score(r)
        local it = r.insert and Utils.InsertById[r.insert]
        return (r.insert and 1000 or 0) + ((it and it.caseHit) and 1000 or 0) + (Utils.ParallelIndex[r.parallel or ''] or 0) * 20 + (Utils.RarityIndex[r.rarity] or 0) * 2 + (r.foil and 1 or 0)
    end
    table.sort(results, function(a, b) return score(a) < score(b) end)
    return results
end

-- give sealed packs: each pack is decided now (hit or not); hit packs weigh a bit more.
-- forceHits = how many of them must hold a hit (hobby boxes)
function Cards.GivePacks(src, name, count, forceHits, caseHits)
    local pack = Config.Packs[name]
    if not pack then
        -- sealed boxes: each one gets its own registered factory seal
        if Seals and Seals.IsBox(name) and (Config.Seals or {}).enabled then
            local ok = true
            for _ = 1, count do ok = Inventory.AddItem(src, name, 1, Seals.New(name)) and ok end
            return ok
        end
        return Inventory.AddItem(src, name, count)
    end
    local hits = 0
    for i = 1, count do
        local left = count - i + 1
        if (forceHits or 0) > hits and left <= (forceHits - hits) then hits = hits + 1
        elseif math.random() < (pack.insertChance or 0) then hits = hits + 1 end
    end
    hits = math.min(hits, count)
    local ok = true
    local ic = Config.Inserts
    if Config.Scale and Config.Scale.uniquePacks then
        -- every pack is its own slot: nothing on the item shows which ones hold a hit
        local order = {}
        caseHits = math.min(caseHits or 0, count)
        for i = 1, count do order[i] = { hit = i <= math.max(hits, caseHits) or nil, caseHit = i <= caseHits or nil } end
        for i = count, 2, -1 do local j = math.random(i) order[i], order[j] = order[j], order[i] end
        for i = 1, count do
            ok = Inventory.AddItem(src, name, 1, { rolled = true, hit = order[i].hit, caseHit = order[i].caseHit, seal = ('%06d'):format(math.random(0, 999999)) }) and ok
        end
        return ok
    end
    if (caseHits or 0) > 0 then
        caseHits = math.min(caseHits, count)
        ok = Inventory.AddItem(src, name, caseHits, { rolled = true, hit = true, caseHit = true, weight = (ic.packWeight or 20) + (ic.hitWeight or 3) }) and ok
        count = count - caseHits
        hits = math.max(0, math.min(hits - caseHits, count))
    end
    if count - hits > 0 then ok = Inventory.AddItem(src, name, count - hits, { rolled = true }) and ok end
    if hits > 0 then ok = Inventory.AddItem(src, name, hits, { rolled = true, hit = true, weight = (ic.packWeight or 20) + (ic.hitWeight or 3) }) and ok end
    return ok
end

-- Creates the metadata for a single physical card (reserves a print number)
function Cards.Mint(cardId, foil, parallelId, extra)
    local card = Config.Cards[cardId]
    if not card then return nil end
    extra = extra or {}
    local set = Config.Sets[card.set] or {}
    local rarity = Utils.RarityById[card.rarity]
    local print = DB.NextPrint(cardId)

    -- numbered parallel (falls back to a normal card if the run just ran out)
    local par = parallelId and Utils.ParallelById[parallelId]
    local parPrint
    if par then
        if DB.ParallelLeft(cardId, par) > 0 then
            parPrint = DB.NextPrint(DB.ParallelKey(cardId, par.id))
        else
            par = nil
        end
    end

    local serial = ('%s-%s-%04d%s%s'):format(set.code or 'XX', Utils.CardCode(card), print, foil and 'F' or '',
        par and ('-%s%02d'):format(par.id:sub(1, 1):upper(), parPrint) or '')

    local label = Utils.FullName(card)
    if par then
        label = par.maxPrints == 1 and ('%s (%s 1/1)'):format(label, par.label) or ('%s (%s %02d/%d)'):format(label, par.label, parPrint, par.maxPrints)
    end
    if foil then label = ('%s (%s)'):format(label, Config.Foil.label) end

    -- chase card numbering (e.g. Autograph 07/50)
    local ins = extra.insert and Utils.InsertById[extra.insert]
    local insPrint
    if ins then
        local key = cardId .. ':ins:' .. ins.id
        if DB.GetPrinted(key) < ins.maxPrints then
            insPrint = DB.NextPrint(key)
            label = ('%s (%s %02d/%d)'):format(label, ins.label, insPrint, ins.maxPrints)
            serial = serial .. '-' .. ins.id:upper():sub(1, 2) .. ('%02d'):format(insPrint)
        else
            ins = nil
        end
    end
    local err = extra.error and Utils.ErrorById[extra.error]
    if err then label = ('%s (Error: %s)'):format(label, err.label) end
    if Utils.Rookie[cardId] then label = label .. ' RC' end

    local printText = card.maxPrints and ('#%d/%d'):format(print, card.maxPrints) or ('#%d'):format(print)

    local meta = {
        cardId = cardId,
        serial = serial,
        print = print,
        foil = foil or nil,
        parallel = par and par.id or nil,
        parPrint = parPrint,
        -- display fields read by ox_inventory / qb-inventory tooltips
        label = label,
        description = ('%s | %s %s | %s | %s'):format((Config.Clubs[card.club] or {}).label or '', set.label or '', rarity and rarity.label or '', printText, serial),
        cond = (Config.Condition and Config.Condition.enabled) and Condition.Factory() or nil,
        insert = ins and ins.id or nil,
        insPrint = insPrint,
        error = err and err.id or nil,
        -- inventory picture: the player's photo (see server/images.lua)
        imageurl = CardImages and CardImages.Get(cardId) or nil,
    }
    if meta.cond then meta.description = Utils.CardDescription(meta) end
    return meta
end

function Cards.ItemFor(cardId)
    local card = Config.Cards[cardId]
    local rarity = card and Utils.RarityById[card.rarity]
    return rarity and rarity.item
end
