-- v2 client: deck boxes, binder covers / playmats, gifting, card in hand
--[[ ---------------------------------------------------------------------------
    DECK BOX
--------------------------------------------------------------------------- ]]
RegisterNetEvent('as-tradingcards:client:deckOpen', function(data)
    Nui.Open('deckOpen', data)
    PlayCardAnim(Config.BinderProp and Config.BinderProp.anim, Config.BinderProp and Config.BinderProp.prop)
end)

local function deckCall(name, ...)
    local data, err = lib.callback.await('as-tradingcards:server:' .. name, false, ...)
    if data then return { ok = true, data = data } end
    return { ok = false, error = err or 'Something went wrong.' }
end
RegisterNUICallback('deckAdd', function(d, done) done(deckCall('deckAdd', d and d.slot, d and d.serial)) end)
RegisterNUICallback('deckRemove', function(d, done) done(deckCall('deckRemove', d and d.serial)) end)
RegisterNUICallback('deckClear', function(_, done) done(deckCall('deckClear')) end)
RegisterNUICallback('deckRename', function(d, done) done(deckCall('deckRename', d and d.name)) end)

--[[ ---------------------------------------------------------------------------
    BINDER COVER (from the binder screen)
--------------------------------------------------------------------------- ]]
RegisterNUICallback('binderTheme', function(d, done)
    done(lib.callback.await('as-tradingcards:server:binderTheme', false, d and d.id) or false)
end)

--[[ ---------------------------------------------------------------------------
    COVERS, MATS AND SLAB LABELS SCREEN
--------------------------------------------------------------------------- ]]
local function openSkins()
    local info = lib.callback.await('as-tradingcards:server:skinsInfo', false)
    if info then Nui.Open('skins', info) end
end
RegisterCommand('cardskins', openSkins, false)
function OpenSkins() openSkins() end
RegisterNUICallback('buyCover', function(d, done)
    local ok, err = lib.callback.await('as-tradingcards:server:buyCover', false, d and d.id)
    done({ ok = ok == true, error = err })
end)
RegisterNUICallback('setMat', function(d, done)
    local ok, err = lib.callback.await('as-tradingcards:server:setMat', false, d and d.id)
    done({ ok = ok == true, error = err })
end)

--[[ ---------------------------------------------------------------------------
    GIFTING
--------------------------------------------------------------------------- ]]
local function giftCard(slot, serial)
    local info, err = lib.callback.await('as-tradingcards:server:giftTargets', false)
    if not info then return lib.notify({ description = err or 'Gifting is off.', type = 'error' }) end
    if #info.players == 0 then return lib.notify({ description = 'Nobody else is around to send it to.', type = 'error' }) end
    local options = {}
    for _, p in ipairs(info.players) do options[#options + 1] = { value = p.id, label = p.name } end
    local input = lib.inputDialog('Send as a gift', {
        { type = 'select', label = 'Who is it for?', options = options, required = true, searchable = true },
        { type = 'textarea', label = 'Message (shown on the parcel)', max = info.max, autosize = true },
        { type = 'checkbox', label = 'Don’t show my name' },
    })
    if not input then return end
    if info.fee > 0 then
        local ok = lib.alertDialog({ header = 'Postage', content = ('Sending costs %s.'):format(Utils.Money(info.fee)), centered = true, cancel = true })
        if ok ~= 'confirm' then return end
    end
    local ok, e = lib.callback.await('as-tradingcards:server:giftSend', false, slot, serial, input[1], input[2], input[3] == true)
    if not ok then lib.notify({ description = e or 'Could not send it.', type = 'error' }) end
end
RegisterNUICallback('giftOpen', function(d, done)
    done('ok')
    Nui.Close()
    SetTimeout(150, function() giftCard(d and d.slot, d and d.serial) end)
end)
exports('giftCard', function(slot) if slot then giftCard(slot, nil) end end)

--[[ ---------------------------------------------------------------------------
    CARD IN HAND
--------------------------------------------------------------------------- ]]
local HP = Config.HandProp or {}
local held = { prop = nil, flipped = false }

local function attach(prop, flipped)
    local ped = PlayerPedId()
    local rot = HP.rot or vec3(0, 0, 0)
    local f = flipped and (HP.flipRot or vec3(0, 180, 0)) or vec3(0, 0, 0)
    AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, HP.bone or 28422),
        (HP.pos or vec3(0, 0, 0)).x, (HP.pos or vec3(0, 0, 0)).y, (HP.pos or vec3(0, 0, 0)).z,
        rot.x + f.x, rot.y + f.y, rot.z + f.z, true, true, false, true, 1, true)
end

local function putAway()
    if held.prop and DoesEntityExist(held.prop) then DeleteEntity(held.prop) end
    held.prop, held.flipped = nil, false
    local ped = PlayerPedId()
    local a = HP.anim
    if a and IsEntityPlayingAnim(ped, a.dict, a.clip, 3) then StopAnimTask(ped, a.dict, a.clip, 1.0) end
    lib.hideTextUI()
    TriggerServerEvent('as-tradingcards:server:handStop')
end

RegisterNUICallback('handHold', function(d, done)
    done('ok')
    if d and d.slot then TriggerServerEvent('as-tradingcards:server:handHold', d.slot) end
end)
exports('holdCard', function(slot) if slot then TriggerServerEvent('as-tradingcards:server:handHold', slot) end end)

RegisterNetEvent('as-tradingcards:client:handStart', function()
    if held.prop then putAway() end
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return lib.notify({ description = 'Not in a vehicle.', type = 'error' }) end
    local model = lib.requestModel(HP.model or 'p_ld_id_card_01', 5000)
    if not model then return end
    local c = GetEntityCoords(ped)
    held.prop = CreateObject(model, c.x, c.y, c.z + 0.2, true, true, false)
    SetEntityCollision(held.prop, false, false)
    SetModelAsNoLongerNeeded(model)
    attach(held.prop, false)
    if HP.anim and lib.requestAnimDict(HP.anim.dict, 5000) then
        TaskPlayAnim(ped, HP.anim.dict, HP.anim.clip, 3.0, 3.0, -1, HP.anim.flag or 49, 0, false, false, false)
        RemoveAnimDict(HP.anim.dict)
    end
    local k = HP.keys or {}
    lib.showTextUI('[G] Flip  [H] Show  [X] Put away')
    CreateThread(function()
        while held.prop do
            Wait(0)
            local p = PlayerPedId()
            if IsPedDeadOrDying(p, true) or IsPedInAnyVehicle(p, false) or Nui.open then
                if not Nui.open then putAway() end
            end
            DisableControlAction(0, k.show or 74, true)
            if IsDisabledControlJustReleased(0, k.flip or 47) or IsControlJustReleased(0, k.flip or 47) then
                held.flipped = not held.flipped
                attach(held.prop, held.flipped)
            elseif IsDisabledControlJustReleased(0, k.show or 74) then
                TriggerServerEvent('as-tradingcards:server:handShow')
            elseif IsControlJustReleased(0, k.put or 73) then
                putAway()
            end
        end
    end)
end)

AddEventHandler('onResourceStop', function(r)
    if r ~= GetCurrentResourceName() then return end
    if held.prop and DoesEntityExist(held.prop) then DeleteEntity(held.prop) end
    lib.hideTextUI()
end)

RegisterCommand('cardhand', function() if held.prop then putAway() end end, false)
