-- Top Trumps (client): challenge menu, invite prompt, and the game screen in the card NUI
local TT = Config.TopTrumps or {}
if not TT.enabled then return end

local playing = false

local function money(n) return Utils.Money(n) end

local function challenge(targetId)
    local info = lib.callback.await('as-tradingcards:server:ttNearby', false)
    if not info then return end
    local function ask(target)
        local bet = 0
        if info.bets then
            local input = lib.inputDialog('Top Trumps', {
                { type = 'select', label = 'Stakes', default = 'none', options = { { value = 'none', label = 'No bet (just for fun)' }, { value = 'bet', label = 'Cash bet' } } },
                { type = 'number', label = ('Bet (%s to %s, both pay)'):format(money(info.bets.min), money(info.bets.max)), min = 0, max = info.bets.max, default = info.bets.min },
            })
            if not input then return end
            bet = input[1] == 'bet' and math.floor(tonumber(input[2]) or 0) or 0
        end
        local ok, err = lib.callback.await('as-tradingcards:server:ttChallenge', false, target, bet)
        if ok then
            lib.notify({ description = bet > 0 and ('Challenge sent for %s.'):format(money(bet)) or 'Challenge sent.', type = 'inform' })
        else
            lib.notify({ description = err or 'Could not send the challenge.', type = 'error' })
        end
    end
    if targetId then return ask(targetId) end
    if #info.players == 0 then return lib.notify({ description = 'Nobody close enough to challenge.', type = 'error' }) end
    local options = {}
    for _, p in ipairs(info.players) do
        options[#options + 1] = { title = p.name, description = ('%.1f m away · best of %d'):format(p.dist, info.rounds), icon = 'fas fa-clone', onSelect = function() ask(p.id) end }
    end
    lib.registerContext({ id = 'ascard_tt', title = 'Top Trumps: challenge', options = options })
    lib.showContext('ascard_tt')
end

RegisterCommand(TT.command or 'toptrumps', function() challenge() end, false)

-- Target option on other players: ox_target has a "global player" export that tracks everyone
-- automatically; as-interact and qb-target don't, so for those we keep a light poll adding/
-- removing a per-player entity interaction as players come in and out of the session.
CreateThread(function()
    if not TT.target then return end

    if GetResourceState('ox_target') == 'started' then
        exports.ox_target:addGlobalPlayer({
            {
                name = 'ascard_toptrumps', icon = 'fas fa-clone', label = 'Challenge to Top Trumps', distance = TT.range or 4.0,
                onSelect = function(data)
                    local id = data and data.entity and GetPlayerServerId(NetworkGetPlayerIndexFromPed(data.entity))
                    if id and id > 0 then challenge(id) end
                end,
            },
        })
        return
    end

    if GetResourceState('as-interact') ~= 'started' then return end

    local tracked = {} -- [serverId] = interaction id
    while true do
        local myPed = PlayerPedId()
        local seen = {}
        for _, playerIndex in ipairs(GetActivePlayers()) do
            local ped = GetPlayerPed(playerIndex)
            if ped ~= myPed and DoesEntityExist(ped) then
                local id = GetPlayerServerId(playerIndex)
                seen[id] = true
                if not tracked[id] then
                    tracked[id] = exports['as-interact']:AddEntityInteraction({
                        netId = NetworkGetNetworkIdFromEntity(ped),
                        distance = TT.range or 4.0,
                        interactDst = TT.range or 4.0,
                        options = {
                            { name = 'ascard_toptrumps', label = 'Challenge to Top Trumps',
                              action = function() challenge(id) end },
                        },
                    })
                end
            end
        end
        for id, interactionId in pairs(tracked) do
            if not seen[id] then
                exports['as-interact']:RemoveInteraction(interactionId)
                tracked[id] = nil
            end
        end
        Wait(3000)
    end
end)

RegisterNetEvent('as-tradingcards:client:ttInvite', function(inv)
    local closed = false
    SetTimeout((inv.seconds or 30) * 1000, function() if not closed then lib.closeAlertDialog() end end)
    local res = lib.alertDialog({
        header = 'Top Trumps challenge',
        content = inv.bet > 0 and ('%s challenges you to Top Trumps (best of %d) for **%s** each. The winner takes %s.'):format(inv.name, inv.rounds, money(inv.bet), money(inv.bet * 2))
            or ('%s challenges you to Top Trumps (best of %d), no bet.'):format(inv.name, inv.rounds),
        centered = true, cancel = true, labels = { confirm = 'Play', cancel = 'No thanks' },
    })
    closed = true
    local ok, err = lib.callback.await('as-tradingcards:server:ttAnswer', false, inv.id, res == 'confirm')
    if res == 'confirm' and not ok then lib.notify({ description = err or 'The challenge is no longer open.', type = 'error' }) end
end)

RegisterNetEvent('as-tradingcards:client:ttStart', function(data)
    playing = true
    Nui.Open('ttStart', data)
end)
RegisterNetEvent('as-tradingcards:client:ttRound', function(data) Nui.Send('ttRound', data) end)
RegisterNetEvent('as-tradingcards:client:ttResult', function(data) Nui.Send('ttResult', data) end)
RegisterNetEvent('as-tradingcards:client:ttEnd', function(data)
    playing = false
    Nui.Send('ttEnd', data)
end)

RegisterNUICallback('ttChoose', function(data, cb)
    cb('ok')
    TriggerServerEvent('as-tradingcards:server:ttChoose', data and data.stat)
end)
RegisterNUICallback('ttForfeit', function(_, cb)
    cb('ok')
    if playing then TriggerServerEvent('as-tradingcards:server:ttForfeit') end
end)
