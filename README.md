# as-tradingcards v2 – Trading Cards

Trading cards for **QBCore, QBX and ESX**: Attack/Defence stats, six card types with animated effects, serials, foils, grading, binder and sell-back. No cards are built in: every card, club/team and set is created with the Card Creator and added through `custom/cards.json` / `custom/cards.lua` (see `custom/README.txt`).

## Requirements
- `ox_lib`, `oxmysql`
- One framework: `qbx_core`, `qb-core` or `es_extended`
- One inventory: `ox_inventory` (any framework) or `qb-inventory` / ps- / lj-inventory (QBCore only)
  - ESX **needs** ox_inventory, because the default ESX inventory has no item metadata
- A target (optional): `as-interact`, `ox_target` or `qb-target`. Without one, it falls back to an ox_lib `[E]` prompt

Everything is detected automatically. You can force a choice in `config/config.lua` (`Config.Framework`, `Config.Inventory`, `Config.Target`).

## Install
1. **Stop the old `as-tradingcards`.** v2 uses the same item names, so the two can't run together. Delete the old folder or rename it to `[old]as-tradingcards`.
2. Rename this folder to `as-tradingcards` if you like. The code doesn't depend on the folder name.
3. Add the items:
   - ox_inventory: `install/ox_inventory_items.lua` → `ox_inventory/data/items.lua`, replacing any old `ascard_*` entries. Each usable item has `server = { export = 'as-tradingcards.useItem' }`. **That name must match this resource's folder name**, so change it if you rename the folder. Without it, using the items does nothing on QBX.
   - qb-inventory: `install/qb-core_items.lua` → `qb-core/shared/items.lua`
4. Add item images (`ascard_*.png`) to your inventory's image folder.
5. `ensure as-tradingcards` after ox_lib, oxmysql, your framework and your inventory.
6. The database tables are created on first start. `sql/install.sql` is there if your DB user can't create tables.
7. **Remove the old qb-inventory `Itemshop_ascard` patch** from the v1 README. It isn't needed any more.

## Features
| | |
|---|---|
| **Server-side packs** | The server rolls the cards, removes the pack and adds the items. The client only plays the progress bar and animation. |
| **Weighted card types** | Drop weights per pack, plus a guarantee (e.g. at least 1 Uncommon or better per pack). |
| **Serials & print runs** | Every card gets a serial like `S1-001-0042`. Set `maxPrints` to cap a card, e.g. only 50 ever. When a card sells out, it stops dropping. |
| **Foils** | Chance per pack. Foils get a rainbow holo layer and a value multiplier. |
| **Pack opening** | Tear the pack open, cards are dealt face-down, then flip each one or reveal all. Each rarity has its own glow and sound. The best card is revealed last. |
| **Show nearby** | Button on the card view. Players within 3m see the card in the corner of their screen and keep control. The shower plays a hold-card animation with a prop. |
| **Grading** | Hand a card and a PSA case to the grader and pay a fee. Collect it later (real time, survives restarts) as a graded slab with a 1–10 grade and cert number. |
| **Sell-back** | The buyer NPC pays by rarity × foil × grade, plus a bonus for low print numbers. |
| **Binder** | A real binder: 60 pages of 9 sleeves (`Config.Binder.pages`). Drag any card into any sleeve (duplicates and parallels too), move them around or take them out. The contents stay with the binder item, so you can sell or give a full binder. |
| **Peds** | One config entry can be shop, grader and buyer. Peds only spawn when a player is nearby. |

