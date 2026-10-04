-- Card Market app for sd-phone (html/market/phone.html is framed by the phone)
if not (Config.Phone and Config.Phone.enabled) then return end

local RES = GetCurrentResourceName()

local function register()
    local ok, res, err = pcall(function()
        return exports['sd-phone']:addCustomApp({
            identifier  = Config.Phone.identifier,
            name        = Config.Phone.name,
            description = Config.Phone.description,
            defaultApp  = Config.Phone.defaultApp,
            ui          = RES .. '/html/market/phone.html',
            icon        = 'https://cfx-nui-' .. RES .. '/html/market/icon.png',
        })
    end)
    if not ok or res == false then
        print(('[as-tradingcards] could not add the Card Market app to sd-phone: %s'):format(tostring(ok and err or res)))
    end
end

CreateThread(function()
    while GetResourceState('sd-phone') ~= 'started' do Wait(1000) end
    Wait(1000)
    register()
end)

AddEventHandler('onClientResourceStart', function(res)
    if res == 'sd-phone' then SetTimeout(2000, register) end
end)

RegisterNUICallback('market', function(data, cb)
    data = type(data) == 'table' and data or {}
    local res = lib.callback.await('as-tradingcards:server:market', false, tostring(data.name or ''), data.args or {})
    cb(res or { ok = false, error = 'No response from the server.' })
end)
