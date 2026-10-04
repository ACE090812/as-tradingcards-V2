--[[ ---------------------------------------------------------------------------
    CLUBS  (made-up parody clubs)
    c1 = main kit colour, c2 = second colour, text = badge text colour
--------------------------------------------------------------------------- ]]
Config.Clubs = {
    -- empty on purpose: clubs / sets / teams are created by your cards (custom/cards.json or the in-game creator)
}

--[[ ---------------------------------------------------------------------------
    SETS
--------------------------------------------------------------------------- ]]
Config.Sets = {
    series1 = {
        label = 'Series 1',
        code = 'S1',
    },
}

--[[ ---------------------------------------------------------------------------
    PORTRAIT LOOKS  (the illustrated player - generic cartoon, not a likeness)
    skin / hair = colours, style = crop | buzz | curly | slick | bald, beard = true/false
    Set `image = 'img/whatever.png'` (or an https:// URL) on a card to use your own art instead.
--------------------------------------------------------------------------- ]]
local S = { light = '#f1c7a3', fair = '#edc39c', tan = '#d9a27a', olive = '#c68e63', brown = '#a8704a', dark = '#7a4a2e', deep = '#5c3620' }
local H = { blonde = '#d9b56a', brown = '#5a3b22', dark = '#1b1b1b', ginger = '#b5562a', grey = '#9a9a9a' }

local function look(skin, hair, style, beard)
    return { skin = S[skin] or skin, hair = H[hair] or hair, style = style, beard = beard or nil }
end

--[[ ---------------------------------------------------------------------------
    CARDS  (key = card id - never change it once cards exist)
    type      : player | star | captain | winner | century | legend  (Config.Types)
    number    : card number in the set (legends use code = 'L01' etc.)
    att / def : Attack and Defence (1-100)
    nation    : 3-letter flag code (see FLAGS in html/app.js)
    maxPrints : limit how many can ever be pulled (nil = unlimited)
    weight    : chance within its type (default 1)
    value     : override the type sell value (optional)
--------------------------------------------------------------------------- ]]
Config.Cards = {
    -- empty on purpose: add cards through custom/cards.json / custom/cards.lua (see custom/README.txt)
}
