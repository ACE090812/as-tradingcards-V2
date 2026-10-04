-- Battle client: placeable tables, table menu, match screen events, leaderboard, tournament prompts
local B = Config.Battle or {}
if not B.enabled then return end
local TB = B.table or {}

local tableData = {}      -- [id] = server row
local spawned = {}        -- [id] = entity
local playing = false

local function money(n) return Utils.Money(n) end

--[[ ---------------------------------------------------------------------------
    TABLE PROPS
--------------------------------------------------------------------------- ]]
local function tableMenu(id)
    local info, err = lib.callback.await('as-tradingcards:server:tableInfo', false, id)
    if not info then return lib.notify({ description = err or 'Get closer to the table.', type = 'error' }) end
    local validDecks = {}
    for _, d in ipairs(info.decks) do
        if d.valid then validDecks[#validDecks + 1] = { value = d.id, label = d.name } end
    end
    local opts = {}

    local function pickDeck(title, extra)
        if #validDecks == 0 then
            lib.notify({ description = 'You need a deck box with exactly 30 cards in it (use the deck box item).', type = 'error' })
            return nil
        end
        local fields = { { type = 'select', label = 'Deck box', options = validDecks, default = validDecks[1].value, required = true } }
        for _, f in ipairs(extra or {}) do fields[#fields + 1] = f end
        return lib.inputDialog(title, fields)
    end

    if info.state == 'free' then
        opts[#opts + 1] = {
            title = 'Open a game here', description = 'Wait for someone to sit across the table', icon = 'fas fa-play',
            onSelect = function()
                local extra = {}
                if info.bets then
                    extra[1] = { type = 'number', label = ('Wager each (0 = just for fun, up to %s)'):format(money(info.bets.max)), default = 0, min = 0, max = info.bets.max }
                end
                local input = pickDeck('Open a battle', extra)
                if not input then return end
                local ok, e = lib.callback.await('as-tradingcards:server:openGame', false, id, input[1], math.floor(tonumber(input[2]) or 0))
                if not ok then lib.notify({ description = e or 'Could not open a game.', type = 'error' }) end
            end,
        }
    elseif info.state == 'waiting' then
        if info.hostIsMe then
            opts[#opts + 1] = {
                title = 'Cancel my open game', icon = 'fas fa-xmark',
                onSelect = function() lib.callback.await('as-tradingcards:server:cancelGame', false, id) lib.notify({ description = 'Game closed.', type = 'inform' }) end,
            }
        else
            opts[#opts + 1] = {
                title = ('Join %s'):format(info.host or 'the game'),
                description = info.bet > 0 and ('Wager %s each. Winner takes %s.'):format(money(info.bet), money(info.bet * 2)) or 'No wager',
                icon = 'fas fa-hand', 
                onSelect = function()
                    local input = pickDeck('Join the battle')
                    if not input then return end
                    local ok, e = lib.callback.await('as-tradingcards:server:joinGame', false, id, input[1])
                    if not ok then lib.notify({ description = e or 'Could not join.', type = 'error' }) end
                end,
            }
        end
    else
        if info.spectate then
            opts[#opts + 1] = {
                title = 'Watch the match', description = info.players and ('%s vs %s'):format(info.players[1], info.players[2]) or nil, icon = 'fas fa-eye',
                onSelect = function()
                    local ok, e = lib.callback.await('as-tradingcards:server:btSpectate', false, id)
                    if not ok then lib.notify({ description = e or 'Could not watch.', type = 'error' }) end
                end,
            }
        else
            opts[#opts + 1] = { title = 'A match is in progress', icon = 'fas fa-clock', disabled = true }
        end
    end

    opts[#opts + 1] = {
        title = 'Leaderboard and rank', description = info.me and ('You are ' .. info.me) or nil, icon = 'fas fa-ranking-star',
        onSelect = function() ExecuteCommand('cardrank') end,
    }
    opts[#opts + 1] = {
        title = 'Choose my playmat', icon = 'fas fa-border-all',
        onSelect = function()
            local options = {}
            for _, m in ipairs(info.mats) do options[#options + 1] = { value = m.id, label = m.label } end
            local input = lib.inputDialog('Playmat', { { type = 'select', label = 'Mat for your side of the table', options = options, default = info.myMat, required = true } })
            if input then lib.callback.await('as-tradingcards:server:setMat', false, input[1]) lib.notify({ description = 'Playmat saved.', type = 'success' }) end
        end,
    }
    if info.canPickup then
        opts[#opts + 1] = {
            title = 'Pick up the table', icon = 'fas fa-hand-holding',
            onSelect = function()
                local ok, e = lib.callback.await('as-tradingcards:server:pickupTable', false, id)
                if not ok then lib.notify({ description = e or 'Could not pick it up.', type = 'error' }) end
            end,
        }
    end
    lib.registerContext({ id = 'ascard_table', title = ('Battle table%s'):format(info.owner and (' · ' .. info.owner) or ''), options = opts })
    lib.showContext('ascard_table')
end

local function spawnTable(t)
    local model = lib.requestModel(TB.model or 'prop_table_03b', 5000)
    if not model then return end
    local e = CreateObjectNoOffset(model, t.x, t.y, t.z + (TB.zOffset or 0.0), false, false, false)
    SetModelAsNoLongerNeeded(model)
    SetEntityHeading(e, t.h + 0.0)
    FreezeEntityPosition(e, true)
    Target.AddEntity(e, {
        { label = 'Card battle table', icon = 'fas fa-clone', onSelect = function() tableMenu(t.id) end },
    })
    return e
end

local function clearTable(id)
    local e = spawned[id]
    if e then
        Target.RemoveEntity(e)
        if DoesEntityExist(e) then DeleteEntity(e) end
    end
    spawned[id] = nil
end

RegisterNetEvent('as-tradingcards:client:tables', function(list)
    local keep = {}
    for _, t in ipairs(list) do keep[t.id] = t tableData[t.id] = t end
    for id in pairs(tableData) do
        if not keep[id] then tableData[id] = nil clearTable(id) end
    end
end)

CreateThread(function()
    local list = lib.callback.await('as-tradingcards:server:getTables', false)
    if list then
        for _, t in ipairs(list) do tableData[t.id] = t end
    end
    while true do
        local pos = GetEntityCoords(PlayerPedId())
        for id, t in pairs(tableData) do
            local d = #(pos - vec3(t.x, t.y, t.z))
            if d < 60.0 and not (spawned[id] and DoesEntityExist(spawned[id])) then
                spawned[id] = spawnTable(t)
            elseif d > 90.0 and spawned[id] then
                clearTable(id)
            end
        end
        Wait(1500)
    end
end)

AddEventHandler('onResourceStop', function(r)
    if r ~= GetCurrentResourceName() then return end
    for id in pairs(spawned) do clearTable(id) end
end)

--[[ ---------------------------------------------------------------------------
    PLACING A TABLE
--------------------------------------------------------------------------- ]]
local placing = false
RegisterNetEvent('as-tradingcards:client:placeTable', function()
    if placing then return end
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return lib.notify({ description = 'Get out of the vehicle first.', type = 'error' }) end
    local model = lib.requestModel(TB.model or 'prop_table_03b', 5000)
    if not model then return end
    placing = true
    local dist, heading = 1.4, GetEntityHeading(ped)
    local ghost = CreateObject(model, 0.0, 0.0, 0.0, false, false, false)
    SetEntityAlpha(ghost, 150, false)
    SetEntityCollision(ghost, false, false)
    FreezeEntityPosition(ghost, true)
    lib.showTextUI('[←/→] Turn  [↑/↓] Move  [ENTER] Place  [BACKSPACE] Cancel')
    local result
    while placing do
        Wait(0)
        DisableControlAction(0, 174, true) DisableControlAction(0, 175, true) DisableControlAction(0, 172, true) DisableControlAction(0, 173, true)
        DisableControlAction(0, 191, true) DisableControlAction(0, 177, true)
        if IsDisabledControlPressed(0, 174) then heading = heading - 1.6 end
        if IsDisabledControlPressed(0, 175) then heading = heading + 1.6 end
        if IsDisabledControlPressed(0, 172) then dist = math.min(3.0, dist + 0.02) end
        if IsDisabledControlPressed(0, 173) then dist = math.max(0.9, dist - 0.02) end
        local p = PlayerPedId()
        local fwd = GetOffsetFromEntityInWorldCoords(p, 0.0, dist, 0.0)
        local found, gz = GetGroundZFor_3dCoord(fwd.x, fwd.y, fwd.z + 1.0, false)
        local z = found and gz or fwd.z - 1.0
        SetEntityCoordsNoOffset(ghost, fwd.x, fwd.y, z + (TB.zOffset or 0.0), false, false, false)
        SetEntityHeading(ghost, heading)
        if IsDisabledControlJustReleased(0, 191) then
            result = { x = fwd.x, y = fwd.y, z = z, h = heading }
            placing = false
        elseif IsDisabledControlJustReleased(0, 177) or IsPedInAnyVehicle(p, false) or IsPedDeadOrDying(p, true) then
            placing = false
        end
    end
    lib.hideTextUI()
    if DoesEntityExist(ghost) then DeleteEntity(ghost) end
    SetModelAsNoLongerNeeded(model)
    if result then
        local a = TB.placeAnim
        if a and lib.requestAnimDict(a.dict, 3000) then TaskPlayAnim(PlayerPedId(), a.dict, a.clip, 3.0, 3.0, 1200, 0, 0, false, false, false) Wait(900) end
        local ok, err = lib.callback.await('as-tradingcards:server:placeTable', false, result.x, result.y, result.z, result.h)
        if not ok then lib.notify({ description = err or 'Could not put the table down.', type = 'error' }) end
    end
end)

--[[ ---------------------------------------------------------------------------
    MATCH SCREEN (NUI) EVENTS
--------------------------------------------------------------------------- ]]
local frozen = false
local function freeze(on)
    frozen = on
    FreezeEntityPosition(PlayerPedId(), on)
end

RegisterNetEvent('as-tradingcards:client:btStart', function(d)
    if Nui.open and not playing then Nui.Close() end
    playing = true
    if not d.watch then freeze(true) end
    Nui.Open('btStart', d)
end)
RegisterNetEvent('as-tradingcards:client:btTurn', function(d) Nui.Send('btTurn', d) end)
RegisterNetEvent('as-tradingcards:client:btPicked', function(d) Nui.Send('btPicked', d) end)
RegisterNetEvent('as-tradingcards:client:btReveal', function(d) Nui.Send('btReveal', d) end)
RegisterNetEvent('as-tradingcards:client:btEnd', function(d)
    freeze(false)
    Nui.Send('btEnd', d)
end)

RegisterNUICallback('btPick', function(d, done)
    done('ok')
    TriggerServerEvent('as-tradingcards:server:btPick', d and d.uid)
end)
RegisterNUICallback('btForfeit', function(_, done)
    done('ok')
    TriggerServerEvent('as-tradingcards:server:btForfeit')
end)
RegisterNUICallback('btUnwatch', function(_, done)
    done('ok')
    TriggerServerEvent('as-tradingcards:server:btUnspectate')
end)
RegisterNUICallback('btDone', function(_, done)
    done('ok')
    playing = false
    freeze(false)
    Nui.Close()
end)

AddEventHandler('onResourceStop', function(r)
    if r == GetCurrentResourceName() and frozen then FreezeEntityPosition(PlayerPedId(), false) end
end)

--[[ ---------------------------------------------------------------------------
    LEADERBOARD
--------------------------------------------------------------------------- ]]
RegisterCommand('cardrank', function()
    local d = lib.callback.await('as-tradingcards:server:btBoard', false)
    if d then Nui.Open('btBoard', d) end
end, false)
RegisterNUICallback('btJoinTourney', function(_, done)
    local ok, err = lib.callback.await('as-tradingcards:server:tourneyJoin', false)
    if not ok then lib.notify({ description = err or 'Could not join.', type = 'error' }) end
    done({ ok = ok == true, error = err })
end)

--[[ ---------------------------------------------------------------------------
    TOURNAMENTS
--------------------------------------------------------------------------- ]]
RegisterNetEvent('as-tradingcards:client:tourneyJoinCmd', function()
    local ok, err = lib.callback.await('as-tradingcards:server:tourneyJoin', false)
    lib.notify({ description = ok and 'You’re in the tournament.' or (err or 'Could not join.'), type = ok and 'success' or 'error' })
end)

RegisterNetEvent('as-tradingcards:client:tourneyReady', function(d)
    local valid = {}
    for _, dk in ipairs(d.decks or {}) do if dk.valid then valid[#valid + 1] = { value = dk.id, label = dk.name } end end
    if #valid == 0 then return lib.notify({ description = 'Your match is ready but you have no valid deck box on you.', type = 'error' }) end
    local deck = valid[1].value
    local closed = false
    SetTimeout((d.seconds or 90) * 1000, function() if not closed then lib.closeAlertDialog() lib.closeInputDialog() end end)
    if #valid > 1 then
        local input = lib.inputDialog(('%s: match vs %s'):format(d.tourney, d.opponent), { { type = 'select', label = 'Which deck box?', options = valid, default = deck, required = true } })
        if not input then closed = true return end
        deck = input[1]
    else
        local r = lib.alertDialog({ header = d.tourney, content = ('Your match against **%s** is ready. Accept to start now. You have %d seconds or you forfeit.'):format(d.opponent, d.seconds or 90), centered = true, cancel = true, labels = { confirm = 'Play', cancel = 'Forfeit' } })
        if r ~= 'confirm' then closed = true return end
    end
    closed = true
    local ok, err = lib.callback.await('as-tradingcards:server:tourneyAccept', false, d.key, deck)
    if not ok then lib.notify({ description = err or 'Could not accept.', type = 'error' }) end
end)

RegisterNetEvent('as-tradingcards:client:tourneyAdmin', function()
    local function show()
        local st = lib.callback.await('as-tradingcards:server:tourneyAdmin', false, 'status')
        local opts = {}
        if st then
            opts[#opts + 1] = { title = ('%s: %s'):format(st.name, st.state), description = ('%d / %d players%s'):format(#st.players, st.size, st.champion and (' · champion ' .. st.champion) or ''), icon = 'fas fa-trophy', readOnly = true }
            for _, n in ipairs(st.players) do opts[#opts + 1] = { title = n, icon = 'fas fa-user', readOnly = true } end
            if st.state == 'open' then
                opts[#opts + 1] = { title = 'Start the tournament', icon = 'fas fa-play', onSelect = function()
                    local _, err = lib.callback.await('as-tradingcards:server:tourneyAdmin', false, 'start')
                    if err then lib.notify({ description = err, type = 'error' }) end
                    show()
                end }
            end
            opts[#opts + 1] = { title = st.state == 'done' and 'Clear it' or 'Cancel the tournament', icon = 'fas fa-xmark', onSelect = function()
                lib.callback.await('as-tradingcards:server:tourneyAdmin', false, 'cancel')
                show()
            end }
        end
        if not st or st.state == 'done' then
            opts[#opts + 1] = { title = 'Create a tournament', icon = 'fas fa-plus', onSelect = function()
                local sizes = {}
                for _, s in ipairs(Config.Tournament.sizes or { 4, 8, 16 }) do sizes[#sizes + 1] = { value = s, label = s .. ' players' } end
                local input = lib.inputDialog('New tournament', {
                    { type = 'input', label = 'Name', default = 'Card Battle Cup', required = true, max = 40 },
                    { type = 'select', label = 'Size', options = sizes, default = sizes[2] and sizes[2].value or sizes[1].value, required = true },
                })
                if not input then return end
                local r, err = lib.callback.await('as-tradingcards:server:tourneyAdmin', false, 'create', { name = input[1], size = input[2] })
                if not r then lib.notify({ description = err or 'Could not create it.', type = 'error' }) end
                show()
            end }
        end
        lib.registerContext({ id = 'ascard_tourney', title = 'Card tournament', options = opts })
        lib.showContext('ascard_tourney')
    end
    show()
end)
