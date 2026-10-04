--[[ One-time unpacker for the card pictures (html/img/cards/*.webp).
     The pictures ship as one text file (html/img/cards.bundle) because copying 1,000+ small files is slow.
     On start, any picture that is missing is written out. New files are only served to players after the
     next restart, so restart the resource once more when it says so. Safe to delete the bundle afterwards. ]]
local res = GetCurrentResourceName()

local b64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local dec = {}
for i = 1, #b64 do dec[b64:byte(i)] = i - 1 end

local function decode(s)
    local out, n = {}, 0
    local char = string.char
    for i = 1, #s - 3, 4 do
        local a, b, c, d = s:byte(i, i + 3)
        local x = (dec[a] << 18) | (dec[b] << 12) | ((dec[c] or 0) << 6) | (dec[d] or 0)
        n = n + 1
        if d == 61 then -- '='
            if c == 61 then out[n] = char((x >> 16) & 255)
            else out[n] = char((x >> 16) & 255, (x >> 8) & 255) end
        else
            out[n] = char((x >> 16) & 255, (x >> 8) & 255, x & 255)
        end
    end
    return table.concat(out)
end

local BUNDLES = {
    { file = 'html/img/cards.bundle', dir = 'html/img/cards/' },
    { file = 'html/img/slabs.bundle', dir = 'html/img/slabs/' },
}

CreateThread(function()
    local written = 0
    for _, b in ipairs(BUNDLES) do
        local data = LoadResourceFile(res, b.file)
        if data and data ~= '' then
            -- a new bundle (different size) rewrites every picture; otherwise only missing ones are written
            local verPath = b.dir .. 'version.txt'
            local fresh = LoadResourceFile(res, verPath) ~= tostring(#data)
            local checked = 0
            for name, body in data:gmatch('([^\t\n]+)\t([^\n]+)') do
                checked = checked + 1
                local path = b.dir .. name
                if fresh or not LoadResourceFile(res, path) then
                    local bin = decode(body)
                    if SaveResourceFile(res, path, bin, #bin) then written = written + 1 end
                end
                if checked % 25 == 0 then Wait(0) end
            end
            if fresh then SaveResourceFile(res, verPath, tostring(#data), -1) end
        end
    end
    if written > 0 then
        print(('^3[%s] unpacked %d card pictures - restart %s once more so players can see them^0'):format(res, written, res))
    end
end)
