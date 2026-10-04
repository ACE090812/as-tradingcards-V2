--[[ BATTLE: placeable tables, lobbies, the match engine, ranks / seasons / leaderboard, tournaments ]]
local B = Config.Battle or {}
if not B.enabled then return end
local TB = B.table or {}
local BET = B.bets or {}

local function money(n) return Utils.Money(n) end
local function name(src) return Framework.GetName(src) or GetPlayerName(src) or ('Player ' .. tostring(src)) end
local function dist(a, b)
    local pa, pb = GetPlayerPed(a), GetPlayerPed(b)
    if pa == 0 or pb == 0 then return 9999 end
    return #(GetEntityCoords(pa) - GetEntityCoords(pb))
end
local function distTo(src, v)
    local p = GetPlayerPed(src)
    if p == 0 then return 9999 end
    return #(GetEntityCoords(p) - v)
end
local function online(src) return src and GetPlayerName(src) ~= nil end
local function notify(src, msg, t) if online(src) then Framework.Notify(src, msg, t or 'inform') end end

if MoneyLog and MoneyLog.Labels then
    MoneyLog.Labels.battle = 'Battle wager'
    MoneyLog.Labels.cardshop = 'Player card shop'
    MoneyLog.Labels.trader = 'Card trader'
    MoneyLog.Labels.wants = 'Collector desk'
    MoneyLog.Labels.gift = 'Card gift'
end

Battle = { games = {}, inGame = {}, tables = {}, lobbies = {} }
local games, inGame, tables, lobbies = Battle.games, Battle.inGame, Battle.tables, Battle.lobbies
local nextGame = 0

--[[ ---------------------------------------------------------------------------
    RANKS
--------------------------------------------------------------------------- ]]
Rank = {}
function Rank.Get(identifier, season)
    season = season or Season.Number()
    local r = MySQL.single.await('SELECT points, wins, losses, draws FROM ascard_rank WHERE season = ? AND identifier = ?', { season, identifier })
    r = r or { points = 0, wins = 0, losses = 0, draws = 0 }
    r.tier = Season.Tier(r.points)
    return r
end

function Rank.Add(identifier, displayName, delta, result)
    local season = Season.Number()
    local cur = Rank.Get(identifier, season)
    local pts = math.max(0, cur.points + delta)
    MySQL.query.await([[INSERT INTO ascard_rank (season, identifier, name, points, wins, losses, draws, updated) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE name = VALUES(name), points = VALUES(points), wins = wins + VALUES(wins), losses = losses + VALUES(losses), draws = draws + VALUES(draws), updated = VALUES(updated)]],
        { season, identifier, tostring(displayName):sub(1, 80), pts, result == 'win' and 1 or 0, result == 'lose' and 1 or 0, result == 'draw' and 1 or 0, os.time() })
    return cur.points, pts
end

function Rank.Board()
    local season = Season.Number()
    local rows = MySQL.query.await('SELECT identifier, name, points, wins, losses FROM ascard_rank WHERE season = ? AND (wins + losses + draws) > 0 ORDER BY points DESC, wins DESC LIMIT ?',
        { season, (Config.Season or {}).leaderboardSize or 25 }) or {}
    for i, r in ipairs(rows) do r.pos = i r.tier = Season.Tier(r.points).name end
    return rows
end

