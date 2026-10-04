--[[ Loads cards and playmats made in the card creator / board creator (custom/*.json) and
     makes the Series 2 + seasonal helpers. Runs on both client and server before shared/utils.lua. ]]
local CC = Config.Custom or {}
local RES = GetCurrentResourceName()
Custom = { cards = {}, mats = {}, slabs = {}, errors = {} }

local function readJson(path)
    local raw = LoadResourceFile(RES, path)
    if not raw or raw == '' then return nil end
    local ok, data = pcall(json.decode, raw)
    if not ok or type(data) ~= 'table' then
        Custom.errors[#Custom.errors + 1] = ('%s is not valid JSON'):format(path)
        return nil
    end
    return data
end

local function list(data)
    if not data then return {} end
    if data.cards and type(data.cards) == 'table' then return data.cards end
    if data.mats and type(data.mats) == 'table' then return data.mats end
    if data[1] ~= nil or next(data) == nil then return data end
    local out = {}
    for id, v in pairs(data) do
        if type(v) == 'table' then v.id = v.id or id out[#out + 1] = v end
    end
    return out
end

local function imageUrl(img)
    if type(img) ~= 'string' or img == '' then return nil end
    if img:find('^https?://') or img:find('^img/') or img:find('^%.%./') then return img end
    return (CC.imagePrefix or '../custom/img/') .. img
end

local function clubFor(key, label)
    key = tostring(key or CC.defaultClub or 'unattached'):lower()
    if not Config.Clubs[key] then
        Config.Clubs[key] = { label = label or key, short = key:sub(1, 2):upper(), c1 = '#2a3042', c2 = '#e8ebf2', text = '#ffffff' }
    end
    return key
end

if CC.enabled ~= false then
    for _, file in ipairs(CC.cardFiles or {}) do
        for _, c in ipairs(list(readJson(file))) do
            local id = type(c) == 'table' and tostring(c.id or ''):lower():gsub('[^%w_]', '') or ''
            if id == '' then
                Custom.errors[#Custom.errors + 1] = ('%s: a card has no id'):format(file)
            elseif Config.Cards[id] then
                Custom.errors[#Custom.errors + 1] = ('%s: card id "%s" already exists, skipped'):format(file, id)
            else
                local typeId = tostring(c.type or CC.defaultType or 'player')
                Config.Cards[id] = {
                    set = tostring(c.set or CC.defaultSet or 'series2'),
                    number = tonumber(c.number) or 0,
                    code = c.code,
                    type = typeId,
                    first = tostring(c.first or ''), last = tostring(c.last or id),
                    club = clubFor(c.club, c.clubLabel),
                    nation = c.nation, pos = tostring(c.pos or 'MID'):upper(),
                    att = math.floor(tonumber(c.att) or 50), def = math.floor(tonumber(c.def) or 50),
                    kit = tonumber(c.kit), image = imageUrl(c.image),
                    weight = tonumber(c.weight) or 1,
                    maxPrints = tonumber(c.maxPrints),
                    value = tonumber(c.value),
                    seasonal = c.seasonal,
                    custom = true,
                }
                Custom.cards[#Custom.cards + 1] = id
            end
        end
    end
    for _, file in ipairs(CC.matFiles or {}) do
        for _, m in ipairs(list(readJson(file))) do
            local id = type(m) == 'table' and tostring(m.id or ''):lower():gsub('[^%w_]', '') or ''
            if id ~= '' then
                local dup = false
                for _, x in ipairs(Config.Mats.list) do if x.id == id then dup = true end end
                if not dup then
                    local mat = { id = id, label = tostring(m.label or id), image = imageUrl(m.image), bg = m.bg or '#101620', line = m.line or 'rgba(255,255,255,.25)', slot = m.slot or 'rgba(255,255,255,.35)', custom = true }
                    Config.Mats.list[#Config.Mats.list + 1] = mat
                    Custom.mats[#Custom.mats + 1] = id
                end
            end
        end
    end

    -- slab designs: { "server": {...}, "business": {...} }. Only those two slots exist, anything else is ignored.
    local function css(v, def)
        v = tostring(v or '')
        if v == '' or #v > 160 or v:find('[<>{};\\"\']') or v:lower():find('url%s*%(') or v:lower():find('expression') then return def end
        return v
    end
    for _, file in ipairs(CC.slabFiles or {}) do
        local data = readJson(file)
        if data then
            for _, slot in ipairs({ 'server', 'business' }) do
                local d = data[slot]
                if type(d) == 'table' and not Config.SlabDesigns[slot] then
                    Config.SlabDesigns[slot] = {
                        slot = slot,
                        name = tostring(d.name or d.brand or ''):sub(1, 24):upper(),
                        bg = css(d.bg, '#f2f3f6'), fg = css(d.fg, '#14171f'),
                        accent = css(d.accent, '#1a3d7c'), border = css(d.border, '#1a3d7c'),
                        case = css(d.case, nil),
                    }
                    Custom.slabs[#Custom.slabs + 1] = slot
                end
            end
            for k in pairs(data) do
                if k ~= 'server' and k ~= 'business' then Custom.errors[#Custom.errors + 1] = ('%s: "%s" ignored (only "server" and "business" slab designs are allowed)'):format(file, tostring(k)) end
            end
        end
    end
end


--[[ ---------------------------------------------------------------------------
    CREATOR LUA (Card Creator "Config.Cards" export, Playmat Creator "Config.PlayMats" export).
    Paste the creator output straight into custom/cards.lua and custom/playmats.lua.
    The files are run in a sandbox so they can't touch your real Config.Cards.
--------------------------------------------------------------------------- ]]
local function runCreator(path)
    local raw = LoadResourceFile(RES, path)
    if not raw or raw:gsub('%s', '') == '' then return nil end
    local env = { Config = { Cards = {}, PlayMats = {}, CardBacks = {}, Packs = {} }, math = math, string = string, table = table, pairs = pairs, ipairs = ipairs, tostring = tostring, tonumber = tonumber, type = type }
    local fn, err = load(raw, '@' .. path, 't', env)
    if not fn then Custom.errors[#Custom.errors + 1] = ('%s: %s'):format(path, tostring(err)) return nil end
    local ok, e = pcall(fn)
    if not ok then Custom.errors[#Custom.errors + 1] = ('%s: %s'):format(path, tostring(e)) return nil end
    return env.Config
end

local function titleCase(s) return (tostring(s):gsub('_', ' '):gsub('(%a)([%w]*)', function(a, b) return a:upper() .. b end)) end

if CC.enabled ~= false then
    local rmap = CC.creatorRarity or {}
    local maxStat = CC.creatorMaxStat or 99
    local scale = CC.creatorStatScale or 1.0
    local nextNumber = CC.creatorNumberBase or 7000
    local setMap = {}
    for _, file in ipairs(CC.creatorCardFiles or {}) do
        local conf = runCreator(file)
        local rows = {}
        for id, c in pairs(conf and conf.Cards or {}) do if type(c) == 'table' then rows[#rows + 1] = { id = tostring(id), c = c } end end
        table.sort(rows, function(a, b) return (tonumber(a.c.binderSlot) or 0) < (tonumber(b.c.binderSlot) or 0) or ((tonumber(a.c.binderSlot) or 0) == (tonumber(b.c.binderSlot) or 0) and a.id < b.id) end)
        for _, r in ipairs(rows) do
            local id, c = r.id:lower():gsub('[^%w_]', ''), r.c
            id = r.id:lower():gsub('[^%w_]', '')
            if c.playType == 'spell' or c.playType == 'trap' then
                Custom.errors[#Custom.errors + 1] = ('%s: "%s" is a %s card. Battles have no spells or traps, so it was skipped'):format(file, id, c.playType)
            elseif Config.Cards[id] then
                Custom.errors[#Custom.errors + 1] = ('%s: card id "%s" already exists, skipped'):format(file, id)
            elseif type(c.name) ~= 'string' or c.name == '' then
                Custom.errors[#Custom.errors + 1] = ('%s: "%s" has no name'):format(file, id)
            else
                local theme = (Config.Themes or {})[c.theme] and c.theme or 'football'
                local TH = (Config.Themes or {})[theme] or {}
                local first, last = c.name:match('^(%S+)%s+(.+)$')
                if not first then first, last = '', c.name end
                local st = type(c.stats) == 'table' and c.stats or {}
                local setId = tostring(CC.creatorSet or (CC.creatorSets or {})[theme] or c.set or CC.defaultSet or 'series2'):lower():gsub('[^%w_]', '')
                do local cs = tostring(c.set or ''):lower():gsub('[^%w_]', '') setMap[cs] = setMap[cs] or {} setMap[cs][setId] = (setMap[cs][setId] or 0) + 1 setMap['all'] = setMap['all'] or {} setMap['all'][setId] = (setMap['all'][setId] or 0) + 1 end
                if not Config.Sets[setId] then
                    Config.Sets[setId] = { label = titleCase(setId), code = setId:gsub('_', ''):sub(1, 3):upper(), hidden = true }
                end
                nextNumber = nextNumber + 1
                local col = type(c.colours) == 'table' and c.colours or nil
                -- filing: football = the club, creatures = the element, Los Santos = the district
                local clubKey, clubLabel, el, dist
                if theme == 'creatures' then
                    local key = tostring(c.element or 'stone'):lower():gsub('[^%w_]', '')
                    el = (TH.elements or {})[key]
                    clubKey, clubLabel = 'el_' .. key, (el and el.label) or titleCase(key)
                    if not Config.Clubs[clubKey] then
                        Config.Clubs[clubKey] = { label = clubLabel, short = clubLabel:sub(1, 2):upper(), c1 = el and el.c1 or '#555555', c2 = el and el.c2 or '#ffffff', text = '#ffffff' }
                    end
                elseif theme == 'lossantos' then
                    local key = tostring(c.district or 'vinewood'):lower():gsub('[^%w_]', '')
                    dist = (TH.districts or {})[key] or titleCase(key)
                    clubKey, clubLabel = 'ds_' .. key, dist
                    if not Config.Clubs[clubKey] then
                        Config.Clubs[clubKey] = { label = clubLabel, short = clubLabel:sub(1, 2):upper(), c1 = '#2a3042', c2 = '#e8ebf2', text = '#ffffff' }
                    end
                else
                    local want = tostring(c.club or ''):lower()
                    local found
                    for k, v in pairs(Config.Clubs) do if k == want or tostring(v.label or ''):lower() == want then found = k break end end
                    clubKey = found or clubFor((want:gsub('%s+', '_'):gsub('[^%w_]', '')), c.clubLabel or (c.club ~= '' and c.club or nil))
                end
                Config.Cards[id] = {
                    set = setId, number = nextNumber, type = rmap[c.rarity] or CC.defaultType or 'player',
                    first = first, last = last, club = clubKey, nation = c.nation or CC.creatorNation,
                    pos = theme == 'football' and tostring(c.pos or CC.creatorPos or 'CM'):upper() or '',
                    att = math.max(0, math.min(maxStat, math.floor((tonumber(c.attack or st.attack) or 50) * scale))),
                    def = math.max(0, math.min(maxStat, math.floor((tonumber(c.defense or st.defense) or 50) * scale))),
                    image = imageUrl(c.image), weight = 1,
                    finish = (c.finish and c.finish ~= 'none') and c.finish or nil, foilStrength = tonumber(c.foilStrength),
                    foilMask = imageUrl(c.foilMask), blurb = c.description,
                    colours = col and { c1 = col.border, c2 = col.plate } or nil,
                    theme = theme ~= 'football' and theme or nil,
                    element = c.element, stage = c.stage, hp = tonumber(c.hp), move = c.move,
                    category = c.category, district = dist or c.district,
                    custom = true,
                }
                Custom.cards[#Custom.cards + 1] = id
            end
        end
    end
    Config.CardBacks = Config.CardBacks or {}
    for _, file in ipairs(CC.creatorCardFiles or {}) do
        local conf = runCreator(file)
        for theme, b in pairs(conf and conf.CardBacks or {}) do
            if type(b) == 'table' and Config.Themes and Config.Themes[theme] then
                local o = { id = theme }
                for _, k in ipairs({ 'style', 'c1', 'c2', 'accent', 'emblem', 'title', 'sub', 'titleColour', 'subColour', 'dim', 'imageOnly', 'fit', 'position' }) do o[k] = b[k] end
                if b.image and b.image ~= '' then o.image = (b.image:match('^https?:') and b.image) or ((CC.imagePrefix or '../custom/img/') .. b.image) end
                Config.CardBacks[theme] = o
            end
        end

        for pid, pk in pairs(conf and conf.Packs or {}) do
            local id = tostring(pid):lower():gsub('[^%w_]', '')
            if type(pk) ~= 'table' or id == '' then
                Custom.errors[#Custom.errors + 1] = ('%s: pack "%s" is not valid'):format(file, tostring(pid))
            else
                local want = pk.set and tostring(pk.set):lower():gsub('[^%w_]', '') or 'all'
                local cand, best, bestN, kinds = setMap[want] or setMap.all or {}, nil, 0, 0
                for sid, n in pairs(cand) do kinds = kinds + 1 if n > bestN then best, bestN = sid, n end end
                if not best then
                    Custom.errors[#Custom.errors + 1] = ('%s: pack "%s" has no cards to draw from, skipped'):format(file, id)
                else
                    if kinds > 1 then Custom.errors[#Custom.errors + 1] = ('%s: pack "%s" covers cards from %d sets. A pack draws from one set, so it uses "%s". Make one pack per theme.'):format(file, id, kinds, best) end
                    local weights, any = {}, false
                    for rk, w in pairs(type(pk.rates) == 'table' and pk.rates or {}) do
                        local t = (CC.creatorRarity or {})[rk]
                        if t and tonumber(w) and tonumber(w) > 0 then weights[t] = tonumber(w) any = true end
                    end
                    if not any then weights = { player = 100 } end
                    local g
                    if type(pk.guaranteed) == 'table' and (CC.creatorRarity or {})[pk.guaranteed.minRarity] then
                        g = { count = 1, minRarity = CC.creatorRarity[pk.guaranteed.minRarity] }
                    end
                    Config.Packs[id] = {
                        label = tostring(pk.label or titleCase(id)), set = best, cards = math.max(1, math.min(15, tonumber(pk.cards) or 5)),
                        weights = weights, guaranteed = g, foilChance = CC.creatorPackFoil or 0.05, custom = true,
                    }
                    Custom.packs = (Custom.packs or 0) + 1
                end
            end
        end
    end
    for _, file in ipairs(CC.creatorMatFiles or {}) do
        local conf = runCreator(file)
        local pm = conf and conf.PlayMats or {}
        local themes = pm.Themes or {}
        local order = pm.Order or {}
        local seen = {}
        local ids = {}
        for _, id in ipairs(order) do if themes[id] then ids[#ids + 1] = id seen[id] = true end end
        local rest = {}
        for id in pairs(themes) do if not seen[id] then rest[#rest + 1] = id end end
        table.sort(rest)
        for _, id in ipairs(rest) do ids[#ids + 1] = id end
        for _, id in ipairs(ids) do
            local t = themes[id]
            local mid = tostring(id):lower():gsub('[^%w_]', '')
            local dup = false
            for _, x in ipairs(Config.Mats.list) do if x.id == mid then dup = true end end
            if dup then
                Custom.errors[#Custom.errors + 1] = ('%s: mat id "%s" already exists, skipped'):format(file, mid)
            else
                local st = type(t.style) == 'table' and t.style or {}
                local img = type(t.image) == 'string' and t.image ~= '' and ((t.image:find('^https?://') and t.image) or ((CC.matImagePrefix or 'img/playmats/') .. t.image)) or nil
                Config.Mats.list[#Config.Mats.list + 1] = {
                    id = mid, label = tostring(t.label or mid), description = t.description, image = img, imageFit = t.imageFit,
                    bg = st.surface or '#101620', line = st.stitch or 'rgba(255,255,255,.25)', slot = st.stitch or 'rgba(255,255,255,.35)',
                    style = st, custom = true,
                }
                Custom.mats[#Custom.mats + 1] = mid
            end
        end
    end
end

-- seasonal windows. A card with seasonal = 'x' is only in packs while Config.Seasonal.windows.x is open.
Seasonal = {}
function Seasonal.Active(card, now)
    local id = card and card.seasonal
    if not id then return true end
    local w = (Config.Seasonal.windows or {})[id]
    if not w then return false end
    now = now or os.time()
    return now >= (w.from or 0) and now <= (w.to or 2 ^ 40)
end
