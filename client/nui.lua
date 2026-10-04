Nui = { open = false }

local prop

function Nui.Open(action, data)
    Nui.open = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = action, data = data, cardBack = Config.CardBack, cardBacks = Config.CardBacks, photoUrl = Config.PhotoUrl or '', sounds = Config.Sounds })
end

function Nui.Send(action, data)
    SendNUIMessage({ action = action, data = data, cardBack = Config.CardBack, cardBacks = Config.CardBacks, photoUrl = Config.PhotoUrl or '', sounds = Config.Sounds })
end

function Nui.Close()
    Nui.open = false
    if FlushPackCards then FlushPackCards() end
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    StopCardAnim()
end

--[[ ---------------------------------------------------------------------------
    ANIM + PROP
--------------------------------------------------------------------------- ]]
local currentAnim

function PlayCardAnim(anim, propCfg)
    StopCardAnim()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return end

    if propCfg and propCfg.model then
        local model = lib.requestModel(propCfg.model, 5000)
        if model then
            local c = GetEntityCoords(ped)
            prop = CreateObject(model, c.x, c.y, c.z + 0.2, true, true, false)
            SetEntityCollision(prop, false, false)
            AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, propCfg.bone),
                propCfg.pos.x, propCfg.pos.y, propCfg.pos.z, propCfg.rot.x, propCfg.rot.y, propCfg.rot.z,
                true, true, false, true, 1, true)
            SetModelAsNoLongerNeeded(model)
        end
    end

    if anim and anim.dict then
        if lib.requestAnimDict(anim.dict, 5000) then
            TaskPlayAnim(ped, anim.dict, anim.clip, 3.0, 3.0, -1, anim.flag or 49, 0, false, false, false)
            RemoveAnimDict(anim.dict)
            currentAnim = anim
        end
    end
end

function StopCardAnim()
    if prop and DoesEntityExist(prop) then
        DeleteEntity(prop)
    end
    prop = nil
    local ped = PlayerPedId()
    local a = currentAnim
    if a and IsEntityPlayingAnim(ped, a.dict, a.clip, 3) then
        StopAnimTask(ped, a.dict, a.clip, 1.0)
    end
    currentAnim = nil
end

--[[ ---------------------------------------------------------------------------
    NUI CALLBACKS
--------------------------------------------------------------------------- ]]
RegisterNUICallback('close', function(_, cb)
    Nui.Close()
    cb('ok')
end)

-- pack top torn off in the rip screen: put the pack prop away
RegisterNUICallback('ripped', function(_, cb)
    StopCardAnim()
    cb('ok')
end)

RegisterNUICallback('sound', function(data, cb)
    if type(data) == 'table' and type(data.name) == 'string' and type(data.set) == 'string' then
        PlaySoundFrontend(-1, data.name, data.set, true)
    end
    cb('ok')
end)

RegisterNUICallback('show', function(data, cb)
    if data and data.slot then
        TriggerServerEvent('as-tradingcards:server:showCard', data.slot)
    end
    cb('ok')
end)

RegisterNUICallback('binderInsert', function(data, cb)
    local result = lib.callback.await('as-tradingcards:server:binderInsert', false, data and data.slot, data and data.serial, data and data.target)
    cb(result or false)
end)

RegisterNUICallback('binderRemove', function(data, cb)
    local result = lib.callback.await('as-tradingcards:server:binderRemove', false, data and data.sleeve)
    cb(result or false)
end)

RegisterNUICallback('binderMove', function(data, cb)
    local result = lib.callback.await('as-tradingcards:server:binderMove', false, data and data.from, data and data.to)
    cb(result or false)
end)

RegisterNUICallback('crack', function(data, cb)
    local ok = lib.callback.await('as-tradingcards:server:crackSlab', false, data and data.slot, data and data.serial)
    cb(ok or false)
    if ok then Nui.Close() end
end)

RegisterNUICallback('protect', function(data, cb)
    local result = lib.callback.await('as-tradingcards:server:protect', false, data and data.slot, data and data.serial, data and data.action)
    cb(result or false)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if Nui.open then SetNuiFocus(false, false) end
    StopCardAnim()
end)
