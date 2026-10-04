--[[ Staff run tournaments (/cardtourney). Players register with /jointourney (needs a valid deck box).
     Single elimination. Rank points only, no prizes. A player who doesn't accept their match in time forfeits it. ]]
local B = Config.Battle or {}
if not B.enabled then return end
local TC = Config.Tournament or {}

Tourney = { t = nil }
local function online(s) return s and GetPlayerName(s) ~= nil end
local function name(s) return Framework.GetName(s) or GetPlayerName(s) or '?' end
local function say(msg, target) TriggerClientEvent('ox_lib:notify', target or -1, { title = 'Card tournament', description = msg, type = 'inform', duration = 9000 }) end

local function findEntry(t, id) for _, e in ipairs(t.players) do if e.id == id then return e end end end

function Tourney.Summary(src)
    local t = Tourney.t
    if not t then return nil end
    local ids = Framework.GetIdentifier(src)
    local names = {}
    for _, e in ipairs(t.players) do names[#names + 1] = e.name end
    local joined = findEntry(t, ids) ~= nil
    local rounds = {}
    for r, ms in ipairs(t.rounds or {}) do
        local row = {}
        for _, m in ipairs(ms) do row[#row + 1] = { a = m.a and m.a.name or '—', b = m.b and m.b.name or (m.bye and 'bye' or '—'), winner = m.winner and m.winner.name or nil, state = m.state } end
        rounds[r] = row
    end
    return { name = t.name, state = t.state, size = t.size, players = names, joined = joined, rounds = rounds, round = t.round, champion = t.champion and t.champion.name or nil }
end

lib.callback.register('as-tradingcards:server:tourneyJoin', function(src)
    local t = Tourney.t
    if not t or t.state ~= 'open' then return nil, 'There’s no tournament open to join.' end
    local id = Framework.GetIdentifier(src)
    if findEntry(t, id) then return nil, 'You’re already in.' end
    if #t.players >= t.size then return nil, 'The tournament is full.' end
    local ok = false
    for _, d in ipairs(Decks.ForPlayer(src)) do if d.valid then ok = true end end
    if not ok then return nil, 'You need a valid deck box on you (30 cards) to enter.' end
    t.players[#t.players + 1] = { id = id, name = name(src), src = src }
    say(('%s joined the tournament (%d/%d).'):format(name(src), #t.players, t.size), -1)
    return true
end)

lib.callback.register('as-tradingcards:server:tourneyLeave', function(src)
    local t = Tourney.t
    if not t or t.state ~= 'open' then return nil, 'You can only leave before it starts.' end
    local id = Framework.GetIdentifier(src)
    for i, e in ipairs(t.players) do if e.id == id then table.remove(t.players, i) return true end end
    return nil, 'You’re not entered.'
end)

--[[ bracket ]]
local function build(t)
    local list = {}
    for _, e in ipairs(t.players) do list[#list + 1] = e end
    for i = #list, 2, -1 do local j = math.random(i) list[i], list[j] = list[j], list[i] end
    local P = 2
    while P < #list do P = P * 2 end
    local slots = {}
    for i = 1, P do slots[i] = list[i] end   -- empty slots = byes
    -- spread byes: pair slot i with slot P+1-i
    local first = {}
    for i = 1, P / 2 do
        local a, b = slots[i], slots[P + 1 - i]
        first[#first + 1] = { a = a, b = b, state = 'wait', bye = (a == nil) ~= (b == nil) }
    end
    t.rounds = { first }
    local n = P / 2
    while n > 1 do
        n = n / 2
        local ms = {}
        for _ = 1, n do ms[#ms + 1] = { state = 'wait' } end
        t.rounds[#t.rounds + 1] = ms
    end
    t.round = 1
end

local function srcOf(e) return e and Framework.GetSourceByIdentifier(e.id) end

local function finishMatch(t, m, winner, why)
    m.winner, m.state = winner, 'done'
    if m.a and m.b and why ~= 'bye' then
        say(('%s beat %s.'):format(winner.name, (winner == m.a and m.b or m.a).name))
    end
end

local function prompt(t, m, ri, mi)
    m.state = 'ready'
    m.key = ('%d:%d'):format(ri, mi)
    m.deadline = os.time() + (TC.readySeconds or 90)
    m.accepted = {}
    for _, e in ipairs({ m.a, m.b }) do
        local s = srcOf(e)
        if s then
            local opp = e == m.a and m.b or m.a
            TriggerClientEvent('as-tradingcards:client:tourneyReady', s, { key = m.key, opponent = opp.name, seconds = TC.readySeconds or 90, tourney = t.name, decks = Decks.ForPlayer(s) })
        end
    end
end

lib.callback.register('as-tradingcards:server:tourneyAccept', function(src, key, deckId)
    local t = Tourney.t
    if not t or t.state ~= 'running' then return nil, 'No tournament is running.' end
    local id = Framework.GetIdentifier(src)
    for _, ms in ipairs(t.rounds) do
        for _, m in ipairs(ms) do
            if m.state == 'ready' and m.key == key then
                local e = (m.a and m.a.id == id and m.a) or (m.b and m.b.id == id and m.b)
                if not e then return nil, 'That isn’t your match.' end
                if Battle.inGame[src] then return nil, 'You’re in a match.' end
                local ok = false
                for _, d in ipairs(Decks.ForPlayer(src)) do if d.id == deckId and d.valid then ok = true end end
                if not ok then return nil, 'Pick a valid deck box (30 cards) you have on you.' end
                m.accepted[id] = deckId
                return true
            end
        end
    end
    return nil, 'That match is no longer waiting.'
end)

function Tourney.Report(g, winner, why)
    local t = Tourney.t
    if not t or t.state ~= 'running' then return end
    local m = g.tourney and g.tourney.match
    if not m or m.state ~= 'playing' then return end
    local wid = winner and g.ids[winner]
    local w = wid and ((m.a and m.a.id == wid and m.a) or (m.b and m.b.id == wid and m.b))
    if not w then
        -- draw / table pickup: replay
        m.state = 'wait'
        say(('%s vs %s was a draw. Replay coming up.'):format(m.a.name, m.b.name))
        return
    end
    finishMatch(t, m, w, why)
end

local function tick()
    local t = Tourney.t
    if not t or t.state ~= 'running' then return end
    local ri = t.round
    local ms = t.rounds[ri]
    local alldone = true
    local now = os.time()
    for mi, m in ipairs(ms) do
        if m.state ~= 'done' then alldone = false end
        if m.state == 'wait' then
            if m.bye then finishMatch(t, m, m.a or m.b, 'bye')
            elseif m.a and m.b then prompt(t, m, ri, mi) end
        elseif m.state == 'ready' then
            local a, b = m.accepted[m.a.id], m.accepted[m.b.id]
            local sa, sb = srcOf(m.a), srcOf(m.b)
            if a and b and sa and sb then
                local g, err = Battle.Start({ src = sa, deckId = a }, { src = sb, deckId = b }, { tourney = { name = t.name, match = m } })
                if g then m.state = 'playing' else
                    m.accepted = {}
                    for _, s in ipairs({ sa, sb }) do Framework.Notify(s, err or 'Could not start the match, please accept again.', 'error') end
                    prompt(t, m, ri, mi)
                end
            elseif now >= m.deadline then
                if a and sa and not (b and sb) then finishMatch(t, m, m.a, 'walkover') say(('%s didn’t turn up. %s goes through.'):format(m.b.name, m.a.name))
                elseif b and sb and not (a and sa) then finishMatch(t, m, m.b, 'walkover') say(('%s didn’t turn up. %s goes through.'):format(m.a.name, m.b.name))
                else finishMatch(t, m, math.random(2) == 1 and m.a or m.b, 'walkover') say('Neither player turned up. One was drawn to go through.') end
            end
        end
    end
    if alldone then
        if ri >= #t.rounds then
            t.state, t.champion = 'done', ms[1].winner
            say(('%s wins the %s!'):format(t.champion.name, t.name))
            if (TC.championPoints or 0) > 0 then Rank.Add(t.champion.id, t.champion.name, TC.championPoints, 'bonus') end
        else
            local nxt = t.rounds[ri + 1]
            for i, m in ipairs(nxt) do
                m.a, m.b = ms[i * 2 - 1].winner, ms[i * 2].winner
                m.bye = false
            end
            t.round = ri + 1
            say(('Round %d of the %s is starting. Check your match prompt.'):format(t.round, t.name))
        end
    end
end

CreateThread(function() while true do Wait(2000) pcall(tick) end end)

--[[ staff ]]
local function isAdmin(src) return Framework.IsAdmin(src) end

lib.callback.register('as-tradingcards:server:tourneyAdmin', function(src, action, d)
    if not isAdmin(src) then return nil, 'Staff only.' end
    d = type(d) == 'table' and d or {}
    local t = Tourney.t
    if action == 'status' then return Tourney.Summary(src) or false end
    if action == 'create' then
        if t and t.state ~= 'done' then return nil, 'A tournament is already open or running. Cancel it first.' end
        local size = tonumber(d.size) or 8
        local okSize = false
        for _, s in ipairs(TC.sizes or { 4, 8, 16 }) do if s == size then okSize = true end end
        if not okSize then return nil, 'Pick one of the allowed sizes.' end
        Tourney.t = { name = tostring(d.name or 'Card Battle Cup'):sub(1, 40), size = size, state = 'open', players = {} }
        say(('%s is open! Up to %d players. Use /jointourney (you need a valid deck box).'):format(Tourney.t.name, size))
        return Tourney.Summary(src)
    end
    if not t then return nil, 'No tournament.' end
    if action == 'start' then
        if t.state ~= 'open' then return nil, 'It already started.' end
        if #t.players < 2 then return nil, 'Need at least 2 players.' end
        t.state = 'running'
        build(t)
        say(('The %s has started with %d players.'):format(t.name, #t.players))
        return Tourney.Summary(src)
    end
    if action == 'cancel' then
        Tourney.t = nil
        say('The tournament was cancelled.')
        return false
    end
    if action == 'kick' then
        for i, e in ipairs(t.players) do if e.id == d.id then table.remove(t.players, i) end end
        return Tourney.Summary(src)
    end
    return nil, 'Unknown action.'
end)

lib.addCommand(TC.command or 'cardtourney', { help = 'Card battle tournaments (staff)', restricted = Config.AdminAce }, function(src)
    if src and src > 0 then TriggerClientEvent('as-tradingcards:client:tourneyAdmin', src) end
end)
lib.addCommand('jointourney', { help = 'Join the open card battle tournament' }, function(src)
    if not src or src <= 0 then return end
    TriggerClientEvent('as-tradingcards:client:tourneyJoinCmd', src)
end)
