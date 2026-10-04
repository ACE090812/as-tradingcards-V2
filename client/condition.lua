--[[ Card condition (client): water checks, the cleaning bench, and the card on the table
     The card on the mat is a real prop (pokemon_card) whose front texture is replaced by a DUI
     that draws our card + its dirt. The NUI is a see-through layer that turns mouse movement
     into wipes on the card, which are sent on to the DUI so you watch the dirt come off in-world. ]]
if not (Config.Condition and Config.Condition.enabled) then return end

local CC = Config.Condition
local RES = GetCurrentResourceName()

--[[ ---------------------------------------------------------------------------
    WATER: swimming / heavy rain with loose cards on you
--------------------------------------------------------------------------- ]]
CreateThread(function()
    while true do
        Wait(CC.wear.waterCheck * 1000)
        local ped = PlayerPedId()
        if IsPedSwimming(ped) or IsPedSwimmingUnderWater(ped) then
            TriggerServerEvent('as-tradingcards:server:wet', 'swim')
        elseif GetRainLevel() > 0.5 and not IsPedInAnyVehicle(ped, false) and GetInteriorFromEntity(ped) == 0 then
            TriggerServerEvent('as-tradingcards:server:wet', 'rain')
        end
    end
end)

--[[ ---------------------------------------------------------------------------
    BENCH PROPS + TARGET
--------------------------------------------------------------------------- ]]
local function firstModel(list)
    for _, name in ipairs(list or {}) do
        local hash = joaat(name)
        if IsModelInCdimage(hash) then return hash end
    end
end

-- where things sit on a bench: coords = where the player stands, facing the desk
local benchTop = {}   -- measured table-top height per bench (from the desk model)

local function benchLayout(b, index)
    local c = b.coords
    local h = math.rad(c.w)
    local fwd = vec3(-math.sin(h), math.cos(h), 0.0)
    local right = vec3(math.cos(h), math.sin(h), 0.0)
    local ground = c.z - 1.0
    local deskPos = vec3(c.x, c.y, ground) + fwd * 0.62
    local top = (index and benchTop[index]) or (ground + CC.deskHeight)
    return {
        heading = c.w, fwd = fwd, right = right,
        desk = deskPos,
        mat = vec3(deskPos.x, deskPos.y, top) - fwd * 0.08,
        lamp = vec3(deskPos.x, deskPos.y, top) + fwd * 0.18 + right * 0.32,
        card = vec3(deskPos.x, deskPos.y, top + (CC.cardLift or 0.008)) - fwd * 0.08,
        stand = vec3(c.x, c.y, c.z),
    }
end

local function spawnLocal(model, pos, heading)
    if not model then return nil end
    if not lib.requestModel(model, 5000) then return nil end
    local obj = CreateObjectNoOffset(model, pos.x, pos.y, pos.z, false, false, false)
    SetEntityHeading(obj, heading)
    FreezeEntityPosition(obj, true)
    SetModelAsNoLongerNeeded(model)
    return obj
end

local startCleaning

