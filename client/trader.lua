-- NPC trader + collector desk (client): ped, blip, screen
local TC = Config.Trader or {}
if not TC.enabled then return end

local ped, blip
local function coords()
    local c = (TC.ped or {}).coords
    if not c or (c.x == 0.0 and c.y == 0.0 and c.z == 0.0) then return nil end
    return c
end

local function openTrader()
    local info, err = lib.callback.await('as-tradingcards:server:traderInfo', false)
    if not info then return lib.notify({ description = err or 'The trader isn’t here right now.', type = 'error' }) end
    Nui.Open('trader', info)
end

local function despawn()
    if ped and DoesEntityExist(ped) then Target.RemoveEntity(ped) DeleteEntity(ped) end
    ped = nil
end

CreateThread(function()
    local c = coords()
    if not c then return end
    while true do
        local on = GlobalState.ascardTraderOn == true
        local near = #(GetEntityCoords(PlayerPedId()) - vec3(c.x, c.y, c.z)) < (Config.PedSpawnDistance or 40.0)
        if on and near and not (ped and DoesEntityExist(ped)) then
            local model = lib.requestModel(TC.ped.model, 10000)
            if model then
                ped = CreatePed(4, model, c.x, c.y, c.z - 1.0, c.w, false, true)
                SetModelAsNoLongerNeeded(model)
                FreezeEntityPosition(ped, true)
                SetEntityInvincible(ped, true)
                SetBlockingOfNonTemporaryEvents(ped, true)
                if TC.ped.scenario then TaskStartScenarioInPlace(ped, TC.ped.scenario, 0, true) end
                Target.AddEntity(ped, { { label = 'Talk to the card trader', icon = 'fas fa-right-left', onSelect = openTrader } })
            end
        elseif (not on or not near) and ped then
            despawn()
        end
        local b = TC.ped.blip
        if b and on and not blip then
            blip = AddBlipForCoord(c.x, c.y, c.z)
            SetBlipSprite(blip, b.sprite) SetBlipColour(blip, b.colour) SetBlipScale(blip, b.scale) SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING') AddTextComponentSubstringPlayerName(b.label) EndTextCommandSetBlipName(blip)
        elseif blip and not on then
            RemoveBlip(blip) blip = nil
        end
        Wait(3000)
    end
end)

AddEventHandler('onResourceStop', function(r)
    if r ~= GetCurrentResourceName() then return end
    despawn()
    if blip then RemoveBlip(blip) end
end)

RegisterNUICallback('traderRefresh', function(_, done)
    local info, err = lib.callback.await('as-tradingcards:server:traderInfo', false)
    done(info and { ok = true, data = info } or { ok = false, error = err })
end)
RegisterNUICallback('traderSwap', function(d, done)
    local r, err = lib.callback.await('as-tradingcards:server:traderSwap', false, d and d.kind, d and d.payload)
    done(r and { ok = true, data = r } or { ok = false, error = err })
end)
RegisterNUICallback('wantHand', function(d, done)
    local r, err = lib.callback.await('as-tradingcards:server:wantHand', false, d and d.id, d and d.serials)
    done(r and { ok = true, data = r } or { ok = false, error = err })
end)
