--[[ Top Trumps: challenge a nearby player, best of N rounds with the cards in your pockets ]]
local TT = Config.TopTrumps or {}
if not TT.enabled then return end

local games, inGame, invites = {}, {}, {}
local nextId = 0
local BET = TT.bets or {}

local function money(n) return Utils.Money and Utils.Money(n) or ('£' .. tostring(n)) end
local function name(src) return Framework.GetName(src) or GetPlayerName(src) or ('Player ' .. src) end
local function dist(a, b)
    local pa, pb = GetPlayerPed(a), GetPlayerPed(b)
    if pa == 0 or pb == 0 then return 9999 end
    return #(GetEntityCoords(pa) - GetEntityCoords(pb))
end

local function boost(m)
    local B, b = TT.boosts or {}, 0
    if m.parallel then b = b + ((B.parallel or {})[m.parallel] or 0) end
    if m.foil then b = b + (B.foil or 0) end
    if m.insert then b = b + (B.insert or 0) end
    return b
end

local function deckFor(src)
    local list = {}
    for _, item in ipairs(Inventory.GetItems(src, Utils.IsCollectible)) do
        local m = item.metadata or {}
        if m.cardId and Config.Cards[m.cardId] then list[#list + 1] = { item = item.name, meta = m } end
    end
    return list
end

local function prep(e)
    local card = Config.Cards[e.meta.cardId]
    local b = boost(e.meta)
    local cap = TT.maxStat or 110
    local noStats = e.meta.error == 'noStats'   -- misprint with no stats printed: plays as 0
    return {
        display = Utils.BuildDisplay(e.meta, e.item), title = Utils.CardTitle(e.meta, e.item), boost = b,
        att = noStats and 0 or math.min(cap, (card.att or 0) + b), def = noStats and 0 or math.min(cap, (card.def or 0) + b),
    }
end

local function deal(src)
    local d = deckFor(src)
    for i = #d, 2, -1 do local j = math.random(i) d[i], d[j] = d[j], d[i] end
    local out = {}
    for i = 1, math.min(#d, TT.rounds or 5) do out[i] = prep(d[i]) end
    return out
end

local function take(src, amount)
    if amount <= 0 then return true end
    local acc = BET.account or 'cash'
    if (Framework.GetMoney(src, acc) or 0) < amount then return false end
    return Framework.RemoveMoney(src, acc, amount, 'ascard-toptrumps')
end
local function give(src, amount)
    if amount > 0 and GetPlayerName(src) then Framework.AddMoney(src, BET.account or 'cash', amount, 'ascard-toptrumps') end
end

--[[ ---------------------------------------------------------------------------
    CHALLENGE
--------------------------------------------------------------------------- ]]
lib.callback.register('as-tradingcards:server:ttNearby', function(src)
    local out = {}
    for _, s in ipairs(GetPlayers()) do
        s = tonumber(s)
        if s ~= src then
            local d = dist(src, s)
            if d <= (TT.range or 4.0) then out[#out + 1] = { id = s, name = name(s), dist = math.floor(d * 10) / 10 } end
        end
    end
    table.sort(out, function(a, b) return a.dist < b.dist end)
    return { players = out, bets = BET.enabled and { min = BET.min, max = BET.max, account = BET.account } or nil, rounds = TT.rounds or 5 }
end)

lib.callback.register('as-tradingcards:server:ttChallenge', function(src, target, bet)
    target = tonumber(target)
    bet = math.floor(tonumber(bet) or 0)
    if not target or not GetPlayerName(target) or target == src then return nil, 'That person isn’t here.' end
    if inGame[src] or inGame[target] then return nil, 'One of you is already playing.' end
    if dist(src, target) > (TT.range or 4.0) + 1 then return nil, 'Get closer to them first.' end
    for _, inv in pairs(invites) do
        if inv.from == src or inv.to == target then return nil, 'There’s already a challenge waiting.' end
    end
    local need = TT.rounds or 5
    if #deckFor(src) < need then return nil, ('You need at least %d cards on you.'):format(need) end
    if bet > 0 then
        if not BET.enabled then bet = 0
        elseif bet < (BET.min or 1) or bet > (BET.max or 1e9) then return nil, ('Bets are %s to %s.'):format(money(BET.min or 1), money(BET.max or 1e9))
        elseif (Framework.GetMoney(src, BET.account or 'cash') or 0) < bet then return nil, ('You don’t have %s on you.'):format(money(bet)) end
    end
    nextId = nextId + 1
    local id = nextId
    invites[id] = { id = id, from = src, to = target, bet = bet, expires = os.time() + (TT.inviteSeconds or 30) }
    TriggerClientEvent('as-tradingcards:client:ttInvite', target, { id = id, name = name(src), bet = bet, rounds = need, seconds = TT.inviteSeconds or 30, account = BET.account })
    return true
end)

--[[ ---------------------------------------------------------------------------
    GAME
--------------------------------------------------------------------------- ]]
local function other(g, src) return g.p[1] == src and g.p[2] or g.p[1] end

local function sendRound(g)
    g.state = 'choose'
    g.deadline = os.time() + (TT.turnSeconds or 20)
    for _, s in ipairs(g.p) do
        local o = other(g, s)
        TriggerClientEvent('as-tradingcards:client:ttRound', s, {
            round = g.round, rounds = g.rounds, card = g.decks[s][g.round], chooser = g.chooser == s,
            score = { you = g.score[s], them = g.score[o] }, seconds = TT.turnSeconds or 20, opponent = g.names[o], pot = g.pot,
        })
    end
end

local function finish(g, forfeitBy)
    if g.state == 'over' then return end
    g.state = 'over'
    local a, b = g.p[1], g.p[2]
    local winner
    if forfeitBy then winner = other(g, forfeitBy)
    elseif g.score[a] > g.score[b] then winner = a
    elseif g.score[b] > g.score[a] then winner = b end
    if winner then give(winner, g.pot) else give(a, g.bet) give(b, g.bet) end
    if winner and MoneyLog and (g.pot or 0) > 0 then MoneyLog.Add(winner, 'toptrumps', g.pot - (g.bet or 0), ('Beat %s (pot %s)'):format(g.names[other(g, winner)] or '?', Utils.Money(g.pot))) end
    for _, s in ipairs(g.p) do
        inGame[s] = nil
        local o = other(g, s)
        TriggerClientEvent('as-tradingcards:client:ttEnd', s, {
            outcome = not winner and 'draw' or (winner == s and 'win' or 'lose'),
            score = { you = g.score[s], them = g.score[o] }, pot = g.pot, bet = g.bet, forfeit = forfeitBy ~= nil and forfeitBy ~= s or nil,
            opponent = g.names[o],
        })
    end
    games[g.id] = nil
end

local function resolve(g, stat)
    if g.state ~= 'choose' then return end
    g.state = 'reveal'
    local a, b = g.p[1], g.p[2]
    local ca, cb = g.decks[a][g.round], g.decks[b][g.round]
    local va, vb = ca[stat], cb[stat]
    local roundWinner = va > vb and a or vb > va and b or nil
    if roundWinner then g.score[roundWinner] = g.score[roundWinner] + 1 g.chooser = roundWinner end
    for _, s in ipairs(g.p) do
        local o = other(g, s)
        TriggerClientEvent('as-tradingcards:client:ttResult', s, {
            stat = stat, you = g.decks[s][g.round], them = g.decks[o][g.round],
            yourValue = g.decks[s][g.round][stat], theirValue = g.decks[o][g.round][stat],
            outcome = not roundWinner and 'draw' or (roundWinner == s and 'win' or 'lose'),
            score = { you = g.score[s], them = g.score[o] }, pickedBy = g.names[g.lastChooser == s and s or o],
        })
    end
    SetTimeout(math.floor((TT.revealSeconds or 3.5) * 1000), function()
        if games[g.id] ~= g or g.state ~= 'reveal' then return end
        local left = g.rounds - g.round
        local lead = math.abs(g.score[a] - g.score[b])
        if g.round >= g.rounds or lead > left then return finish(g) end
        g.round = g.round + 1
        sendRound(g)
    end)
end

lib.callback.register('as-tradingcards:server:ttAnswer', function(src, id, accept)
    local inv = invites[tonumber(id)]
    if not inv or inv.to ~= src then return nil end
    invites[inv.id] = nil
    local a, b = inv.from, inv.to
    if not accept then
        if GetPlayerName(a) then TriggerClientEvent('ox_lib:notify', a, { description = ('%s turned down your Top Trumps challenge.'):format(name(b)), type = 'error' }) end
        return true
    end
    if os.time() > inv.expires then return nil, 'That challenge ran out.' end
    if not GetPlayerName(a) or inGame[a] or inGame[b] then return nil, 'The challenge is no longer open.' end
    if dist(a, b) > (TT.range or 4.0) + 2 then return nil, 'You’re too far apart.' end
    local need = TT.rounds or 5
    if #deckFor(b) < need then return nil, ('You need at least %d cards on you.'):format(need) end
    if #deckFor(a) < need then return nil, 'They don’t have enough cards on them any more.' end
    if inv.bet > 0 then
        if not take(b, inv.bet) then return nil, ('You don’t have %s on you.'):format(money(inv.bet)) end
        if not take(a, inv.bet) then give(b, inv.bet) return nil, 'They can’t cover the bet any more.' end
    end
    nextId = nextId + 1
    local g = { id = nextId, p = { a, b }, names = { [a] = name(a), [b] = name(b) }, decks = { [a] = deal(a), [b] = deal(b) },
        round = 1, rounds = need, chooser = a, score = { [a] = 0, [b] = 0 }, bet = inv.bet, pot = inv.bet * 2 }
    games[g.id], inGame[a], inGame[b] = g, g.id, g.id
    for _, s in ipairs(g.p) do
        TriggerClientEvent('as-tradingcards:client:ttStart', s, { opponent = g.names[other(g, s)], rounds = g.rounds, pot = g.pot, bet = g.bet })
    end
    SetTimeout(1500, function() if games[g.id] == g then sendRound(g) end end)
    return true
end)

RegisterNetEvent('as-tradingcards:server:ttChoose', function(stat)
    local src = source
    local g = games[inGame[src] or 0]
    if not g or g.state ~= 'choose' or g.chooser ~= src then return end
    if stat ~= 'att' and stat ~= 'def' then return end
    g.lastChooser = src
    resolve(g, stat)
end)

RegisterNetEvent('as-tradingcards:server:ttForfeit', function()
    local src = source
    local g = games[inGame[src] or 0]
    if g then finish(g, src) end
end)

AddEventHandler('playerDropped', function()
    local src = source
    local g = games[inGame[src] or 0]
    if g then finish(g, src) end
    for id, inv in pairs(invites) do if inv.from == src or inv.to == src then invites[id] = nil end end
end)

-- slow choosers: pick their better stat for them; old invites: drop them
CreateThread(function()
    while true do
        Wait(1000)
        local now = os.time()
        for _, g in pairs(games) do
            if g.state == 'choose' and now >= g.deadline then
                local c = g.decks[g.chooser][g.round]
                g.lastChooser = g.chooser
                resolve(g, c.att >= c.def and 'att' or 'def')
            end
        end
        for id, inv in pairs(invites) do
            if now > inv.expires then
                invites[id] = nil
                if GetPlayerName(inv.from) then TriggerClientEvent('ox_lib:notify', inv.from, { description = 'Your Top Trumps challenge wasn’t answered.', type = 'inform' }) end
            end
        end
    end
end)
