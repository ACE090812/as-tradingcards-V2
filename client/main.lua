--[[ ---------------------------------------------------------------------------
    PACK OPENING
--------------------------------------------------------------------------- ]]
lib.callback.register('as-tradingcards:client:packProgress', function(label)
    if Nui.open or lib.progressActive() then return false end
    local po = Config.PackOpening
    local ok = lib.progressCircle({
        duration = po.duration,
        label = L('opening_pack', label),
        position = 'bottom',
        useWhileDead = false,
        canCancel = true,
        disable = { combat = true, car = false, move = false },
        anim = po.anim and { dict = po.anim.dict, clip = po.anim.clip, flag = po.anim.flag } or nil,
        prop = po.prop and { model = po.prop.model, bone = po.prop.bone, pos = po.prop.pos, rot = po.prop.rot } or nil,
    })
    if not ok then lib.notify({ description = L('cancelled'), type = 'error' }) end
    return ok
end)

local packToken = nil
RegisterNetEvent('as-tradingcards:client:openPack', function(data)
    if packToken then TriggerServerEvent('as-tradingcards:server:packDone', packToken) end
    packToken = data and data.token or nil
    Nui.Open('openPack', data)
    -- keep the pack in hand until it's ripped open on screen
    PlayCardAnim(Config.PackOpening.anim, Config.PackOpening.prop)
end)

--[[ ---------------------------------------------------------------------------
    BOOSTER BOX
--------------------------------------------------------------------------- ]]
lib.callback.register('as-tradingcards:client:boxProgress', function(label, duration)
    if Nui.open or lib.progressActive() then return false end
    local bx = Config.BoosterBox
    if Config.Sounds.enabled and Config.Sounds.box then
        Nui.Send('sfx', { name = Config.Sounds.box })
    end
    local ok = lib.progressCircle({
        duration = duration or bx.duration,
        label = L('opening_box', label),
        position = 'bottom',
        useWhileDead = false,
        canCancel = true,
        disable = { combat = true, car = false, move = false },
        anim = bx.anim and { dict = bx.anim.dict, clip = bx.anim.clip, flag = bx.anim.flag } or nil,
        prop = bx.prop and { model = bx.prop.model, bone = bx.prop.bone, pos = bx.prop.pos, rot = bx.prop.rot } or nil,
    })
    if not ok then lib.notify({ description = L('cancelled'), type = 'error' }) end
    return ok
end)

--[[ ---------------------------------------------------------------------------
    VIEW / SHOW
--------------------------------------------------------------------------- ]]
RegisterNetEvent('as-tradingcards:client:viewCard', function(card, slot, canShow, tools)
    Nui.Open('viewCard', { card = card, slot = slot, canShow = canShow and slot ~= nil, tools = tools, v2 = slot and { hand = (Config.HandProp or {}).enabled, gift = (Config.Gift or {}).enabled } or nil })
    PlayCardAnim(Config.Show.anim, Config.Show.prop)
end)

RegisterNetEvent('as-tradingcards:client:peekCard', function(card, fromName, duration)
    lib.notify({ description = L('showing_you', fromName), type = 'inform' })
    if Nui.open then return end -- don't cover whatever they have open
    Nui.Send('peekCard', { card = card, from = fromName, duration = duration })
end)

--[[ ---------------------------------------------------------------------------
    BINDER
--------------------------------------------------------------------------- ]]
RegisterNetEvent('as-tradingcards:client:openBinder', function(data)
    local wasOpen = Nui.open
    Nui.Open('binder', data)
    if not wasOpen then PlayCardAnim(Config.BinderProp.anim, Config.BinderProp.prop) end
end)

