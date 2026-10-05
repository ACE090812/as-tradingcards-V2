Utils = {}

-- card type lookups ("rarity" internally = card type, ordered common -> rare)
Utils.RarityIndex = {}
Utils.RarityById = {}
Utils.CardItems = {}      -- [itemName] = typeId
for i, t in ipairs(Config.Types) do
    Utils.RarityIndex[t.id] = i
    Utils.RarityById[t.id] = t
    Utils.CardItems[t.item] = t.id
end

-- parallel lookups
Utils.ParallelById, Utils.ParallelIndex = {}, {}
for i, par in ipairs(Config.Parallels or {}) do
    Utils.ParallelById[par.id] = par
    Utils.ParallelIndex[par.id] = i
end

-- chase cards / errors / rookies
Utils.InsertById, Utils.ErrorById, Utils.Rookie = {}, {}, {}
for _, t in ipairs((Config.Inserts or {}).types or {}) do Utils.InsertById[t.id] = t end
for _, e in ipairs((Config.Errors or {}).kinds or {}) do Utils.ErrorById[e.id] = e end
for _, id in ipairs(Config.Rookies or {}) do Utils.Rookie[id] = true end

-- sealed products (packs, boxes, tins) and their shop price
Utils.Sealed = {}
for name in pairs(Config.Packs) do Utils.Sealed[name] = true end
for name in pairs(Config.Boxes or {}) do Utils.Sealed[name] = true end
if Config.BoosterBox and Config.BoosterBox.item then Utils.Sealed[Config.BoosterBox.item] = true end
function Utils.ShopPrice(name)
    for _, e in ipairs(Config.Shop.items) do if e.item == name then return e.price end end
    for _, e in ipairs((Config.Series2 or {}).shop or {}) do if e.item == name then return e.price end end
end
-- current sealed value: grows the longer the set has been out
function Utils.SealedValue(name)
    local base = Utils.ShopPrice(name)
    if not base then
        local pack = Config.Packs[name]
        base = pack and pack.cards * 2 or 0
    end
    local sc = Config.Sealed or {}
    local pack = Config.Packs[name]
    local released = (sc.released or {})[pack and pack.set or ''] or os.time()
    local weeks = math.max(0, (os.time() - released) / 604800)
    local mult = math.min(sc.maxMultiplier or 3, 1 + weeks * (sc.growthPerWeek or 0))
    return math.floor(base * mult + 0.5)
end

-- how good a physical card is (used to decide which version the binder keeps)
function Utils.VersionScore(meta)
    meta = meta or {}
    local score = 0
    if meta.parallel and Utils.ParallelIndex[meta.parallel] then score = score + Utils.ParallelIndex[meta.parallel] * 10 end
    if meta.foil then score = score + 1 end
    if meta.grade then score = score + meta.grade * 0.01 end
    if meta.insert then score = score + 100 end
    return score
end

-- validate card config once
for id, card in pairs(Config.Cards) do
    card.id = id
    card.rarity = card.type
    card.weight = card.weight or 1
    if not Utils.RarityById[card.type] then
        print(('^1[as-tradingcards] card "%s" has unknown type "%s"^0'):format(id, tostring(card.type)))
    end
    if not Config.Sets[card.set] then
        print(('^1[as-tradingcards] card "%s" has unknown set "%s"^0'):format(id, tostring(card.set)))
    end
    if not Config.Clubs[card.club] then
        print(('^1[as-tradingcards] card "%s" has unknown club "%s"^0'):format(id, tostring(card.club)))
    end
end

function L(key, ...)
    local str = Config.Locale[key] or key
    if select('#', ...) > 0 then return str:format(...) end
    return str
end

function Utils.IsCardItem(name)
    return Utils.CardItems[name] ~= nil
end

function Utils.IsCollectible(name)
    return Utils.CardItems[name] ~= nil or name == Config.Items.slab
end

-- weights: { key = weight }
function Utils.WeightedPick(weights)
    local total = 0
    for _, w in pairs(weights) do total = total + w end
    if total <= 0 then return nil end
    local roll = math.random() * total
    local acc = 0
    local last
    for k, w in pairs(weights) do
        acc = acc + w
        last = k
        if roll <= acc then return k end
    end
    return last