for index, b in ipairs(CC.benches) do
    local lay = benchLayout(b)
    lib.points.new({
        coords = lay.desk,
        distance = 40.0,
        onEnter = function(self)
            self.props = {}
            if b.desk then
                local model = firstModel(CC.deskModels)
                if not model then print('^3[as-tradingcards] none of Config.Condition.deskModels exist on this game build^0') end
                local d = spawnLocal(model, lay.desk, lay.heading)
                if d then
                    PlaceObjectOnGroundProperly(d)
                    self.props[#self.props + 1] = d
                    -- measure the real table top so the mat, lamp and card sit on it
                    local _, max = GetModelDimensions(model)
                    benchTop[index] = GetEntityCoords(d).z + max.z
                end
            end
            local l2 = benchLayout(b, index)
            local m = spawnLocal(firstModel(CC.matModels), l2.mat, l2.heading)
            if m then self.props[#self.props + 1] = m end
            local l = spawnLocal(firstModel(CC.lampModels), l2.lamp, l2.heading + 200.0)
            if l then self.props[#self.props + 1] = l end
            self.zone = Target.AddPoint(('ascard_bench_%d'):format(index), vec3(l2.desk.x, l2.desk.y, l2.mat.z), 0.8, {
                { label = L('target_clean'), icon = 'fas fa-hand-sparkles', onSelect = function() startCleaning(index) end },
            })
        end,
        onExit = function(self)
            Target.RemovePoint(self.zone)
            for _, p in ipairs(self.props or {}) do if DoesEntityExist(p) then DeleteEntity(p) end end
            self.props, self.zone = nil, nil
        end,
    })
end

--[[ ---------------------------------------------------------------------------
    CLEANING SESSION
--------------------------------------------------------------------------- ]]
local S = nil      -- active session

local function placeCamera()
    local c = S.lay.card
    SetCamCoord(S.cam, c.x, c.y, c.z + S.camHeight)
    SetCamRot(S.cam, -89.9, 0.0, S.lay.heading, 2)
end

local function endSession()
    if not S then return end
    local s = S
    S = nil
    RenderScriptCams(false, true, 500, true, false)
    if s.cam then DestroyCam(s.cam, false) end
    local ped = PlayerPedId()
    StopAnimTask(ped, CC.anim.dict, CC.anim.clip, 1.0)
    FreezeEntityPosition(ped, false)
    Nui.Close()
end

function startCleaning(bench)
    if S or Nui.open then return end
    local list = lib.callback.await('as-tradingcards:server:cleanList', false, bench)
    if not list then return end
    if #list.cards == 0 then return lib.notify({ description = L('nothing_to_clean'), type = 'error' }) end

    local options = {}
    for _, c in ipairs(list.cards) do
        options[#options + 1] = {
            title = c.title,
            description = c.prot and (c.glance .. ' · take it out of its sleeve first') or c.glance,
            icon = 'fas fa-hand-sparkles',
            disabled = c.prot ~= nil,
            onSelect = function() CreateThread(function() BeginClean(bench, c) end) end,
        }
    end
    lib.registerContext({ id = 'ascard_clean', title = L('clean_pick'), options = options })
    lib.showContext('ascard_clean')
end

local function beginClean(bench, entry)
    if S then return end
    local res = lib.callback.await('as-tradingcards:server:cleanStart', false, bench, entry.slot, entry.serial)
    if not res then return end
    local b = CC.benches[bench]
    local lay = benchLayout(b, bench)
    local ped = PlayerPedId()

    S = { bench = bench, lay = lay, flipped = false, camHeight = CC.camera.height }

    -- stand at the bench, lean over the desk
    SetEntityCoords(ped, lay.stand.x, lay.stand.y, lay.stand.z - 1.0, false, false, false, false)
    SetEntityHeading(ped, lay.heading)
    FreezeEntityPosition(ped, true)
    if lib.requestAnimDict(CC.anim.dict, 3000) then
        TaskPlayAnim(ped, CC.anim.dict, CC.anim.clip, 3.0, 3.0, -1, 1, 0, false, false, false)
        RemoveAnimDict(CC.anim.dict)
    end

    -- camera looks down at the mat; the card itself is drawn in 3D by the NUI on top of it
    S.cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', lay.card.x, lay.card.y, lay.card.z + S.camHeight, -89.9, 0.0, lay.heading, CC.camera.fov, false, 2)
    placeCamera()
    SetCamActive(S.cam, true)
    RenderScriptCams(true, true, 700, true, false)

    Nui.Open('cleanStart', { card = res.card, tools = res.tools, loupe = res.loupe })

    CreateThread(function()
        while S do
            DisableAllControlActions(0)
            SetEntityLocallyInvisible(PlayerPedId())
            Wait(0)
        end
    end)
end

function BeginClean(bench, entry)
    local ok, err = pcall(beginClean, bench, entry)
    if not ok then
        print(('^1[as-tradingcards] cleaning failed: %s^0'):format(tostring(err)))
        lib.callback.await('as-tradingcards:server:cleanCancel', false)
        endSession()
        lib.notify({ description = 'Cleaning failed - check F8', type = 'error' })
    end
end

RegisterNUICallback('cleanDone', function(data, cb)
    cb('ok')
    if not S then return end
    lib.callback.await('as-tradingcards:server:cleanFinish', false, data and data.result or {})
    endSession()
end)

RegisterNUICallback('cleanCancel', function(_, cb)
    cb('ok')
    if not S then return end
    lib.callback.await('as-tradingcards:server:cleanCancel', false)
    endSession()
end)

AddEventHandler('onResourceStop', function(res)
    if res == RES and S then endSession() end
end)

-- helper for setting up benches: prints where you stand, facing the way you face
RegisterCommand('cardbenchpos', function()
    local ped = PlayerPedId()
    local c, h = GetEntityCoords(ped), GetEntityHeading(ped)
    local text = ('vec4(%.2f, %.2f, %.2f, %.1f)'):format(c.x, c.y, c.z, h)
    print('[as-tradingcards] bench coords: ' .. text)
    lib.setClipboard(text)
    lib.notify({ description = 'Bench position copied: ' .. text, type = 'inform' })
end, false)