--[[ ---------------------------------------------------------------------------
    PED MENUS
--------------------------------------------------------------------------- ]]
function OpenShop()
    local items, nextRestock = lib.callback.await('as-tradingcards:server:getShop', false)
    if not items then return end
    local options = {}
    if Config.Repacks and Config.Repacks.enabled then
        options[#options + 1] = {
            title = 'Repacks', description = 'Mystery packs made from cards other players sold to the shop', icon = 'fas fa-box-open', arrow = true,
            onSelect = function() OpenRepacks() end,
        }
    end
    for i, entry in ipairs(items) do
        local desc = ('%s each'):format(Utils.Money(entry.price))
        if entry.left ~= nil then
            desc = entry.left > 0 and ('%s · %d left this week'):format(desc, entry.left) or (desc .. ' · SOLD OUT until the restock')
        end
        options[#options + 1] = {
            title = entry.label,
            description = desc,
            disabled = entry.left == 0,
            icon = 'fas fa-layer-group',
            onSelect = function()
                local input = lib.inputDialog(entry.label, {
                    { type = 'number', label = L('menu_amount'), default = 1, min = 1, max = Config.Shop.maxPerPurchase, required = true },
                })
                if input and input[1] then
                    lib.callback.await('as-tradingcards:server:buy', false, i, input[1])
                end
            end,
        }
    end
    lib.registerContext({ id = 'ascard_shop', title = L('menu_shop'), options = options })
    lib.showContext('ascard_shop')
end

function OpenGrader()
    local data = lib.callback.await('as-tradingcards:server:getGradable', false)
    if not data then return end
    if #data.cards == 0 then
        return lib.notify({ description = L('nothing_to_grade'), type = 'error' })
    end
    local options = {}
    for _, c in ipairs(data.cards) do
        options[#options + 1] = {
            title = c.title,
            description = c.rarity .. (c.serial and (' | ' .. c.serial) or ''),
            icon = 'fas fa-magnifying-glass',
            onSelect = function()
                local opts = {}
                for _, t in ipairs(data.tiers or {}) do
                    opts[#opts + 1] = {
                        title = ('%s - £%d'):format(t.label, t.fee),
                        description = ('Ready in %s%s'):format(t.time, data.requireCase and ' · uses a grading case' or ''),
                        icon = t.id == 'express' and 'fas fa-bolt' or t.id == 'economy' and 'fas fa-hourglass-half' or 'fas fa-clock',
                        onSelect = function()
                            lib.callback.await('as-tradingcards:server:submitGrading', false, c.slot, c.serial, t.id)
                        end,
                    }
                end
                lib.registerContext({ id = 'ascard_grade_tier', title = c.title, menu = 'ascard_grade', options = opts })
                lib.showContext('ascard_grade_tier')
            end,
        }
    end
    lib.registerContext({ id = 'ascard_grade', title = L('menu_grade'), options = options })
    lib.showContext('ascard_grade')
end

function CollectGrading()
    local res = lib.callback.await('as-tradingcards:server:collectGrading', false)
    if type(res) == 'table' and res.reveal and #res.reveal > 0 then
        Nui.Open('gradeReveal', { slabs = res.reveal })
    end
end

--[[ ---------------------------------------------------------------------------
    PACK SCALE
--------------------------------------------------------------------------- ]]
local function weighMenu()
    local list = lib.callback.await('as-tradingcards:server:scaleList', false)
    if not list then return end
    if #list == 0 then return lib.notify({ description = 'You have no sealed packs to weigh.', type = 'error' }) end
    local options = {}
    for _, p in ipairs(list) do
        options[#options + 1] = {
            title = p.label .. (p.count > 1 and (' x' .. p.count) or ''),
            description = p.seal and ('Seal #%s'):format(p.seal) or nil,
            icon = 'fas fa-weight-scale',
            onSelect = function()
                if lib.progressCircle({ duration = (Config.Scale and Config.Scale.time) or 1500, label = 'Weighing...', position = 'bottom', canCancel = true, disable = { move = true, combat = true } }) then
                    local r = lib.callback.await('as-tradingcards:server:weigh', false, p.slot)
                    if r then
                        lib.notify({ title = 'Pack scale', description = ('%s%s: %.1f g'):format(r.label, p.seal and (' #' .. p.seal) or '', r.grams), type = 'inform', duration = 6000 })
                    end
                end
                weighMenu()
            end,
        }
    end
    lib.registerContext({ id = 'ascard_scale', title = 'Pack scale', options = options })
    lib.showContext('ascard_scale')
