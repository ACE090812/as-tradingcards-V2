CUSTOM FOLDER  (cards and playmats from your creators)
======================================================

EASIEST WAY: paste the creators' own Lua output (no editing, no converting)
  custom/cards.lua      <- Card Creator "Copy Lua" (see custom/cards.example.lua)
  custom/playmats.lua   <- Playmat Creator "Copy Lua" (see custom/playmats.example.lua)
  Card art goes in custom/img/, mat images go in html/img/playmats/.
  Creator rarity becomes a card type (Common, Uncommon, Rare, Epic,
  Legendary, Mythic). ATK and DEF are used as the card's attack and defence. 
  THEMES (set in the Card Creator's Theme box):
    Football  -> set series2.   Fields: club, position, nation.
    Creatures -> set creatures. Fields: element (ember, tide, leaf, volt, shade, stone, frost, spirit), stage, HP, move. Original creatures, no real franchise names or art.
    Los Santos -> set lossantos. Fields: category (character, vehicle, landmark, crew, item), district.
  All three sets are hidden until the admin Series 2 switch is on AND the set has at least one card.
  CARD BACKS: the Card Creator's Card back panel designs one back per theme (pattern, colours, emblem, title) or uses your own image. It exports with Copy Lua into custom/cards.lua. No back = the default.
  PACKS: the creator's Packs panel exports Config.Packs into custom/cards.lua. Rates become the pack's card type odds, and the last-card guarantee is kept. A pack draws from ONE game set (its theme's set), so make one pack per theme. Add the pack item lines (ox/qb) to your inventory. Card back extras (image, dim, fit, colours) are read too.
  Packs: ascard_s2_booster, ascard_cr_booster, ascard_ls_booster (items in install/).
  Spell and trap cards are skipped (battles have no spells or traps) and logged in the server console.
  Finish and border/plate colours are kept. All options are in Config.Custom (config/custom.lua).
  The JSON format below still works too.

Put your creator output here. Nothing in the Lua needs editing. Restart as-tradingcards after changes.

custom/cards.json   array of cards (or { "cards": [ ... ] })
custom/mats.json    array of playmats
custom/img/         card images and mat images (png / jpg / webp). Already in the resource manifest.

CARD (all fields except id optional; same fields as config/cards.lua)
{
  "id": "smithy",              unique key, lowercase letters/numbers/underscore  (required)
  "first": "Jack",  "last": "Smith",
  "club": "ar",                a key from Config.Clubs. Unknown keys are made up for you (label = the key).
  "clubLabel": "Arsenic",      optional label used when the club key is unknown
  "pos": "FWD",                FWD | MID | DEF | GK  (or ST, CB, ...)
  "att": 84, "def": 61,
  "type": "star",              player | star | captain | winner | century | legend
  "set": "series2",
  "number": 12,
  "nation": "ENG",
  "image": "smithy.png",       file in custom/img/ (or a full https:// URL)
  "weight": 1,                 how often it drops inside its type
  "maxPrints": 100,            optional print run
  "seasonal": "halloween26"    optional: only drops while that window (Config.Seasonal.windows) is open
}

PLAYMAT
{
  "id": "terrace",
  "label": "Terrace Night",
  "image": "terrace.png",      file in custom/img/ (a board from the board creator)
  "bg": "#101010"              optional colour behind the image
}