## Card condition
Every card has a real condition: four scores (centering, corners, edges, surface) plus visible issues like dust, fingerprints, dirt, stains, scratches, print lines, edge whitening, dinged corners, creases and water damage. Settings are in `config/condition.lua`.
- **Out of the pack**: most cards are near mint. A few come off-centre, with a print line or, rarely, a dinged corner.
- **Wear**: loose cards pick up dust, scratches, corner dings and edge whitening while carried. Creases are rare. Viewing or showing a loose card can leave fingerprints. Swimming or heavy rain can cause water damage. Dropping a loose card can ding or crease it.
- **Protection**: penny sleeve (`ascard_sleeve`) stops dust, fingerprints, scratches and water. A toploader (`ascard_toploader`, needs a sleeve first) stops all wear. Use the buttons on the card view. Cards in a binder don't wear.
- **Magnifier** (`ascard_loupe`): adds an Inspect button to the card view showing every flaw and the exact scores. Without it you only see an overall guess ("Looks Near Mint").
- **Cleaning bench**: in the card shop (`Config.Condition.benches`, set it with `/cardbenchpos`). You need a microfibre cloth (`ascard_cloth`). The camera looks down at the mat and the card appears as a 3D card you wipe with the mouse. The cleaner spray (`ascard_spray`) removes dirt and stains: right-click to spray, then wipe, but press too hard and it scratches. Creases, corners, edges, centering and water damage can't be fixed.
- **Grading** uses the real condition (the lowest score counts most) and the slab shows sub-grades. **Selling** a raw card pays less the worse its condition is.
- Cards from before this update start as near mint with small random flaws.

## Market, auctions, phone app and website
Settings are in `config/market.lua`. Everything below works without the optional resources; they just add the phone app, the website and locker delivery.

- **Market prices**: every card has a live price = base value × supply × demand. Supply compares how many copies of that card have been pulled with the average for its card type (fewer = worth more, sold-out cards get a bonus). Demand comes from what the card actually sold for at auction over the last 14 days. Prices are worked out every 10 minutes and saved every hour for the price charts. The card shop's sell-back uses market prices too (`Config.Market.shopUsesMarket = false` to turn that off).
- **Card Market app** (needs `sd-phone`): installed from the App Store (`Config.Phone.defaultApp = true` to pre-install it). Price guide with charts and every version's price, live auctions, selling, your set checklist, your pulls (report stolen / found) and price alerts, plus a stolen serial check.
- **Website** (needs `as-browser`): the same thing at `lscardexchange.co.uk` (`Config.Site`). It registers itself with as-browser's `registerSite` export, so as-browser doesn't need any edits.
- **Auctions**: the seller picks 1 hour, 6 hours or 24 hours and pays the listing fee up front (£25 / £50 / £100), with an optional buy it now and a hidden reserve. The card leaves their pockets while it's listed. A bid takes the money straight away and being outbid gives it back. Buy it now goes once the first bid is placed. A bid in the last 2 minutes pushes the end back 2 minutes. When it sells, the seller gets the winning bid minus 5%. Stolen cards can't be listed. A seller can cancel only while there are no bids.
- **Delivery** (needs `as-postalprime`): the winner's card, and unsold or cancelled items going back to the seller, are sent to the Postal Prime locker picked in the app (Delivery). A parcel left in the locker until it expires is sent again, so a card is never lost. Without Postal Prime, items go straight into the player's pockets the next time they're online.
- **Money for offline players**: money for someone who is offline (sale proceeds, refunds) is kept in `ascard_payouts` and paid into their bank within a minute of them coming online.
- **Phone alerts** (sd-phone notifications): outbid, first bid, won, sold, not sold, reserve not met, ending in 5 minutes (bidders and watchers), grading ready to collect, and price alerts. Turn each one on or off in `Config.Alerts`. Without sd-phone they show as normal notifications.
- **Tables**: `ascard_sales`, `ascard_price_history`, `ascard_price_alerts`, `ascard_market_prefs`, `ascard_auctions`, `ascard_bids`, `ascard_payouts`, `ascard_deliveries`, all created on first start.
- **Start order**: `ensure sd-phone`, `ensure as-browser`, `ensure as-postalprime`, then `ensure as-tradingcards`. Restarting as-browser re-adds the website automatically.