end
RegisterNetEvent('as-tradingcards:client:useScale', weighMenu)

RegisterNetEvent('as-tradingcards:client:openSlabCase', function(stash)
    exports.ox_inventory:openInventory('stash', stash)
end)

function OpenSell()
    local list = lib.callback.await('as-tradingcards:server:getSellable', false)
    if not list then return end
    if #list == 0 then
        return lib.notify({ description = L('nothing_to_sell'), type = 'error' })
    end
    local options = {}
    for _, c in ipairs(list) do
        options[#options + 1] = {
            title = c.title,
            description = ('%s | %s'):format(c.rarity, Utils.Money(c.price)),
            icon = 'fas fa-sterling-sign',
            onSelect = function()
                local confirm = lib.alertDialog({
                    header = L('menu_sell'),
                    content = L('confirm_sell', c.title, Utils.Money(c.price)),
                    centered = true,
                    cancel = true,
                })
                if confirm == 'confirm' then
                    lib.callback.await('as-tradingcards:server:sell', false, c.slot, c.serial)
                    OpenSell()
                end
            end,
        }
    end
    lib.registerContext({ id = 'ascard_sell', title = L('menu_sell'), options = options })
    lib.showContext('ascard_sell')
end

function ReportStolen()
    local pulls = lib.callback.await('as-tradingcards:server:myPulls', false) or {}
    local opts = {}
    for _, p in ipairs(pulls) do
        opts[#opts + 1] = {
            title = p.name, description = p.serial .. (p.stolen and ' · REPORTED STOLEN' or ''),
            icon = p.stolen and 'fas fa-circle-exclamation' or 'fas fa-id-card',
            iconColor = p.stolen and '#f25f5c' or nil,
            onSelect = function()
                local ok = lib.alertDialog({ header = p.stolen and 'Mark as recovered?' or 'Report stolen?', content = ('%s\n%s'):format(p.name, p.serial), centered = true, cancel = true })
                if ok == 'confirm' then lib.callback.await('as-tradingcards:server:reportStolen', false, p.serial, p.stolen) end
            end,
        }
    end
    if #opts == 0 then opts[1] = { title = 'No cards registered to you yet', disabled = true } end
    lib.registerContext({ id = 'ascard_stolen', title = L('target_stolen'), options = opts })
    lib.showContext('ascard_stolen')
end

--[[ ---------------------------------------------------------------------------
    RENAME binders / slab cases
    ox_inventory: right-click the item -> Rename (a button in the item definition calls this export)
    or: /renamecard (renames the binder / slab case in your first slot that has one)
--------------------------------------------------------------------------- ]]
local function renameItem(slot)
    local info = lib.callback.await('as-tradingcards:server:renameInfo', false, slot)
    if not info then return lib.notify({ description = 'Only binders and slab cases can be renamed.', type = 'error' }) end
    local input = lib.inputDialog(('Rename %s'):format(info.kind), {
        { type = 'input', label = 'Name', description = 'Up to 30 characters. Leave empty to reset.', default = info.name, max = 30 },
    })
    if not input then return end
    lib.callback.await('as-tradingcards:server:rename', false, slot, input[1] or '')
end
exports('renameItem', renameItem)

RegisterNUICallback('binderRename', function(data, cb)
    cb(lib.callback.await('as-tradingcards:server:binderRename', false, data and data.name or '') or false)
end)

