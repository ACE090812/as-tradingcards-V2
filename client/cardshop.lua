-- Player card shop (client): counter, shop desk, customer + manager screens, grading for customers
local CS = Config.CardShop or {}
if not CS.enabled then return end

local function call(name, ...)
    local r, err = lib.callback.await('as-tradingcards:server:' .. name, false, ...)
    return r, err
end
local function reply(r, err) return r and { ok = true, data = r } or { ok = false, error = err or 'Something went wrong.' } end

local function openCustomer()
    local d, err = call('shopCustomer')
    if not d then return lib.notify({ description = err or 'Nobody is serving right now.', type = 'error' }) end
    Nui.Open('shopCustomer', d)
end
local function openManager()
    local d, err = call('shopManage')
    if not d then return lib.notify({ description = err or 'Not now.', type = 'error' }) end
    Nui.Open('shopManage', d)
end

local function gradeForCustomer()
    local list, err = call('shopGradeNearby')
    if not list then return lib.notify({ description = err or 'Not now.', type = 'error' }) end
    if #list == 0 then return lib.notify({ description = 'Nobody is at the counter.', type = 'error' }) end
    local opts = {}
    for _, p in ipairs(list) do
        opts[#opts + 1] = { title = p.name, icon = 'fas fa-user', onSelect = function()
            local ok, e = call('shopGradeAsk', p.id)
            if not ok then lib.notify({ description = e or 'Could not ask them.', type = 'error' }) end
        end }
    end
    lib.registerContext({ id = 'ascard_gradeFor', title = 'Whose card is it?', options = opts })
    lib.showContext('ascard_gradeFor')
end

local function counterMenu()
    local role = lib.callback.await('as-tradingcards:server:shopRole', false) or {}
    local opts = {}
    if role.staffed then
        opts[#opts + 1] = { title = 'Browse the shop', description = 'Buy packs, supplies and cards. Sell your cards.', icon = 'fas fa-store', onSelect = openCustomer }
        opts[#opts + 1] = { title = 'Collect graded cards', icon = 'fas fa-box-open', onSelect = function() if CollectGrading then CollectGrading() end end }
        opts[#opts + 1] = { title = 'Binder covers and playmats', icon = 'fas fa-palette', onSelect = function() if OpenSkins then OpenSkins() end end }
    end
    if role.rank then
        if role.onduty then opts[#opts + 1] = { title = 'Send a customer’s card for grading', icon = 'fas fa-magnifying-glass', onSelect = gradeForCustomer } end
        opts[#opts + 1] = { title = 'Shop desk', description = ('You are %s'):format(role.rank), icon = 'fas fa-clipboard-list', onSelect = openManager }
    end
    if #opts == 0 then return lib.notify({ description = role.staffed == false and 'Nobody is on duty at the counter.' or 'Nothing to do here.', type = 'inform' }) end
    lib.registerContext({ id = 'ascard_counter', title = CS.counter and 'Card shop counter' or 'Card shop', options = opts })
    lib.showContext('ascard_counter')
end

CreateThread(function()
    Wait(1000)
    local c = (CS.counter or {}).coords
    local spot
    if c and not (c.x == 0.0 and c.y == 0.0 and c.z == 0.0) then spot = vec3(c.x, c.y, c.z)
    elseif Config.Peds and Config.Peds[1] then local p = Config.Peds[1].coords spot = vec3(p.x, p.y, p.z) end
    if not spot then return end
    Target.AddPoint('ascard_counter', spot, (CS.counter or {}).radius or 1.6, { { label = 'Card shop counter', icon = 'fas fa-store', onSelect = counterMenu } })
    local d = (CS.managerDesk or {}).coords
    if d and not (d.x == 0.0 and d.y == 0.0 and d.z == 0.0) then
        Target.AddPoint('ascard_desk', vec3(d.x, d.y, d.z), (CS.managerDesk or {}).radius or 1.2, { { label = 'Card shop desk', icon = 'fas fa-clipboard-list', onSelect = counterMenu } })
    end
    local b = (CS.counter or {}).blip
    if b and c and not (c.x == 0.0 and c.y == 0.0 and c.z == 0.0) then
        local blip = AddBlipForCoord(c.x, c.y, c.z)
        SetBlipSprite(blip, b.sprite) SetBlipColour(blip, b.colour) SetBlipScale(blip, b.scale) SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING') AddTextComponentSubstringPlayerName(b.label) EndTextCommandSetBlipName(blip)
    end
end)

-- NUI -----------------------------------------------------------------------
RegisterNUICallback('shopRefreshCustomer', function(_, done) done(reply(call('shopCustomer'))) end)
RegisterNUICallback('shopBuy', function(d, done) local r, e = call('shopBuy', d and d.id, d and d.amount) done({ ok = r == true, error = e }) end)
RegisterNUICallback('shopSell', function(d, done) local r, e = call('shopSell', d and d.slot, d and d.serial) done({ ok = r == true, error = e }) end)
RegisterNUICallback('shopSetPrice', function(d, done) done(reply(call('shopSetPrice', d and d.id, d and d.price))) end)
RegisterNUICallback('shopSetBuy', function(d, done) done(reply(call('shopSetBuy', d and d.pct, d and d.on))) end)
RegisterNUICallback('shopWithdraw', function(d, done) done(reply(call('shopWithdraw', d and d.amount))) end)
RegisterNUICallback('shopDeposit', function(d, done) done(reply(call('shopDeposit', d and d.amount))) end)
RegisterNUICallback('shopOrder', function(d, done) done(reply(call('shopOrder', d and d.item, d and d.qty))) end)
RegisterNUICallback('shopRefreshManage', function(_, done) done(reply(call('shopManage'))) end)

-- a customer asked by staff which card to send for grading
RegisterNetEvent('as-tradingcards:client:gradeAsk', function(d)
    if #d.cards == 0 then return lib.notify({ description = 'You have no cards to send for grading.', type = 'error' }) end
    local cards, tiers = {}, {}
    for _, c in ipairs(d.cards) do cards[#cards + 1] = { value = c.slot .. '|' .. c.serial, label = c.title } end
    for _, t in ipairs(d.tiers) do tiers[#tiers + 1] = { value = t.id, label = ('%s · %s · back in %s'):format(t.label, Utils.Money(t.fee), t.time) } end
    local input = lib.inputDialog(('%s will send a card for grading'):format(d.staff), {
        { type = 'select', label = 'Card', options = cards, required = true, searchable = true },
        { type = 'select', label = 'Service', options = tiers, default = tiers[1].value, required = true },
    })
    if not input then return end
    if d.needCase and not d.hasCase then return lib.notify({ description = 'You need a grading case.', type = 'error' }) end
    local slot, serial = tostring(input[1]):match('^(%d+)|(.+)$')
    local ok, err = lib.callback.await('as-tradingcards:server:shopGradeConfirm', false, d.req, tonumber(slot), serial, input[2])
    if not ok then lib.notify({ description = err or 'Could not send it.', type = 'error' }) end
end)