end

function Utils.FormatTime(seconds)
    seconds = math.max(0, math.floor(seconds))
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60
    if h > 0 then return ('%dh %dm'):format(h, m) end
    if m > 0 then return ('%dm %ds'):format(m, s) end
    return ('%ds'):format(s)
end

function Utils.CardCode(card)
    if not card then return '' end
    return card.code or ('%03d'):format(card.number or 0)
end

function Utils.FullName(card)
    if not card then return 'Unknown' end
    if card.first and card.first ~= '' then return card.first .. ' ' .. card.last end
    return card.last or 'Unknown'
end

-- slab label skin for a graded card (Config.Skins.slabs, first match wins)
function Utils.SlabSkin(meta, card)
    for _, sk in ipairs((Config.Skins or {}).slabs or {}) do
        local w, ok = sk.when, false
        if w == 'pristine' then ok = meta.pristine == true
        elseif w == 'legend' then ok = card and card.type == 'legend'
        elseif w == 'chase' then ok = meta.insert ~= nil or meta.error ~= nil
        elseif w == 'parallel' then ok = meta.parallel ~= nil
        elseif w == 'grade10' then ok = meta.grade == 10
        elseif w == 'foil' then ok = meta.foil == true
        elseif w == 'rookie' then ok = card and Utils.Rookie[card.id] == true
        elseif w == 'grade' then ok = true end
        if ok then return { id = sk.id, label = sk.label, bg = sk.bg, fg = sk.fg } end
    end
end

-- Picture of the whole card (html/img/cards/<cardId>.png/.webp/.jpg), made by the website's Card Creator
-- ("Card images (.zip)"). When one exists the card is shown as that picture, so it looks the same as in the creator.
local faceCache = {}
function Utils.CardFace(cardId)
    if not cardId or Config.CardFaceImages == false then return nil end
    local hit = faceCache[cardId]
    if hit ~= nil then return hit or nil end
    for _, ext in ipairs({ 'png', 'webp', 'jpg' }) do
        if LoadResourceFile(GetCurrentResourceName(), ('html/img/cards/%s.%s'):format(cardId, ext)) then
            faceCache[cardId] = ('img/cards/%s.%s'):format(cardId, ext)
            return faceCache[cardId]
        end
    end
    faceCache[cardId] = false
    return nil
end

-- the matching foil map (html/img/cards/<cardId>_foil.png, also made by the Card Creator) lets the game draw the same finish as the website
local foilCache = {}
function Utils.CardFoilMap(cardId)
    if not cardId or Config.CardFaceImages == false then return nil end
    local hit = foilCache[cardId]
    if hit ~= nil then return hit or nil end
    if LoadResourceFile(GetCurrentResourceName(), ('html/img/cards/%s_foil.png'):format(cardId)) then
        foilCache[cardId] = ('img/cards/%s_foil.png'):format(cardId)
        return foilCache[cardId]
    end
    foilCache[cardId] = false
    local card = Config.Cards[cardId]
    if card and card.finish and IsDuplicityVersion() and Utils.CardFace(cardId) then
        print(('^3[as-tradingcards] card "%s" has a foil finish ("%s") but html/img/cards/%s_foil.png is missing, so the game uses a simpler glow. Download everything from the Card Creator again and copy html/img/cards/ across.^0'):format(cardId, card.finish, cardId))
    end
    return nil
end