## Pop report, stock, pack scale, slab case
Settings are in `config/extras.lua`.
- **Pop report**: every card graded is counted by version (base, foil, each parallel, each hit) and grade. It shows on each card's page in the app and website, on graded auctions, and in the grade reveal ("Pop 1 at 10, none graded higher"). Cracking a slab doesn't remove it, the same as the real report.
- **Grade reveal**: collecting from the grader plays a reveal for each slab. The label is covered, then slides away, the grade drops in (a GEM MT 10 gets a flash and sparks), then the sub-grades, the pop and the value appear.
- **Weekly stock**: the items in `Config.Stock.items` only get that many a week, and restock on `restockDay` / `restockHour`. Empty by default; add your own boxes there.
- **Pack scale** (`ascard_scale`, £60): weigh sealed packs. Packs with a hit are slightly heavier, but every pack varies a little and each reading wobbles, so a heavy pack is a clue, not a guarantee. With `uniquePacks = true` every pack is its own slot with a seal number, so hit packs can't be spotted by stacking. Buying 10 packs then needs 10 free slots.
- **Slab case** (`ascard_slabcase`, £75): holds 10 graded slabs and only slabs (ox_inventory). The slabs stay with the case, so giving the case gives the slabs. Slabs in a case count in Collection, My cards.
- **Pack odds page**: the app (Prices, then Pack odds) and the website (`/odds`) list the odds for every pack, box and hit, plus this week's stock.
- New items: add `install/ox_inventory_items_extras.lua` to ox_inventory and copy `ascard_scale.png` and `ascard_slabcase.png` into ox_inventory's image folder.

## Lots, offers, ratings, wantlist, this week, release days
Settings: `Config.Auctions` in `config/market.lua` (lots, offers, ratings) and `config/community.lua` (wantlist, this week, release days).
- **Lots**: in Sell, switch to "A lot (several)", tick 2 to 10 items (`maxLot`) and give it an optional name. The winner gets everything in one Postal Prime parcel. Unsold lots go back to the seller the same way.
- **Make an offer**: on a buy it now listing with no bids, buyers can offer from 50% of the buy it now price (`offers.minPercent`). The money is held. The seller sees the offers on their listing and can accept (the auction ends and the buyer gets it) or decline (refunded). Offers are refunded if the seller doesn't answer within 24 hours, someone bids, the listing is cancelled, or another offer is accepted.
- **Seller ratings**: after winning, the buyer gets "Rate seller" under My auctions → Finished (positive, neutral or negative, plus an optional comment) for 14 days. Every listing shows the seller's % positive, and tapping the seller's name opens their page with feedback and what they're selling now.
- **Wantlist**: "Add to wantlist" on any card. When one is listed at auction, including inside a lot, everyone who wants it gets a phone notification. It's under Collection → Alerts, and checklist tiles show a heart.
- **This week**: card of the week (the biggest sale), the biggest sales, the biggest pulls (numbered parallels, hits, errors, Legendary and Mythic cards; names are hidden by default with `Config.Weekly.showPullerNames`) and price movers.
- **Release days**: add products to `Config.Releases.list` with a price, quantity, per-player limit and start time. Players buy them in the app or on the website when they go live, and they're sent to their locker. Everyone online gets a notification when one goes live. A **test release** is included that goes live 2 minutes after the resource starts. Delete it once you've tried it.

## Case hits, Top Trumps, renaming
- **Case hits** (`Config.CaseHits` in `config/products.lua`): the rarest insert. Off until you list a box in `Config.CaseHits.boxes`. It's never in normal packs.
- **Top Trumps** (`config/toptrumps.lua`): `/toptrumps`, or target a player with as-interact/ox_target → "Challenge to Top Trumps" (qb-target/textui users can still use the command). Pick no bet or a cash bet (both pay the same, winner takes the pot, a draw refunds it). Each player gets 5 random cards from their own pockets (they need at least 5). The chooser picks Attack or Defence, the higher number wins the round and picks next, and the most rounds won wins. Rare versions get a boost on both stats: Black +10, Red +7, Gold +5, Blue +3, Foil +2, any hit +5. A slow chooser gets their better stat picked after 20 seconds. Leaving, or disconnecting, forfeits. Cards never change hands.
- **Renaming**: binders and slab cases can be renamed (up to 30 characters, empty resets). In ox_inventory, right-click the item → Rename (add the `buttons` line from `install/ox_inventory_items.lua` to your item definitions). The binder screen also has a RENAME button, and the name shows above the page number. The name is the item's name in the inventory and moves with the item.

