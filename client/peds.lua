local roleOptions = {
    shop   = function() return { label = L('target_shop'), icon = 'fas fa-store', onSelect = OpenShop } end,
    grader = function()
        if not Config.Grading.enabled then return nil end
        return {
            { label = L('target_grade'), icon = 'fas fa-magnifying-glass', onSelect = OpenGrader },
            { label = L('target_collect'), icon = 'fas fa-box-open', onSelect = CollectGrading },
            { label = L('target_stolen'), icon = 'fas fa-user-secret', onSelect = ReportStolen },
        }
    end,
    buyer  = function()
        if not Config.Buyer.enabled then return nil end
        return { label = L('target_sell'), icon = 'fas fa-sterling-sign', onSelect = OpenSell }
    end,
}

local function buildOptions(roles)
    local opts = {}
    for _, role in ipairs(roles) do
        local o = roleOptions[role] and roleOptions[role]()
        if o then
            if o.label then opts[#opts + 1] = o else for _, x in ipairs(o) do opts[#opts + 1] = x end end
        end
    end
    return opts
end

local function spawnPed(cfg)
    local model = lib.requestModel(cfg.model, 10000)
    if not model then return end
    local c = cfg.coords
    local ped = CreatePed(4, model, c.x, c.y, c.z - 1.0, c.w, false, true)
    SetModelAsNoLongerNeeded(model)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)

    if cfg.scenario then
        TaskStartScenarioInPlace(ped, cfg.scenario, 0, true)
    elseif cfg.anim and lib.requestAnimDict(cfg.anim.dict, 5000) then
        TaskPlayAnim(ped, cfg.anim.dict, cfg.anim.clip, 8.0, 0.0, -1, 1, 0, false, false, false)
        RemoveAnimDict(cfg.anim.dict)
    end

    Target.AddEntity(ped, buildOptions(cfg.roles))
    return ped
end

CreateThread(function()
    for _, cfg in ipairs(Config.Peds) do
        if cfg.blip then
            local b = AddBlipForCoord(cfg.coords.x, cfg.coords.y, cfg.coords.z)
            SetBlipSprite(b, cfg.blip.sprite)
            SetBlipColour(b, cfg.blip.colour)
            SetBlipScale(b, cfg.blip.scale)
            SetBlipAsShortRange(b, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(cfg.blip.label)
            EndTextCommandSetBlipName(b)
        end

        local pt
        pt = lib.points.new({
            coords = cfg.coords.xyz,
            distance = Config.PedSpawnDistance,
            onEnter = function(self)
                -- a player is running the shop: the NPC steps back
                if GlobalState.ascardStaffed then return end
                if not self.ped or not DoesEntityExist(self.ped) then
                    self.ped = spawnPed(cfg)
                end
            end,
            nearby = function(self)
                if GlobalState.ascardStaffed and self.ped and DoesEntityExist(self.ped) then
                    Target.RemoveEntity(self.ped)
                    DeleteEntity(self.ped)
                    self.ped = nil
                elseif not GlobalState.ascardStaffed and not self.ped then
                    self.ped = spawnPed(cfg)
                end
            end,
            onExit = function(self)
                if self.ped and DoesEntityExist(self.ped) then
                    Target.RemoveEntity(self.ped)
                    DeleteEntity(self.ped)
                end
                self.ped = nil
            end,
        })
    end
end)