--[[ Builds the table the NUI renders from card metadata ]]
function Utils.BuildDisplay(meta, itemName)
    meta = meta or {}
    local card = meta.cardId and Config.Cards[meta.cardId]
    local typeId = (card and card.type) or meta.rank or Utils.CardItems[itemName] or Config.Types[1].id
    local t = Utils.RarityById[typeId] or Config.Types[1]
    local set = card and Config.Sets[card.set]
    local club = card and Config.Clubs[card.club] or { label = '', short = '?', c1 = '#333333', c2 = '#ffffff', text = '#ffffff' }
    if card and card.colours and card.colours.c1 and card.colours.c2 then club = setmetatable({ c1 = card.colours.c1, c2 = card.colours.c2 }, { __index = club }) end

    local display = {
        id = card and card.id,
        first = card and card.first or '',
        last = card and card.last or (meta.label or 'Unknown'),
        label = card and Utils.FullName(card) or (meta.label or 'Unknown Card'),
        pos = card and card.pos or '',
        att = card and card.att or 0,
        def = card and card.def or 0,
        nation = card and card.nation,
        kit = card and card.kit,
        look = card and card.look,
        image = card and card.image,
        face = card and Utils.CardFace(card.id),
        foilMap = card and Utils.CardFoilMap(card.id),
        code = Utils.CardCode(card),
        club = { key = card and card.club, label = club.label, short = club.short, c1 = club.c1, c2 = club.c2, text = club.text, badge = club.badge },
        setLabel = set and set.label,
        setCode = set and set.code,
        rarity = {
            id = t.id, label = t.label, frame = t.frame, plate = t.plate, plateText = t.plateText,
            posBg = t.posBg, effects = t.effects or {}, glow = t.glow,
        },
        foil = meta.foil == true or (card and card.finish ~= nil) or false,
        finish = card and card.finish, foilStrength = card and card.foilStrength, blurb = card and card.blurb,
        theme = card and card.theme, element = card and card.element, stage = card and card.stage, hp = card and card.hp, move = card and card.move,
        category = card and card.category, district = card and card.district,
        statLabels = card and card.theme and ((Config.Themes or {})[card.theme] or {}).stats or nil,
        serial = meta.serial,
        print = meta.print,
        maxPrints = card and card.maxPrints,
        footer = Config.CardFooter,
    }

    display.rookie = card and Utils.Rookie[card.id] or nil
    local ins = meta.insert and Utils.InsertById[meta.insert]
    if ins then display.insert = { id = ins.id, label = ins.label, print = meta.insPrint, max = ins.maxPrints, caseHit = ins.caseHit or nil } end
    local err = meta.error and Utils.ErrorById[meta.error]
    if err then display.error = { id = err.id, label = err.label } end

    local par = meta.parallel and Utils.ParallelById[meta.parallel]
    if par then
        display.parallel = {
            id = par.id, label = par.label, frame = par.frame, stamp = par.stamp,
            effects = par.effects or {}, print = meta.parPrint, max = par.maxPrints,
        }
    end

    if type(meta.cond) == 'table' and not meta.grade then
        local sc = Condition.Scores(meta.cond)
        display.cond = {
            c = meta.cond, scores = sc, glance = Condition.Glance(meta.cond),
            issues = Condition.Issues(meta.cond), prot = meta.prot,
        }
    end

    if meta.grade then
        local design = (Config.SlabDesigns or {})[meta.slabBy or 'server']
        display.graded = {
            grade = meta.grade,
            label = (meta.pristine and Config.Pristine and Config.Pristine.label) or Config.Grading.labels[meta.grade] or '',
            pristine = meta.pristine or nil,
            cert = meta.cert,
            brand = (design and design.name ~= '' and design.name) or Config.GradingBrand,
            design = design,
            sub = meta.sub,
            skin = Utils.SlabSkin(meta, card),
        }
        if type(meta.cond) == 'table' then display.cond = { c = meta.cond } end
    end

    return display
end

