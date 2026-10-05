-- Client-side target bridge: as-interact / ox_target / qb-target / ox_lib textui fallback
Target = { name = nil }

local function started(res) return GetResourceState(res) == 'started' end

do
    local cfg = Config.Target
    if cfg == 'interact' or (cfg == 'auto' and started('as-interact')) then
        Target.name = 'interact'
    elseif cfg == 'ox' or (cfg == 'auto' and started('ox_target')) then
        Target.name = 'ox'
    elseif cfg == 'qb' or (cfg == 'auto' and started('qb-target')) then
        Target.name = 'qb'
    else
        Target.name = 'textui'
    end
end

-- as-interact id bookkeeping: its Add* exports return an id used to remove/update later, but
-- AddEntity/RemoveEntity below are called by entity handle (same shape ox_target/qb-target
-- expect), so we keep our own entity -> id map for that backend.
local interactIds = {}

-- textui registry: entity -> options
local textEntities = {}
local textShown = false
local activeEntity

-- options: { { label, icon, onSelect } }
function Target.AddEntity(entity, options)
    if Target.name == 'interact' then
        local opts = {}
        for i, o in ipairs(options) do
            opts[i] = {
                name = ('ascard_%d_%d'):format(entity, i),
                label = o.label,
                action = function() o.onSelect() end,
            }
        end
        interactIds[entity] = exports['as-interact']:AddLocalEntityInteraction({
            entity = entity,
            distance = Config.InteractDistance,
            interactDst = Config.InteractDistance,
            options = opts,
        })
    elseif Target.name == 'ox' then
        local opts = {}
        for i, o in ipairs(options) do
            opts[i] = {
                name = ('ascard_%d_%d'):format(entity, i),
                label = o.label, icon = o.icon,
                distance = Config.InteractDistance,
                onSelect = function() o.onSelect() end,
            }
        end
        exports.ox_target:addLocalEntity(entity, opts)
    elseif Target.name == 'qb' then
        local opts = {}
        for i, o in ipairs(options) do
            opts[i] = { label = o.label, icon = o.icon, action = function() o.onSelect() end }
        end
        exports['qb-target']:AddTargetEntity(entity, { options = opts, distance = Config.InteractDistance })
    else
        textEntities[entity] = options
    end
end

function Target.RemoveEntity(entity)
    if Target.name == 'interact' then
        local id = interactIds[entity]
        if id then
            exports['as-interact']:RemoveInteraction(id)
            interactIds[entity] = nil
        else
            exports['as-interact']:RemoveInteractionByEntity(entity)
        end
    elseif Target.name == 'ox' then
        exports.ox_target:removeLocalEntity(entity)
    elseif Target.name == 'qb' then
        exports['qb-target']:RemoveTargetEntity(entity)
    else
        textEntities[entity] = nil
        if activeEntity == entity then
            lib.hideTextUI()
            textShown, activeEntity = false, nil
        end
    end
end

-- a spot in the world (no entity): as-interact point / ox_target sphere / qb-target circle / textui point
local textPoints = {}
function Target.AddPoint(id, coords, radius, options)
    if Target.name == 'interact' then
        local opts = {}
        for i, o in ipairs(options) do
            opts[i] = { name = ('%s_%d'):format(id, i), label = o.label, action = function() o.onSelect() end }
        end
        -- as-interact has no separate radius/zone concept - distance/interactDst already define
        -- how close the player must be, so radius maps onto interactDst (matches the sphere's size).
        return exports['as-interact']:AddInteraction({
            coords = coords,
            distance = Config.InteractDistance + 0.5,
            interactDst = radius,
            name = id,
            options = opts,
        })
    elseif Target.name == 'ox' then
        local opts = {}
        for i, o in ipairs(options) do
            opts[i] = { name = ('%s_%d'):format(id, i), label = o.label, icon = o.icon, distance = Config.InteractDistance + 0.5, onSelect = function() o.onSelect() end }
        end
        return exports.ox_target:addSphereZone({ coords = coords, radius = radius, debug = false, options = opts })
    elseif Target.name == 'qb' then
        local opts = {}
        for i, o in ipairs(options) do opts[i] = { label = o.label, icon = o.icon, action = function() o.onSelect() end } end
        exports['qb-target']:AddCircleZone(id, coords, radius, { name = id, debugPoly = false, useZ = true }, { options = opts, distance = Config.InteractDistance + 0.5 })
        return id
    else
        textPoints[id] = { coords = coords, radius = radius, options = options }
        return id
    end
end

function Target.RemovePoint(zone)
    if not zone then return end
    if Target.name == 'interact' then exports['as-interact']:RemoveInteraction(zone)
    elseif Target.name == 'ox' then exports.ox_target:removeZone(zone)
    elseif Target.name == 'qb' then exports['qb-target']:RemoveZone(zone)
    else textPoints[zone] = nil end
end

local function openTextMenu(options)
    if #options == 1 then return options[1].onSelect() end
    local menu = {}
    for i, o in ipairs(options) do
        menu[i] = { title = o.label, icon = o.icon, onSelect = o.onSelect }
    end
    lib.registerContext({ id = 'ascard_ped_menu', title = Config.Shop.label, options = menu })
    lib.showContext('ascard_ped_menu')
end

if Target.name == 'textui' then
    CreateThread(function()
        while true do
            local sleep = 750
            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)
            local nearest, nearestDist

            for entity in pairs(textEntities) do
                if DoesEntityExist(entity) then
                    local d = #(pos - GetEntityCoords(entity))
                    if d <= Config.InteractDistance and (not nearestDist or d < nearestDist) then
                        nearest, nearestDist = entity, d
                    end
                end
            end

            local nearOpts
            if nearest then nearOpts = textEntities[nearest] end
            if not nearOpts then
                for _, p in pairs(textPoints) do
                    if #(pos - p.coords) <= p.radius + Config.InteractDistance then nearOpts = p.options nearest = p break end
                end
            end
            if nearest then
                sleep = 0
                if not textShown or activeEntity ~= nearest then
                    local opts = nearOpts
                    lib.showTextUI(L('textui', #opts == 1 and opts[1].label or Config.Shop.label))
                    textShown, activeEntity = true, nearest
                end
                if IsControlJustReleased(0, 38) then
                    openTextMenu(nearOpts)
                end
            elseif textShown then
                lib.hideTextUI()
                textShown, activeEntity = false, nil
            end

            Wait(sleep)
        end
    end)
end
