fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'as-tradingcards'
description 'Trading cards - packs, serials, foils, grading, binder, sell-back. QBCore / QBX / ESX.'
version '3.0.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/condition.js',
    'html/v2.js',
    'html/v2.css',
    'custom/img/*.png',
    'custom/img/*.jpg',
    'custom/img/*.webp',
    'custom/*.json',
    'html/img/playmats/*.png',
    'html/img/playmats/*.jpg',
    'html/img/playmats/*.webp',
    'html/market/*.html',
    'html/market/*.css',
    'html/market/*.js',
    'html/market/*.png',
    'html/img/*.png',
    'html/img/*.jpg',
    'html/img/*.webp',
    'html/img/items/*.png',
    'html/img/cards/*.webp',
    'html/img/slabs/*.webp',
    'html/img/badges/*.png',
    'html/img/badges/*.webp',
    'html/img/players/*.png',
    'html/img/players/*.jpg',
    'html/img/players/*.webp',
    'html/sounds/*.ogg',
}

-- props (booster pack, booster box, deck box)
data_file 'DLC_ITYP_REQUEST' 'stream/as_cardbinder.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/asboosterbox.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/ascardpack.ytyp'

shared_scripts {
    '@ox_lib/init.lua',
    'config/config.lua',
    'config/cards.lua',
    'config/condition.lua',
    'config/products.lua',
    'config/market.lua',
    'config/extras.lua',
    'config/community.lua',
    'config/toptrumps.lua',
    'config/admin.lua',
    'config/battle.lua',
    'config/trader.lua',
    'config/cardshop.lua',
    'config/series2.lua',
    'config/custom.lua',
    'shared/custom.lua',
    'shared/utils.lua',
    'shared/condition.lua',
}

client_scripts {
    'bridge/target.lua',
    'client/nui.lua',
    'client/main.lua',
    'client/peds.lua',
    'client/condition.lua',
    'client/phone.lua',
    'client/toptrumps.lua',
    'client/v2.lua',
    'client/battle.lua',
    'client/trader.lua',
    'client/cardshop.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'bridge/framework.lua',
    'bridge/inventory.lua',
    'server/db.lua',
    'server/cards.lua',
    'server/images.lua',
    'server/discord.lua',
    'server/main.lua',
    'server/shop.lua',
    'server/extras.lua',
    'server/grading.lua',
    'server/binder.lua',
    'server/condition.lua',
    'server/commands.lua',
    'server/market.lua',
    'server/auctions.lua',
    'server/community.lua',
    'server/toptrumps.lua',
    'server/collector.lua',
    'server/admin.lua',
    'server/v2db.lua',
    'server/society.lua',
    'server/deck.lua',
    'server/battle.lua',
    'server/tourney.lua',
    'server/skins.lua',
    'server/trader.lua',
    'server/cardshop.lua',
    'server/api.lua',
}

dependencies {
    'ox_lib',
    'oxmysql',
}