## Repacks, appraisal letters, Pristine 10, stats, market report
- **Repacks** (`Config.Repacks` in `config/extras.lua`): cards players sell to the card shop go into a pool. The shop menu has **Repacks**: Bronze £50 (3 cards, each worth up to £300), Silver £250 (3 cards, 1 numbered or better guaranteed) and Gold £1,000 (2 cards, 1 graded or hit guaranteed). Cheap cards come up more often. Each tier shows its chase card (the best card you could get). A tier is out of stock until the pool can fill it. Bronze tops up with fresh base cards when the pool is short.
- **Appraisal letters** (`Config.Appraisal`): order one in the app or website (Collection → My cards → Get an appraisal letter) for £50. The letter item goes to your Postal Prime locker. It lists the card, serial, condition or grade (with cert), who presented it, the value and the date. Using the letter shows it. Every letter you order stays under "Your letters", where you can:
  - **Save to phone**: sd-phone Files → Card Exchange.
  - **Save to computer**: as-computer File Explorer → Downloads (needs the `saveToDownloads` export added to `as-computer/server/files.lua`). From there it can be opened in Notepad and printed.
  - **Print**: on the website near a printer (as-printer).
- **Pristine 10** (`Config.Pristine`): a GEM MT 10 where all four sub-grades are 10 gets a black PRISTINE label and is worth 2.5× a normal 10 (after the usual bonus damping).
- **My stats** (Collection → Stats): packs opened, cards pulled, repacks, money spent on product, the value of everything pulled at the time ("pack luck" %), money from the card shop and auctions, and your best pull.
- **Collection value chart** (Collection → My cards): saved once a day, and every 30 minutes while you're online (`Config.ValueHistory`).
- **Daily market report**: posts to Discord every day at `Config.Discord.marketReport.hour` with the top sales and pulls of the last 24 hours, risers and fallers, live auctions and releases. Set `set ascard_market_webhook "..."` in server.cfg (falls back to `ascard_webhook`). `/cardreport` (admin) posts one now.
- New item: `ascard_appraisal` (in `install/ox_inventory_items_extras.lua`, image `ascard_appraisal.png`).

## Admin panel, money logs, sealed boxes, sun damage, serial history, shop hours (config/admin.lua)
- **Admin panel**: `/cardadmin` (ace `group.admin`). Tabs:
  - **Overview**: players online, whether the shop is open, live auctions, the repack pool, unclaimed payouts, and money moved in the last 24 hours and 7 days by type. Also a button to post the market report to Discord.
  - **Players & give**: pick an online player to see their card count and value, sealed value, best cards and recent money. You can give them any card (version, foil, graded 1-10, Pristine) or packs and boxes.
  - **Switches**: pause auctions, stop the shop buying cards, close the card shop, freeze market prices. Switches stay set after a restart.
  - **Auctions**: remove a live listing. The top bid and any offers are refunded, and the item goes back to the seller's locker.
  - **Repack pool**: see what's in it and take cards out.
  - **Money logs**: search by type or player.