-- Short name used in menus / notifications
function Utils.CardTitle(meta, itemName)
    local d = Utils.BuildDisplay(meta, itemName)
    local parts = { d.label }
    if d.parallel then
        parts[#parts + 1] = d.parallel.max == 1 and ('[%s 1/1]'):format(d.parallel.label)
            or ('[%s %02d/%d]'):format(d.parallel.label, d.parallel.print or 0, d.parallel.max)
    end
    if d.foil then parts[#parts + 1] = ('(%s)'):format(Config.Foil.label) end
    if d.insert then parts[#parts + 1] = ('[%s %02d/%d]'):format(d.insert.label, d.insert.print or 0, d.insert.max) end
    if d.error then parts[#parts + 1] = ('[Error: %s]'):format(d.error.label) end
    if d.rookie then parts[#parts + 1] = 'RC' end
    if d.graded then parts[#parts + 1] = d.graded.pristine and ('[Pristine %d]'):format(d.graded.grade) or ('[%d]'):format(d.graded.grade) end
    if d.print then
        parts[#parts + 1] = d.maxPrints and ('#%d/%d'):format(d.print, d.maxPrints) or ('#%d'):format(d.print)
    end
    return table.concat(parts, ' ')
end

function Utils.CardValue(meta, itemName)
    local d = Utils.BuildDisplay(meta, itemName)
    local card = d.id and Config.Cards[d.id]
    local t = Utils.RarityById[d.rarity.id]
    local value = (card and card.value) or (t and t.value) or 0

    -- every bonus the card has (foil, parallel, hit, error, rookie, grade, low print number)
    local bonus = {}
    local function add(m) m = tonumber(m) or 1 if m > 1 then bonus[#bonus + 1] = m elseif m < 1 then value = value * m end end
    if d.foil then add(Config.Foil.valueMultiplier) end
    local par = d.parallel and Utils.ParallelById[d.parallel.id]
    if par then add(par.value) end
    local ins = d.insert and Utils.InsertById[d.insert.id]
    if ins then add(ins.value) end
    local err = d.error and Utils.ErrorById[d.error.id]
    if err then add(err.value) end
    if d.rookie then add(Config.RookieValue) end
    if d.graded then
        add(Config.Grading.multipliers[d.graded.grade] or 1.0)
        if d.graded.pristine and Config.Pristine then add(Config.Pristine.valueMultiplier or 1) end
    elseif type(meta and meta.cond) == 'table' then
        value = value * Condition.ValueMultiplier(meta.cond)   -- wear only ever lowers the price
    end
    local lpb = Config.Buyer.lowPrintBonus
    if lpb and d.maxPrints and d.print and d.print <= lpb.upTo then add(lpb.multiplier) end

    -- bonuses don't simply multiply together (a foil Black 1/1 graded 10 would be worth millions).
    -- The biggest counts in full, the next at half strength, the next at a quarter, and so on.
    local pc = Config.Pricing or {}
    local damping = pc.stackDamping or 0.5
    table.sort(bonus, function(a, b) return a > b end)
    local strength = 1
    for _, m in ipairs(bonus) do
        value = value * (m ^ strength)
        strength = strength * damping
    end

    -- market prices (server only: server/market.lua defines MarketFactor)
    if MarketFactor and d.id and not (Config.Market and Config.Market.shopUsesMarket == false and not Utils.ForceMarket) then
        value = value * MarketFactor(d.id)
    end

    if pc.cap and tonumber(pc.maxValue) and value > pc.maxValue then value = pc.maxValue end

    return math.max(value > 0 and 1 or 0, math.floor(value))
end

-- £1,234,567
function Utils.Money(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
    if out:sub(1, 1) == ',' then out = out:sub(2) end
    return '£' .. out
end

-- inventory tooltip text for a raw card (club | set type | print | condition | serial)
function Utils.CardDescription(meta, itemName)
    local card = meta.cardId and Config.Cards[meta.cardId]
    if not card then return meta.description end
    local set = Config.Sets[card.set] or {}
    local rarity = Utils.RarityById[card.rarity]
    local printText = card.maxPrints and ('#%d/%d'):format(meta.print or 0, card.maxPrints) or ('#%d'):format(meta.print or 0)
    local parts = { (Config.Clubs[card.club] or {}).label or '', ('%s %s'):format(set.label or '', rarity and rarity.label or ''), printText }
    if type(meta.cond) == 'table' then
        local cond = Condition.Glance(meta.cond)
        local prot = Condition.ProtLabel(meta.prot)
        parts[#parts + 1] = prot and (cond .. ' · ' .. prot) or cond
    end
    parts[#parts + 1] = meta.serial or ''
    return table.concat(parts, ' | ')
end