--[[ ---------------------------------------------------------------------------
    REPACKS (card shop)
--------------------------------------------------------------------------- ]]
function OpenRepacks()
    local list = lib.callback.await('as-tradingcards:server:repackList', false)
    if not list then return end
    local options = {}
    local G = { numbered = ' · 1 numbered card or better guaranteed', bigHit = ' · 1 graded card or hit guaranteed' }
    for _, t in ipairs(list) do
        local desc = ('%s · %d cards%s'):format(Utils.Money(t.price), t.cards, G[t.guarantee] or '')
        if t.chase then desc = desc .. ('\nChase: %s (%s)'):format(t.chase.title, Utils.Money(t.chase.value)) end
        if not t.available then desc = desc .. '\nOut of stock: check back when more cards are sold to the shop' end
        options[#options + 1] = {
            title = t.label, description = desc, icon = 'fas fa-box-open', disabled = not t.available,
            onSelect = function()
                local ok = lib.alertDialog({ header = t.label, content = ('Buy a %s for %s?'):format(t.label, Utils.Money(t.price)), centered = true, cancel = true })
                if ok == 'confirm' then lib.callback.await('as-tradingcards:server:repackBuy', false, t.id) end
            end,
        }
    end
    lib.registerContext({ id = 'ascard_repacks', title = 'Repacks', menu = 'ascard_shop', options = options })
    lib.showContext('ascard_repacks')
end

-- appraisal letter
RegisterNetEvent('as-tradingcards:client:viewAppraisal', function(a)
    Nui.Open('appraisal', a)
end)

RegisterNUICallback('appraisalSave', function(data, cb)
    cb(lib.callback.await('as-tradingcards:server:appraisalSave', false, data and data.ref) or false)
end)

RegisterNUICallback('appraisalSaveComputer', function(data, cb)
    cb(lib.callback.await('as-tradingcards:server:appraisalSaveComputer', false, data and data.ref) or false)
end)

--[[ ---------------------------------------------------------------------------
    SHRINK WRAP (reseal packs into a box)
--------------------------------------------------------------------------- ]]
RegisterNetEvent('as-tradingcards:client:useShrinkwrap', function()
    local list = lib.callback.await('as-tradingcards:server:resealList', false)
    if not list then return lib.notify({ type = 'error', description = 'You can’t use shrink wrap right now.' }) end
    local opts = {}
    for _, b in ipairs(list) do
        opts[#opts + 1] = {
            title = b.label, description = b.need, icon = 'box', disabled = not b.possible,
            onSelect = function()
                local ok = lib.progressCircle({ duration = 6000, label = 'Shrink wrapping...', position = 'bottom', canCancel = true, disable = { move = true, combat = true },
                    anim = { dict = 'mp_arresting', clip = 'a_uncuff' } })
                if ok then lib.callback.await('as-tradingcards:server:reseal', false, b.item) end
            end,
        }
    end
    lib.registerContext({ id = 'ascard_reseal', title = 'Shrink wrap packs into a box', options = opts })
    lib.showContext('ascard_reseal')
end)

--[[ ---------------------------------------------------------------------------
    SHOP HOURS (game clock mode tells the server the in-game hour)
--------------------------------------------------------------------------- ]]
CreateThread(function()
    local sh = Config.ShopHours
    if not (sh and sh.enabled and sh.clock == 'game') then return end
    while true do
        LocalPlayer.state:set('ascardHour', GetClockHours(), true)
        Wait(30000)
    end
end)

--[[ ---------------------------------------------------------------------------
    ADMIN PANEL (/cardadmin)
--------------------------------------------------------------------------- ]]
RegisterNetEvent('as-tradingcards:client:admin', function()
    local res = lib.callback.await('as-tradingcards:server:admin', false, 'overview', {})
    if not res or not res.ok then return lib.notify({ type = 'error', description = res and res.error or 'Staff only.' }) end
    Nui.Open('admin', { overview = res.data, me = GetPlayerServerId(PlayerId()) })
end)

RegisterNUICallback('admin', function(data, cb)
    data = data or {}
    cb(lib.callback.await('as-tradingcards:server:admin', false, data.name, data.data or {}) or { ok = false, error = 'No answer.' })
end)

--[[ pack screen: a card turned over goes into the inventory; leaving early hands over the rest ]]
RegisterNUICallback('packTake', function(data, cb)
    if packToken and data and data.token == packToken then TriggerServerEvent('as-tradingcards:server:packTake', packToken, tonumber(data.index)) end
    cb('ok')
end)
function FlushPackCards()
    if packToken then
        TriggerServerEvent('as-tradingcards:server:packDone', packToken)
        packToken = nil
    end
end