- **Money logs** (`Config.MoneyLogs`): every money movement is saved for 60 days: shop buys, sell-backs, auctions and fees, repacks, releases, appraisals, grading fees and Top Trumps winnings. Anything £2,500 or more is posted to Discord: `set ascard_log_webhook "..."`. If a player sells £25,000 or more to the shop within 30 minutes, Discord gets a red "check this player" alert.
- **Sealed boxes** (`Config.Seals`): every box you define in `Config.Boxes` gets its own seal number (on the item: "Factory sealed · Seal FS-XXXXXXXX"). Check it in the app or website under **Check → Box seal**. **Shrink wrap** (`ascard_shrinkwrap`, £5 at the shop) lets anyone wrap the right packs back into a box. It looks the same, but the seal check says it isn't a factory seal, and the shop won't buy it. Opening it gives back exactly the packs that were wrapped. A seal that's been opened, or sold to the shop, shows as used.
- **Sun and damp** (`Config.Weather`): a raw card left in a glovebox fades after 2 hours. One left in a boot can warp after 4 hours. On the ground, both start after 30 minutes. The damage is worked out when you take the card out. A penny sleeve halves it, a toploader stops it, and slabs are always safe. Fading and warping lower the surface and edge scores, show up on the card, and count when it's graded.
- **Serial history**: **Check → Card serial** now shows the card's history: when it was pulled, sent for grading and graded (with cert), sales at auction (including lots), cracked slabs, stolen and recovered reports, appraisals, and sales to the shop.
- **Shop hours** (`Config.ShopHours`): the shop, grader and buyer are open 09:00–23:00 by default. `clock = 'game'` uses the in-game clock instead of real time. `closedDays` can close the shop on set days. The website, app and auctions stay open.
- **Pack opening** (`Config.PackOpening.giveOnReveal`): each card goes into your inventory when you turn it over. Press Done or Esc at any point and all the cards you haven't turned over go in straight away. Anything not handed out after 2 minutes is given anyway. If you leave the server mid-pack, the rest are posted to your parcel locker.
- New item: `ascard_shrinkwrap` (in `install/ox_inventory_items_extras.lua`, image `ascard_shrinkwrap.png`). New tables are made automatically (also in `sql/install.sql`).

## Props, sounds and pack ripping
- **Props** (in `stream/`): `ascardpack` in your hand while opening a pack, `asboosterbox` while opening a booster box, and `as_cardbinder` while the binder is open. There is no model for a single card yet.
- **Sounds** (`html/sounds/`): snap (rip), dealfour (deal), flip, badge (rare pulls) and boxopen. Volume and on/off are in `Config.Sounds`.
- **Ripping**: packs open in a 3D foil pack. Drag along the top to tear the strip off, then the cards slide out. The pack art is `Config.PackArt`, and each pack can set its own `art`.
- **Booster box**: the `ascard_booster_box` item gives `Config.BoosterBox.gives` packs. It's switched off until you point it at a pack of your own.

## Card types
| Type | Item | Effect |
|---|---|---|
| Common | `ascard_player` | Matte |
| Uncommon | `ascard_star` | Silver shine sweep |
| Rare | `ascard_captain` | Gold shine sweep |
| Epic | `ascard_winner` | Gold glitter, shine sweep, light follows the mouse |
| Legendary | `ascard_century` | Rainbow holo that shifts with the mouse, glitter |
| Mythic | `ascard_legend` | Black and gold, gold glitter, sweep, edge glow, limited prints |
| Foil (any type) | same item | Rainbow holo and glitter on top |

Colours, effects, sell values and pack drop weights are all in `config/config.lua` (`Config.Types`, `Config.Packs`).

## The cards
- `config/cards.lua` is intentionally empty (no clubs, no cards). Add your own cards in `custom/cards.json` / `custom/cards.lua`; they join the pack pools automatically.
- The first 45 cards keep their old ids, so any cards players already have still work.

## Player photos
Each card looks for a photo in this order:
1. `html/img/players/<cardId>.png`, `.jpg` or `.webp` in the resource
2. `Config.PhotoUrl` (hosted online), with `{id}` replaced by the card id, e.g. `https://your-host.com/cards/{id}.jpg`
3. A plain silhouette in the club colours

The card id is the key in your card file (`custom/cards.json` or `custom/cards.lua`). Name each photo after its card id, upload them all to one folder on any image host (Fivemanage, an R2/S3 bucket, a GitHub repo), and set `Config.PhotoUrl`. Portrait photos around 700 px wide work best.

## Adding your own series
Nothing is built in: no cards, no sets and no packs. You make everything.

1. **Make the cards** in the website's Card Creator and put the output in `custom/cards.json` or `custom/cards.lua` (see `custom/README.txt`). Cards go into the set named by their `set` field (default `series2`).
2. **Define the series** in a config file, e.g. `config/series2.lua` (it already does this for Series 2, Creatures and Los Santos):
   ```lua
   Config.Sets.myseries = { label = 'My Series', code = 'MS', hidden = true }   -- hidden until staff switch it on in /cardadmin
   Config.Packs['ascard_ms_booster'] = {
       label = 'My Series Booster', set = 'myseries', cards = 5,
       weights = { player = 70, star = 20, captain = 6, winner = 3, century = 0.8, legend = 0.2 },
       guaranteed = { count = 1, minRarity = 'star' },
       foilChance = 0.05,
   }
   ```