--[[ ---------------------------------------------------------------------------
    TABLES (placeable battle table item)
--------------------------------------------------------------------------- ]]
local function tableList()
    local out = {}
    for id, t in pairs(tables) do
        out[#out + 1] = { id = id, x = t.x, y = t.y, z = t.z, h = t.h, owner = t.owner_name, state = t.state or 'free' }
    end
    return out
end
local function pushTables(target) TriggerClientEvent('as-tradingcards:client:tables', target or -1, tableList()) end

CreateThread(function()
    V2.Wait()
    for _, r in ipairs(MySQL.query.await('SELECT * FROM ascard_tables') or {}) do
        tables[r.id] = { id = r.id, owner = r.owner, owner_name = r.owner_name, x = r.x, y = r.y, z = r.z, h = r.h, state = 'free' }
    end
    pushTables()
end)

lib.callback.register('as-tradingcards:server:getTables', function() return tableList() end)

function Battle.UseTableItem(src) TriggerClientEvent('as-tradingcards:client:placeTable', src) end

lib.callback.register('as-tradingcards:server:placeTable', function(src, x, y, z, h)
    x, y, z, h = tonumber(x), tonumber(y), tonumber(z), tonumber(h)
    if not (x and y and z and h) then return nil, 'Bad position.' end
    if distTo(src, vec3(x, y, z)) > 6.0 then return nil, 'Too far away to put it down there.' end
    local identifier = Framework.GetIdentifier(src)
    if not identifier then return nil end
    local count, mine = 0, 0
    for _, t in pairs(tables) do count = count + 1 if t.owner == identifier then mine = mine + 1 end end
    if mine >= (TB.maxPerPlayer or 1) then return nil, ('You can only have %d table%s out.'):format(TB.maxPerPlayer or 1, (TB.maxPerPlayer or 1) == 1 and '' or 's') end
    if count >= (TB.maxTotal or 30) then return nil, 'Too many tables are out already.' end
    for _, t in pairs(tables) do
        if #(vec3(t.x, t.y, t.z) - vec3(x, y, z)) < 1.6 then return nil, 'Too close to another table.' end
    end
    if not Inventory.RemoveItem(src, TB.item or 'ascard_table', 1) then return nil, 'You don’t have a battle table.' end
    local id = MySQL.insert.await('INSERT INTO ascard_tables (owner, owner_name, x, y, z, h, placed_at) VALUES (?, ?, ?, ?, ?, ?, ?)', { identifier, name(src), x, y, z, h, os.time() })
    if not id then Inventory.AddItem(src, TB.item or 'ascard_table', 1) return nil, 'Could not place it.' end
    tables[id] = { id = id, owner = identifier, owner_name = name(src), x = x, y = y, z = z, h = h, state = 'free' }
    pushTables()
    return true
end)

lib.callback.register('as-tradingcards:server:pickupTable', function(src, id)
    local t = tables[tonumber(id)]
    if not t then return nil, 'That table is gone.' end
    local identifier = Framework.GetIdentifier(src)
    local allowed = Framework.IsAdmin(src) or TB.pickupBy == 'anyone' or t.owner == identifier
    if not allowed then return nil, 'It isn’t your table.' end
    if distTo(src, vec3(t.x, t.y, t.z)) > (TB.range or 3.0) + 2 then return nil, 'Get closer.' end
    if t.state ~= 'free' and not Framework.IsAdmin(src) then return nil, 'There’s a game at this table.' end
    if not Inventory.CanCarry(src, TB.item or 'ascard_table', 1) then return nil, 'No room in your pockets.' end
    -- cancel anything waiting
    if lobbies[t.id] then lobbies[t.id] = nil end
    local g = t.game and games[t.game]
    if g then Battle.Finish(g, nil, 'table') end
    MySQL.update.await('DELETE FROM ascard_tables WHERE id = ?', { t.id })
    tables[t.id] = nil
    Inventory.AddItem(src, TB.item or 'ascard_table', 1)
    pushTables()
    return true
end)

--[[ ---------------------------------------------------------------------------
    CARD STATS AND DECKS
--------------------------------------------------------------------------- ]]
local function boostOf(m)
    local bs, b = B.boosts or {}, 0
    if m.parallel then b = b + ((bs.parallel or {})[m.parallel] or 0) end
    if m.foil then b = b + (bs.foil or 0) end
    if m.insert then b = b + (bs.insert or 0) end
    return b
end

-- one deck row -> a playable card (stats are worked out here, on the server)
local function prep(row)
    local card = Config.Cards[row.cardId] or {}
    local pos = (B.positions or {})[card.pos or ''] or { att = 0, def = 0 }
    local boost = boostOf(row.meta)
    local cap = B.maxStat or 120
    local noStats = row.meta.error == 'noStats'
    local base_att, base_def = noStats and 0 or (card.att or 0), noStats and 0 or (card.def or 0)
    return {
        display = Utils.BuildDisplay(row.meta, row.item),
        att = noStats and 0 or math.min(cap, base_att + boost + (pos.att or 0)),
        def = noStats and 0 or math.min(cap, base_def + boost + (pos.def or 0)),
        boost = boost, posAtt = pos.att or 0, posDef = pos.def or 0, pos = card.pos,
    }
end
Battle.PrepCard = prep

local function shuffle(t) for i = #t, 2, -1 do local j = math.random(i) t[i], t[j] = t[j], t[i] end return t end

local function loadDeck(src, deckId)
    local found
    for _, item in ipairs(Inventory.GetItems(src, function(n) return n == Decks.Item end)) do
        if item.metadata.deckId == deckId then found = item break end
    end
    if not found then return nil, 'That deck box isn’t on you.' end
    local rows = Decks.Rows(deckId)
    local ok, why = Decks.Validate(rows)
    if not ok then return nil, ('Your deck box %s.'):format(why) end
    for _, r in ipairs(rows) do if DB.IsStolen(r.serial) then return nil, 'A card in that box is reported stolen.' end end
    return rows
end

--[[ ---------------------------------------------------------------------------
    MATS
--------------------------------------------------------------------------- ]]
local function matById(id)
    for _, m in ipairs(Config.Mats.list) do if m.id == id then return m end end
    return Config.Mats.list[1]
end
local function matFor(src)
    local identifier = Framework.GetIdentifier(src)
    if identifier then
        local row = MySQL.single.await('SELECT mat FROM ascard_prefs WHERE identifier = ?', { identifier })
        if row and row.mat then
            local m = matById(row.mat)
            return m
        end
    end
    return matById(Config.Mats.default)
end
Battle.MatFor = matFor

--[[ ---------------------------------------------------------------------------
    GAME ENGINE
--------------------------------------------------------------------------- ]]
local function other(g, src) return g.p[1] == src and g.p[2] or g.p[1] end

local function take(src, amount)
    if amount <= 0 then return true end
    local acc = BET.account or 'cash'
    if (Framework.GetMoney(src, acc) or 0) < amount then return false end
    return Framework.RemoveMoney(src, acc, amount, 'ascard-battle')
end
local function give(src, amount)
    if amount > 0 and online(src) then Framework.AddMoney(src, BET.account or 'cash', amount, 'ascard-battle') end
end

local function draw(g, s)
    local h, pile = g.hand[s], g.pile[s]
    while #h < (B.handSize or 5) and #pile > 0 do h[#h + 1] = table.remove(pile) end
end

local function cardOut(c) return { uid = c.uid, display = c.display, att = c.att, def = c.def, boost = c.boost, posAtt = c.posAtt, posDef = c.posDef, pos = c.pos } end

local function sendTo(g, s, ev, fn)
    -- players get personal data; spectators get player 1's view
    TriggerClientEvent(ev, s, fn(s))
end

local function everyone(g, ev, fn)
    for _, s in ipairs(g.p) do if online(s) then TriggerClientEvent(ev, s, fn(s, false)) end end
    for s in pairs(g.spec) do
        if online(s) then TriggerClientEvent(ev, s, fn(g.p[1], true)) else g.spec[s] = nil end
    end
end

local function lives(g, s) return { me = g.life[s], opp = g.life[other(g, s)] } end

local function turnData(g, s, watch)
    local o = other(g, s)
    local hand = {}
    for i, c in ipairs(g.hand[s]) do hand[i] = cardOut(c) end
    return {
        turn = g.turn, role = g.attacker == s and 'attack' or 'defend', hand = hand, watch = watch or nil,
        life = lives(g, s), deck = { me = #g.pile[s], opp = #g.pile[o] }, handCount = { me = #g.hand[s], opp = #g.hand[o] },
        deadline = g.deadline and math.max(0, g.deadline - os.time()) or 0, matchLeft = math.max(0, g.endsAt - os.time()),
        field = { mine = g.field[s], theirs = g.field[o] }, log = g.log, picked = g.picks[s] ~= nil, oppPicked = g.picks[o] ~= nil,
        attackerName = g.names[g.attacker], names = { me = g.names[s], opp = g.names[o] },
    }
end

local function sendTurn(g)
    g.state = 'pick'
    g.picks = {}
    g.turn = g.turn + 1
    g.deadline = os.time() + (B.turnSeconds or 20)
    for _, s in ipairs(g.p) do draw(g, s) end
    everyone(g, 'as-tradingcards:client:btTurn', function(s, watch) return turnData(g, s, watch) end)
end

local function pushLog(g, text)
    g.log[#g.log + 1] = text
    while #g.log > 6 do table.remove(g.log, 1) end
end

local function pay(g, winner, why)
    local a, b = g.p[1], g.p[2]
    if g.pot > 0 then
        if winner then
            give(winner, g.pot)
            if MoneyLog then MoneyLog.Add(winner, 'battle', g.pot - g.bet, ('Beat %s (pot %s)'):format(g.names[other(g, winner)] or '?', money(g.pot))) end
            local loser = other(g, winner)
            if MoneyLog and online(loser) then MoneyLog.Add(loser, 'battle', -g.bet, ('Lost to %s'):format(g.names[winner] or '?')) end
        else
            give(a, g.bet) give(b, g.bet)
        end
    end
end

local function rankResult(g, winner, why)
    local out = {}
    local a, b = g.p[1], g.p[2]
    local ra, rb = g.ids[a], g.ids[b]
    local S = Config.Season or {}
    local ranked = not g.noRank
    if ranked then
        local since = os.time() - 86400
        local n = MySQL.scalar.await('SELECT COUNT(*) FROM ascard_matches WHERE `at` > ? AND ((p1 = ? AND p2 = ?) OR (p1 = ? AND p2 = ?))', { since, ra, rb, rb, ra }) or 0
        if n >= (B.rankedPairLimit or 3) then ranked = false end
    end
    for _, s in ipairs(g.p) do
        local id = g.ids[s]
        local res = not winner and 'draw' or (winner == s and 'win' or 'lose')
        local delta = 0
        if ranked then
            if res == 'win' then delta = why == 'forfeit' and (S.forfeitWinPoints or 15) or (S.winPoints or 25)
            elseif res == 'lose' then delta = -(S.lossPoints or 8)
            else delta = S.drawPoints or 0 end
            if g.tourney and res == 'win' then delta = delta + (Config.Tournament.roundPoints or 0) end
        end
        local before, after = Rank.Add(id, g.names[s], delta, res)
        out[s] = { before = before, after = after, delta = after - before, tier = Season.Tier(after), ranked = ranked, season = Season.Number() }
    end
    MySQL.insert('INSERT INTO ascard_matches (season, `at`, p1, p2, n1, n2, winner, wager, life1, life2, why) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        { Season.Number(), os.time(), ra, rb, g.names[a], g.names[b], winner and g.ids[winner] or nil, g.bet, g.life[a], g.life[b], why })
    return out
end

function Battle.Finish(g, forfeitBy, why)
    if g.state == 'over' then return end
    g.state = 'over'
    local a, b = g.p[1], g.p[2]
    local winner
    if forfeitBy then winner, why = other(g, forfeitBy), why or 'forfeit'
    elseif g.life[a] <= 0 and g.life[b] <= 0 then winner = nil
    elseif g.life[a] <= 0 then winner = b
    elseif g.life[b] <= 0 then winner = a
    elseif g.life[a] > g.life[b] then winner = a
    elseif g.life[b] > g.life[a] then winner = b end
    why = why or ((g.life[a] <= 0 or g.life[b] <= 0) and 'ko' or 'time')
    if why == 'table' then winner = nil end   -- table picked up: everyone gets their wager back, no ranking
    pay(g, winner, why)
    local ranks = why == 'table' and {} or rankResult(g, winner, why)
    for _, s in ipairs(g.p) do
        inGame[s] = nil
        local o = other(g, s)
        if online(s) then
            TriggerClientEvent('as-tradingcards:client:btEnd', s, {
                outcome = not winner and 'draw' or (winner == s and 'win' or 'lose'), why = why, life = lives(g, s), pot = g.pot, bet = g.bet,
                opponent = g.names[o], rank = ranks[s], forfeit = (forfeitBy and forfeitBy ~= s) or nil,
            })
        end
    end
    for s in pairs(g.spec) do
        if online(s) then TriggerClientEvent('as-tradingcards:client:btEnd', s, { watch = true, outcome = winner and 'win' or 'draw', winnerName = winner and g.names[winner] or nil, why = why, life = lives(g, g.p[1]) }) end
    end
    if g.tableId and tables[g.tableId] then tables[g.tableId].state, tables[g.tableId].game = 'free', nil pushTables() end
    if g.tourney and Tourney and Tourney.Report then Tourney.Report(g, winner, why) end
    games[g.id] = nil
end

local function checkEnd(g)
    local a, b = g.p[1], g.p[2]
    if g.life[a] <= 0 or g.life[b] <= 0 then return true end
    if #g.hand[a] == 0 and #g.hand[b] == 0 then return true end
    return false
end

local function resolve(g)
    if g.state ~= 'pick' then return end
    g.state = 'reveal'
    local atk = g.attacker
    local def = other(g, atk)
    local ca = g.picks[atk] or g.hand[atk][math.random(#g.hand[atk])]
    local cd = g.picks[def] or g.hand[def][math.random(#g.hand[def])]
    for _, pair in ipairs({ { atk, ca }, { def, cd } }) do
        local s, c = pair[1], pair[2]
        for i, x in ipairs(g.hand[s]) do if x == c then table.remove(g.hand[s], i) break end end
        local f = g.field[s]
        f[#f + 1] = cardOut(c)
        while #f > 5 do table.remove(f, 1) end
    end
    local diff = ca.att - cd.def
    local damage = diff > 0 and math.floor(diff * (B.damageScale or 10)) or 0
    g.life[def] = math.max(0, g.life[def] - damage)
    local line = damage > 0
        and ('%s (%d ATT) hits %s (%d DEF) for %s'):format(ca.display.label, ca.att, cd.display.label, cd.def, damage)
        or ('%s (%d DEF) blocks %s (%d ATT)'):format(cd.display.label, cd.def, ca.display.label, ca.att)
    pushLog(g, line)
    everyone(g, 'as-tradingcards:client:btReveal', function(s, watch)
        local mineIsAtk = atk == s
        return {
            watch = watch or nil, role = mineIsAtk and 'attack' or 'defend', attackerName = g.names[atk],
            atk = cardOut(ca), def = cardOut(cd), damage = damage, diff = diff,
            life = lives(g, s), line = line, log = g.log, youAttack = mineIsAtk,
            field = { mine = g.field[s], theirs = g.field[other(g, s)] },
        }
    end)
    SetTimeout(math.floor((B.revealSeconds or 4.5) * 1000), function()
        if games[g.id] ~= g or g.state ~= 'reveal' then return end
        for _, s in ipairs(g.p) do draw(g, s) end
        if checkEnd(g) or os.time() >= g.endsAt then return Battle.Finish(g) end
        g.attacker = other(g, g.attacker)
        sendTurn(g)
    end)
end

RegisterNetEvent('as-tradingcards:server:btPick', function(uid)
    local src = source
    local g = games[inGame[src] or 0]
    if not g or g.state ~= 'pick' or g.picks[src] then return end
    uid = tonumber(uid)
    for _, c in ipairs(g.hand[src]) do
        if c.uid == uid then
            g.picks[src] = c
            local o = other(g, src)
            if online(o) then TriggerClientEvent('as-tradingcards:client:btPicked', o, {}) end
            for s in pairs(g.spec) do if online(s) then TriggerClientEvent('as-tradingcards:client:btPicked', s, {}) end end
            if g.picks[g.p[1]] and g.picks[g.p[2]] then resolve(g) end
            return
        end
    end
end)

RegisterNetEvent('as-tradingcards:server:btForfeit', function()
    local src = source
    local g = games[inGame[src] or 0]
    if g then Battle.Finish(g, src, 'forfeit') end
end)

-- Starts a match between two online players. a / b = { src, deckId }. opts: tableId, bet, tourney
function Battle.Start(a, b, opts)
    opts = opts or {}
    local decks = {}
    for _, p in ipairs({ a, b }) do
        if inGame[p.src] then return nil, ('%s is already in a match.'):format(name(p.src)) end
        local rows, err = loadDeck(p.src, p.deckId)
        if not rows then return nil, ('%s: %s'):format(name(p.src), err) end
        decks[p.src] = rows
    end
    local bet = math.floor(opts.bet or 0)
    if bet > 0 then
        if not take(a.src, bet) then return nil, ('%s can’t cover the wager.'):format(name(a.src)) end
        if not take(b.src, bet) then give(a.src, bet) return nil, ('%s can’t cover the wager.'):format(name(b.src)) end
    end
    nextGame = nextGame + 1
    local g = {
        id = nextGame, p = { a.src, b.src }, ids = { [a.src] = Framework.GetIdentifier(a.src), [b.src] = Framework.GetIdentifier(b.src) },
        names = { [a.src] = name(a.src), [b.src] = name(b.src) },
        life = { [a.src] = B.life or 4000, [b.src] = B.life or 4000 },
        hand = { [a.src] = {}, [b.src] = {} }, pile = { [a.src] = {}, [b.src] = {} }, field = { [a.src] = {}, [b.src] = {} },
        picks = {}, spec = {}, log = {}, turn = 0, state = 'start', bet = bet, pot = bet * 2, noRank = opts.noRank,
        tableId = opts.tableId, tourney = opts.tourney, endsAt = os.time() + (B.matchSeconds or 600),
    }
    local uid = 0
    for _, p in ipairs({ a, b }) do
        local pile = {}
        for _, r in ipairs(decks[p.src]) do
            uid = uid + 1
            local c = prep(r) c.uid = uid
            pile[#pile + 1] = c
        end
        g.pile[p.src] = shuffle(pile)
        if DB.Seen then for _, r in ipairs(decks[p.src]) do DB.Seen(p.src, r.meta) end end
    end
    g.attacker = g.p[math.random(2)]
    games[g.id] = g
    inGame[a.src], inGame[b.src] = g.id, g.id
    if g.tableId and tables[g.tableId] then tables[g.tableId].state, tables[g.tableId].game = 'playing', g.id pushTables() end
    local mats = { [a.src] = matFor(a.src), [b.src] = matFor(b.src) }
    local function startData(s, watch)
        local o = other(g, s)
        return {
            watch = watch or nil, me = { name = g.names[s], rank = Rank.Get(g.ids[s]).tier.name }, opp = { name = g.names[o], rank = Rank.Get(g.ids[o]).tier.name },
            life = B.life or 4000, pot = g.pot, bet = g.bet, mats = { mine = mats[s], theirs = mats[o] }, season = Season.Number(),
            tourney = g.tourney and g.tourney.name or nil, table = g.tableId, matchLeft = math.max(0, g.endsAt - os.time()),
            ranked = not g.noRank,
        }
    end
    g.startData = startData
    everyone(g, 'as-tradingcards:client:btStart', startData)
    SetTimeout(1800, function() if games[g.id] == g then sendTurn(g) end end)
    return g
end

-- spectators -----------------------------------------------------------------
lib.callback.register('as-tradingcards:server:btSpectate', function(src, tableId)
    local t = tables[tonumber(tableId)]
    if not t or not TB.spectators then return nil, 'Nothing to watch.' end
    local g = t.game and games[t.game]
    if not g then return nil, 'Nobody is playing at this table.' end
    if inGame[src] then return nil, 'You’re in a match.' end
    if distTo(src, vec3(t.x, t.y, t.z)) > (TB.spectateRange or 8.0) then return nil, 'Get closer to watch.' end
    g.spec[src] = true
    TriggerClientEvent('as-tradingcards:client:btStart', src, g.startData(g.p[1], true))
    if g.turn > 0 and g.state ~= 'reveal' then TriggerClientEvent('as-tradingcards:client:btTurn', src, turnData(g, g.p[1], true)) end
    return true
end)

RegisterNetEvent('as-tradingcards:server:btUnspectate', function()
    local src = source
    for _, g in pairs(games) do g.spec[src] = nil end
end)

--[[ ---------------------------------------------------------------------------
    LOBBIES  (host opens a game at a table, someone else joins)
--------------------------------------------------------------------------- ]]
local function tableNear(src, id)
    local t = tables[tonumber(id)]
    if not t then return nil end
    if distTo(src, vec3(t.x, t.y, t.z)) > (TB.range or 3.0) + 1.0 then return nil end
    return t
end

lib.callback.register('as-tradingcards:server:tableInfo', function(src, id)
    local t = tableNear(src, id)
    if not t then return nil, 'Get closer to the table.' end
    local identifier = Framework.GetIdentifier(src)
    local lobby = lobbies[t.id]
    local g = t.game and games[t.game]
    local mats = {}
    for _, m in ipairs(Config.Mats.list) do mats[#mats + 1] = { id = m.id, label = m.label } end
    return {
        id = t.id, state = g and 'playing' or (lobby and 'waiting' or 'free'),
        host = lobby and lobby.hostName or nil, hostIsMe = lobby and lobby.host == src or false, bet = lobby and lobby.bet or 0,
        players = g and { g.names[g.p[1]], g.names[g.p[2]] } or nil, spectate = TB.spectators and g ~= nil,
        decks = Decks.ForPlayer(src), bets = BET.enabled and { min = BET.min, max = BET.max, account = BET.account } or nil,
        owner = t.owner_name, mine = t.owner == identifier, mats = mats, myMat = matFor(src).id,
        canPickup = Framework.IsAdmin(src) or TB.pickupBy == 'anyone' or t.owner == identifier,
        me = Rank.Get(identifier).tier.name,
    }
end)

lib.callback.register('as-tradingcards:server:openGame', function(src, id, deckId, bet)
    local t = tableNear(src, id)
    if not t then return nil, 'Get closer to the table.' end
    if inGame[src] then return nil, 'You’re already in a match.' end
    if t.game or lobbies[t.id] then return nil, 'This table is busy.' end
    for _, l in pairs(lobbies) do if l.host == src then return nil, 'You already opened a game at another table.' end end
    bet = math.floor(tonumber(bet) or 0)
    if bet > 0 then
        if not BET.enabled then bet = 0
        elseif bet < (BET.min or 1) or bet > (BET.max or 50000) then return nil, ('Wagers are %s to %s.'):format(money(BET.min or 1), money(BET.max or 50000))
        elseif (Framework.GetMoney(src, BET.account or 'cash') or 0) < bet then return nil, ('You don’t have %s on you.'):format(money(bet)) end
    end
    local rows, err = loadDeck(src, deckId)
    if not rows then return nil, err end
    lobbies[t.id] = { host = src, hostName = name(src), deckId = deckId, bet = bet, at = os.time() }
    notify(src, bet > 0 and ('Game open at the table for %s each. Waiting for a challenger.'):format(money(bet)) or 'Game open at the table. Waiting for a challenger.', 'success')
    return true
end)

lib.callback.register('as-tradingcards:server:cancelGame', function(src, id)
    local l = lobbies[tonumber(id)]
    if l and l.host == src then lobbies[tonumber(id)] = nil return true end
    return nil
end)

lib.callback.register('as-tradingcards:server:joinGame', function(src, id, deckId)
    local t = tableNear(src, id)
    if not t then return nil, 'Get closer to the table.' end
    local l = lobbies[t.id]
    if not l or t.game then return nil, 'Nobody is waiting here.' end
    if l.host == src then return nil, 'That’s your own game.' end
    if not online(l.host) then lobbies[t.id] = nil return nil, 'The host left.' end
    if inGame[src] then return nil, 'You’re already in a match.' end
    if distTo(l.host, vec3(t.x, t.y, t.z)) > (TB.range or 3.0) + 4.0 then lobbies[t.id] = nil return nil, 'The host walked away.' end
    local lobby = l
    lobbies[t.id] = nil
    local g, err = Battle.Start({ src = lobby.host, deckId = lobby.deckId }, { src = src, deckId = deckId }, { tableId = t.id, bet = lobby.bet })
    if not g then
        notify(lobby.host, err or 'The match could not start.', 'error')
        lobbies[t.id] = lobby
        return nil, err
    end
    return true
end)

lib.callback.register('as-tradingcards:server:btBoard', function(src)
    local identifier = Framework.GetIdentifier(src)
    local me = Rank.Get(identifier)
    local pos = MySQL.scalar.await('SELECT COUNT(*) + 1 FROM ascard_rank WHERE season = ? AND points > ?', { Season.Number(), me.points }) or 1
    local last = {}
    if Season.Number() > 1 then
        last = MySQL.query.await('SELECT name, points FROM ascard_rank WHERE season = ? ORDER BY points DESC, wins DESC LIMIT 3', { Season.Number() - 1 }) or {}
    end
    return {
        season = Season.Number(), endsIn = math.max(0, Season.EndsAt() - os.time()), top = Rank.Board(),
        me = { name = name(src), points = me.points, wins = me.wins, losses = me.losses, draws = me.draws, tier = me.tier, pos = pos },
        last = last, tourney = Tourney and Tourney.Summary and Tourney.Summary(src) or nil,
        tiers = (Config.Season or {}).tiers,
    }
end)

-- cleanup ----------------------------------------------------------------------
AddEventHandler('playerDropped', function()
    local src = source
    local g = games[inGame[src] or 0]
    if g then Battle.Finish(g, src, 'forfeit') end
    for id, l in pairs(lobbies) do if l.host == src then lobbies[id] = nil end end
    for _, gm in pairs(games) do gm.spec[src] = nil end
end)

CreateThread(function()
    while true do
        Wait(1000)
        local now = os.time()
        for _, g in pairs(games) do
            if g.state == 'pick' and g.deadline and now >= g.deadline then
                -- slow players get a random card
                for _, s in ipairs(g.p) do
                    if not g.picks[s] and #g.hand[s] > 0 then g.picks[s] = g.hand[s][math.random(#g.hand[s])] end
                end
                resolve(g)
            end
            if g.state == 'pick' and now >= g.endsAt then Battle.Finish(g) end
        end
        for id, l in pairs(lobbies) do
            local t = tables[id]
            if not online(l.host) or not t or now - l.at > 600 or distTo(l.host, vec3(t.x, t.y, t.z)) > (TB.range or 3.0) + 8.0 then
                lobbies[id] = nil
                if online(l.host) then notify(l.host, 'Your open game at the table closed.', 'inform') end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, g in pairs(games) do
        if g.state ~= 'over' then give(g.p[1], g.bet) give(g.p[2], g.bet) end
    end
end)

--[[ ---------------------------------------------------------------------------
    SEASON ANNOUNCEMENT
--------------------------------------------------------------------------- ]]
CreateThread(function()
    V2.Wait()
    local last = tonumber(V2.GetSetting('battle_season', '0')) or 0
    while true do
        local n = Season.Number()
        if n ~= last then
            if last > 0 and (Config.Season or {}).announce then
                local top = MySQL.query.await('SELECT name, points FROM ascard_rank WHERE season = ? ORDER BY points DESC, wins DESC LIMIT 3', { last }) or {}
                local msg = ('Battle season %d is over.'):format(last)
                if top[1] then msg = msg .. (' Champion: %s (%d points).'):format(top[1].name, top[1].points) end
                msg = msg .. (' Season %d starts now.'):format(n)
                TriggerClientEvent('ox_lib:notify', -1, { title = 'Card battles', description = msg, type = 'inform', duration = 12000 })
            end
            last = n
            V2.SetSetting('battle_season', n)
        end
        Wait(60000)
    end
end)
