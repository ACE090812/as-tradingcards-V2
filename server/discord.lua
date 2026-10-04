--[[ Big pulls to Discord (nothing is shown in game). Webhook goes in server.cfg:
       set ascard_webhook "https://discord.com/api/webhooks/..." ]]
local function webhook()
    local url = GetConvar('ascard_webhook', '')
    if url == '' then url = (Config.Discord or {}).webhook or '' end
    return url
end

local COLOURS = { auto = 0x3b82f6, relic = 0x22c55e, autorelic = 0xf59e0b, oneOfOne = 0x111111, error = 0xef4444 }

function AnnouncePull(src, meta, itemName)
    local dc = Config.Discord
    if not dc or not dc.enabled or not meta then return end
    local url = webhook()
    if url == '' then return end
    local a = dc.announce or {}
    local d = Utils.BuildDisplay(meta, itemName)
    local reason, colour
    if meta.insert and a.inserts then reason, colour = d.insert.label, COLOURS[meta.insert]
    elseif d.parallel and d.parallel.max == 1 and a.oneOfOne then reason, colour = ('%s 1/1'):format(d.parallel.label), COLOURS.oneOfOne
    elseif meta.error and a.errors then reason, colour = 'Error card: ' .. d.error.label, COLOURS.error
    elseif d.rarity.id == 'legend' and d.parallel and a.legendsNumbered then reason, colour = 'Numbered Legend', 0xd4af37
    end
    if not reason then return end

    local who = Framework.GetName(src) or GetPlayerName(src) or 'Someone'
    local fields = {
        { name = 'Card', value = Utils.CardTitle(meta, itemName), inline = false },
        { name = 'Club', value = d.club.label ~= '' and d.club.label or '-', inline = true },
        { name = 'Type', value = d.rarity.label, inline = true },
        { name = 'Serial', value = meta.serial or '-', inline = true },
    }
    local embed = {
        title = ('%s pulled a %s!'):format(who, reason),
        color = colour or 0xffffff,
        fields = fields,
        footer = { text = Config.CardFooter or '' },
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
    }
    local photo = Config.PhotoUrl
    if type(photo) == 'string' and photo ~= '' and d.id then
        embed.thumbnail = { url = photo:gsub('{id}', d.id) }
    end
    PerformHttpRequest(url, function() end, 'POST', json.encode({ username = dc.username, embeds = { embed } }), { ['Content-Type'] = 'application/json' })
end