3. **Add the pack item** to your inventory (copy an entry from `install/ox_inventory_items_v3.lua`), give it an icon in `html/img/items/`, and add it to the shop list (`Config.Series2.shop` or `Config.Shop.items`).
4. **Make the pack art** in the website's Pack Creator and set it with `Config.Packs['ascard_ms_booster'].art = 'img/my_pack.png'`.

Until you have made cards and a pack, players have nothing to buy or open. Boxes (`Config.Boxes`), the booster box and releases (`Config.Releases`) are empty too; their config files have examples.

## Commands (ace: `group.admin`)
| Command | |
|---|---|
| `/givecard [id] [cardId] [foil 0/1]` | Mints a real card with a serial |
| `/givepack [id] [pack] [count]` | Gives packs |
| `/previewcard [cardId] [foil] [grade]` | Shows how a card looks, without giving an item |
| `/cardprints` | Print counts for every card |
| `/cardadmin` | Admin panel |
| `/cardreport` | Post the market report to Discord now |

## Security notes
- There are no client → server item events. Buying, selling and grading go through callbacks that check the player is next to the right NPC.
- Items are re-checked by slot **and serial** before anything is removed. This stops slot-swap tricks while a menu is open.
- `/testcard` from v1 (usable by anyone) is gone. `/previewcard` is admin only.

## Migrating

## Migrating from v1
- Old `ascard_psa` items with a card stored in a `psa_<serial>` stash (qb-inventory `stashitemsnew`) are **not** migrated automatically. Give those cards back from the stash table if players have any.

## v3 (battles, trader, card shop job, skins)
All new tables are created automatically on start. Everything below is switched on or tuned in `config/battle.lua`, `config/trader.lua`, `config/cardshop.lua`, `config/series2.lua` and `config/custom.lua`.

**Fill these in before it works**
- `Config.Trader.ped.coords`: where the NPC trader and collector desk stand (the trader stays off while it is `vec4(0,0,0,0)`).
- `Config.CardShop.counter` and `managerDesk`: the player shop counter and manager desk. Make a job `cardshop` with grades staff (0), manager (2), owner (4) in your framework, or change `Config.CardShop.grades`.
- `Config.CardShop` society settings if you use a banking resource. The till has an internal fallback, so it works without one.
- `Config.Season.start`: first day of season one (unix time).
- Items: `install/ox_inventory_items_v3.lua` (or `qb-core_items_v3.lua`) plus the PNGs in `html/img/items`.

**What is in it**
- Deck box (`ascard_deckbox`): 30 raw cards, max 2 copies, 1 Mythic.
- Battle table (`ascard_table`): place it anywhere, host a game, a second player joins, others spectate. Wagers up to £50,000. 4,000 life, 10 minute cap.
- Ranks and 4-week seasons with a leaderboard (`/cardrank`). Staff tournaments: `/cardtourney`, players join with `/jointourney`.
- NPC trader: quantity, condition and sidegrade swaps with daily rates (10 swaps a day) and the collector desk with daily cash wants and a weekly brand week.
- Player card shop job: stock, prices (70% to 140% of market), buy list (50% to 90%), grading for customers, wholesale for the owner, hourly pay plus commission. The NPC shop and trader step back while someone is on duty.
- Series 2 is hidden until staff switch it on in `/cardadmin`. Cards and playmats from your creators load from `custom/` (see `custom/README.txt`).
- Binder covers (`/cardskins`), 8 slab label skins, hold a card in hand (`/cardhand`), and gift a card as a Postal Prime parcel.
- Giving a card to someone is plain ox_inventory hand-over. There is no trade window.


### Themes
Card Creator supports Football, Creatures (original) and Los Santos. Each theme is its own set with its own booster
(`ascard_s2_booster`, `ascard_cr_booster`, `ascard_ls_booster`). All are released by the single Series 2 admin switch
once the set has cards. See custom/README.txt.
