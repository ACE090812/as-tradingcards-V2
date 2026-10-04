--[[ Card condition helpers (shared). Stored on each card as metadata.cond:
     seed          layout of the visible flaws (same picture everywhere)
     cen/cor/edg/sur  base scores (1-10) before damage
     dust, finger, dirt, stain, whiten   0-1 amounts
     scratch, ding  counts
     print, crease, water   0/1
     fade          0-1 sun fading (left in a car / on the ground)
     warp          0/1 bowed from damp
   metadata.prot = nil | 'sleeve' | 'toploader' ]]
Condition = {}

local WORDS = {
    [10] = 'Gem Mint', [9] = 'Mint', [8] = 'Near Mint-Mint', [7] = 'Near Mint', [6] = 'Excellent-Mint',
    [5] = 'Excellent', [4] = 'Very Good-Excellent', [3] = 'Very Good', [2] = 'Good', [1] = 'Poor',
}
Condition.Words = WORDS

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end
local function half(v) return math.floor(v * 2 + 0.5) / 2 end

-- random number biased towards the top of the range
local function biased(min, max, bias)
    return min + (max - min) * (1 - math.random() ^ bias)
end

function Condition.Factory()
    local f = Config.Condition.factory
    return {
        seed = math.random(1, 2147483646),
        cen = half(biased(f.centering.min, f.centering.max, f.centering.bias)),
        cor = half(9.0 + math.random() * 1.0),
        edg = half(9.0 + math.random() * 1.0),
        sur = half(9.5 + math.random() * 0.5),
        print = math.random() < f.printLineChance and 1 or 0,
        ding = math.random() < f.dingChance and 1 or 0,
        dust = 0, finger = 0, dirt = 0, stain = 0, whiten = 0, scratch = 0, crease = 0, water = 0,
    }
end

-- cards from before the condition update: near mint with a few small flaws.
-- Seeded from the serial so every server/restart agrees.
function Condition.Legacy(meta)
    local s = 0
    for i = 1, #(meta.serial or '') do s = (s * 31 + meta.serial:byte(i)) % 2147483646 end
    local function r() s = (s * 16807) % 2147483647 return s / 2147483647 end
    return {
        seed = s + 1,
        cen = half(7.5 + r() * 2.5), cor = half(8.5 + r() * 1.5), edg = half(8.5 + r() * 1.5), sur = half(9.0 + r() * 1.0),
        dust = r() < 0.6 and 0.3 or 0, finger = r() < 0.4 and 0.3 or 0, dirt = 0, stain = 0,
        whiten = r() < 0.3 and 0.15 or 0, scratch = r() < 0.2 and 1 or 0, ding = 0, print = 0, crease = 0, water = 0,
    }
end

-- adds cond to metadata if missing; returns true if it changed
function Condition.Ensure(meta)
    if type(meta) ~= 'table' or not meta.cardId or type(meta.cond) == 'table' then return false end
    meta.cond = Condition.Legacy(meta)
    return true
end

function Condition.Scores(c)
    c = c or {}
    local centering = clamp(c.cen or 9, 1, 10)
    local corners = clamp((c.cor or 9.5) - (c.ding or 0) * 1.5, 1, 10)
    local edges = clamp((c.edg or 9.5) - (c.whiten or 0) * 3 - (c.warp or 0) * 0.8, 1, 10)
    local surface = (c.sur or 9.5)
        - (c.dust or 0) * 0.8 - (c.finger or 0) * 0.8 - (c.dirt or 0) * 1.5 - (c.stain or 0) * 2.0
        - (c.scratch or 0) * 0.6 - (c.print or 0) * 0.5 - (c.crease or 0) * 4.0 - (c.water or 0) * 3.5
        - (c.fade or 0) * 4.0 - (c.warp or 0) * 1.2
    surface = clamp(surface, 1, 10)
    local s = { centering = half(centering), corners = half(corners), edges = half(edges), surface = half(surface) }
    local low = math.min(s.centering, s.corners, s.edges, s.surface)
    local avg = (s.centering + s.corners + s.edges + s.surface) / 4
    s.overall = clamp(math.floor(low * 0.6 + avg * 0.4 + 0.5), 1, 10)
    s.word = WORDS[s.overall]
    return s
end

-- the grade a grader gives: condition + a little human variation
function Condition.Grade(c)
    local s = Condition.Scores(c)
    local low = math.min(s.centering, s.corners, s.edges, s.surface)
    local avg = (s.centering + s.corners + s.edges + s.surface) / 4
    local g = low * 0.6 + avg * 0.4 + (math.random() - 0.5) * 0.8
    return clamp(math.floor(g + 0.5), 1, 10), s
end

-- what someone sees without a magnifier (only obvious damage counts)
function Condition.Glance(c)
    local s = Condition.Scores(c)
    if (c.crease or 0) > 0 or (c.water or 0) > 0 then return 'Damaged' end
    if (c.fade or 0) >= 0.4 then return 'Looks Sun Faded' end
    if s.overall >= 7 then return 'Looks Near Mint' end
    if s.overall >= 5 then return 'Looks Lightly Played' end
    if s.overall >= 3 then return 'Looks Played' end
    return 'Looks Damaged'
end

-- issue list for the UI; small = only visible with a magnifier
function Condition.Issues(c)
    local list = {}
    local function add(id, label, sev, fix, small) list[#list + 1] = { id = id, label = label, sev = sev, fix = fix, small = small } end
    c = c or {}
    if (c.dust or 0) > 0.05 then add('dust', 'Dust & lint', 'minor', 'Cloth', true) end
    if (c.finger or 0) > 0.05 then add('finger', 'Fingerprints', 'minor', 'Cloth', true) end
    if (c.dirt or 0) > 0.05 then add('dirt', 'Dirt smudge', 'minor', 'Spray', false) end
    if (c.stain or 0) > 0.05 then add('stain', 'Stain', 'major', 'Spray', false) end
    if (c.scratch or 0) > 0 then add('scratch', (c.scratch > 1 and '%d surface scratches' or 'Surface scratch'):format(c.scratch), 'minor', nil, true) end
    if (c.print or 0) > 0 then add('print', 'Print line', 'minor', nil, true) end
    if (c.whiten or 0) > 0.05 then add('edges', 'Edge whitening', 'minor', nil, true) end
    if (c.ding or 0) > 0 then add('corner', (c.ding > 1 and '%d dinged corners' or 'Dinged corner'):format(c.ding), 'major', nil, false) end
    if (c.crease or 0) > 0 then add('crease', 'Crease', 'major', nil, false) end
    if (c.water or 0) > 0 then add('water', 'Water damage', 'major', nil, false) end
    if (c.fade or 0) > 0.05 then add('fade', (c.fade >= 0.4 and 'Badly sun faded' or 'Sun fading'), c.fade >= 0.25 and 'major' or 'minor', nil, c.fade < 0.15) end
    if (c.warp or 0) > 0 then add('warp', 'Warped (damp)', 'major', nil, false) end
    if (c.cen or 10) < 8 then add('centering', 'Off-centre print', 'minor', nil, true) end
    return list
end

-- sell value multiplier for a raw (ungraded) card
function Condition.ValueMultiplier(c)
    local s = Condition.Scores(c)
    return math.max(0.15, (s.overall / 9) ^ 1.6)
end

function Condition.ProtLabel(prot)
    return prot == 'toploader' and 'Toploader' or prot == 'sleeve' and 'Sleeved' or nil
end
