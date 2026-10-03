# Travel legs to measure in game

Which runs between two NPCs or objects the timing plans actually use, most used first, so the hand measurements that matter most get done first. Generated 2026-09-26 from the local database (WoW: Forever build 1.60.1.69977, prices from the Classic Beta PvE auction house).

## How this was counted

- Each city was timed on its own (`TimeModel(config, city)`), for every recipe the ranking returns, in four setups per city: browsing without characters (every recipe, one crafter) and the local characters of that city's faction (unlearned recipes included), each at a time value of 0 and of 50 gold per hour (which changes which plan is picked).
- A leg counts once per timed plan whose route (`Timing.legs`) runs between the two points, in either direction (a measured time is stored per unordered pair).
- **Used by** is the share of *profitable* timed plans in that city whose route contains the leg; *all plans* and *top 200* (the 200 best by profit per hour in each setup) are for comparison.
- **Est.** is the current straight-line estimate: distance x detour (1.3, or the city's own) / 7 yd/s on foot. Short legs matter little even when common: an error on a 3 s run can't be large.
- Coordinates are the zone map's (the ones addons like TomTom show). No leg is measured yet (every preset's `overrides.travel` is empty).

Enter a measurement in the city's `data/forever/cities/<City>.json` as `"overrides": {"travel": {"<id a>|<id b>": <seconds>}}` (either order); it replaces the estimate whatever the run speed. Measure on foot at 7 yd/s, or note the speed. Once a few are in, routes can change, so re-count before the next round.

## Top 40 across all cities

| # | City | From | To | Used by | Est. |
|---|---|---|---|---:|---:|
| 1 | Darnassus | Auctioneer Golothas (56.2, 54.0) `ah` | Mailbox (41.6, 41.8) `mailbox:32822` | 95% | 33 s |
| 2 | Ironforge | Auctioneer Redmuse (24.2, 74.7) `ah` | Mailbox (33.2, 64.7) `mailbox:866` | 91% | 17 s |
| 3 | Undercity | Auctioneer Stockton (71.4, 46.7) `ah` | Mailbox (68.2, 38.3) `mailbox:17985` | 89% | 12 s |
| 4 | Stormwind | Auctioneer Fitch (61.2, 71.3) `ah` | Mailbox (61.6, 76.1) `mailbox:26387` | 88% | 10 s |
| 5 | Thunder Bluff | Auctioneer Stampi (40.4, 51.8) `ah` | Mailbox (45.2, 59.4) `mailbox:20426` | 87% | 14 s |
| 6 | Ironforge | Mailbox (33.2, 64.7) `mailbox:866` | Fillius Fizzlespinner (38.1, 73.7) `vendor:5100` | 60% | 11 s |
| 7 | Orgrimmar | Auctioneer Thathung (55.9, 62.7) `ah` | Mailbox (62.3, 40.5) `mailbox:10968` | 54% | 42 s |
| 8 | Undercity | Mailbox (68.2, 38.3) `mailbox:17985` | Felicia Doan (64.1, 50.6) `vendor:4775` | 53% | 16 s |
| 9 | Thunder Bluff | Mailbox (45.2, 59.4) `mailbox:20426` | Mahu (43.8, 45.1) `vendor:3005` | 51% | 19 s |
| 10 | Thunder Bluff | Auctioneer Stampi (40.4, 51.8) `ah` | Mahu (43.8, 45.1) `vendor:3005` | 51% | 11 s |
| 11 | Ironforge | Auctioneer Redmuse (24.2, 74.7) `ah` | Fillius Fizzlespinner (38.1, 73.7) `vendor:5100` | 50% | 21 s |
| 12 | Orgrimmar | Auctioneer Thathung (55.9, 62.7) `ah` | Borya (63.1, 51.4) `vendor:3364` | 47% | 27 s |
| 13 | Orgrimmar | Mailbox (62.3, 40.5) `mailbox:10968` | Borya (63.1, 51.4) `vendor:3364` | 46% | 19 s |
| 14 | Undercity | Auctioneer Stockton (71.4, 46.7) `ah` | Felicia Doan (64.1, 50.6) `vendor:4775` | 45% | 14 s |
| 15 | Stormwind | Auctioneer Fitch (61.2, 71.3) `ah` | Edna Mullby (64.7, 71.3) `vendor:1286` | 40% | 11 s |
| 16 | Stormwind | Mailbox (61.6, 76.1) `mailbox:26387` | Edna Mullby (64.7, 71.3) `vendor:1286` | 40% | 14 s |
| 17 | Orgrimmar | Auctioneer Thathung (55.9, 62.7) `ah` | Mailbox (50.7, 70.4) `mailbox:10107` | 38% | 19 s |
| 18 | Darnassus | Mailbox (41.6, 41.8) `mailbox:32822` | Saenorion (63.7, 22.3) `vendor:4225` | 31% | 51 s |
| 19 | Darnassus | Auctioneer Golothas (56.2, 54.0) `ah` | Saenorion (63.7, 22.3) `vendor:4225` | 30% | 44 s |
| 20 | Darnassus | Mailbox (41.6, 41.8) `mailbox:32822` | Chardryn (48.5, 69.0) `vendor:4216` | 21% | 38 s |
| 21 | Darnassus | Auctioneer Golothas (56.2, 54.0) `ah` | Chardryn (48.5, 69.0) `vendor:4216` | 20% | 25 s |
| 22 | Stormwind | Mailbox (61.6, 76.1) `mailbox:26387` | Keldric Boucher (62.8, 75.0) `vendor:1257` | 19% | 4 s |
| 23 | Thunder Bluff | Auctioneer Stampi (40.4, 51.8) `ah` | Anvil (38.8, 56.1) `anvil:18124` | 18% | 7 s |
| 24 | Orgrimmar | Auctioneer Thathung (55.9, 62.7) `ah` | Anvil (79.7, 23.1) `anvil:10187` | 17% | 93 s |
| 25 | Stormwind | Auctioneer Fitch (61.2, 71.3) `ah` | Keldric Boucher (62.8, 75.0) `vendor:1257` | 17% | 10 s |
| 26 | Undercity | Auctioneer Stockton (71.4, 46.7) `ah` | Anvil (61.1, 30.6) `anvil:44941` | 17% | 26 s |
| 27 | Thunder Bluff | Mailbox (45.2, 59.4) `mailbox:20426` | Shadi Mistrunner (40.6, 64.0) `vendor:8363` | 17% | 11 s |
| 28 | Thunder Bluff | Auctioneer Stampi (40.4, 51.8) `ah` | Shadi Mistrunner (40.6, 64.0) `vendor:8363` | 15% | 16 s |
| 29 | Undercity | Forge (62.2, 30.2) `forge:44917` | Mailbox (68.2, 38.3) `mailbox:17985` | 14% | 15 s |
| 30 | Darnassus | Auctioneer Golothas (56.2, 54.0) `ah` | Forge (59.6, 45.7) `forge:49803` | 13% | 13 s |
| 31 | Undercity | Auctioneer Stockton (71.4, 46.7) `ah` | Joseph Moore (70.1, 58.4) `vendor:4589` | 13% | 14 s |
| 32 | Undercity | Mailbox (68.2, 38.3) `mailbox:17985` | Joseph Moore (70.1, 58.4) `vendor:4589` | 13% | 24 s |
| 33 | Ironforge | Mailbox (33.2, 64.7) `mailbox:866` | Bombus Finespindle (39.6, 34.5) `vendor:5128` | 12% | 31 s |
| 34 | Orgrimmar | Mailbox (50.7, 70.4) `mailbox:10107` | Shimra (47.9, 80.3) `vendor:5817` | 12% | 19 s |
| 35 | Orgrimmar | Anvil (79.7, 23.1) `anvil:10187` | Forge (71.8, 27.0) `forge:10054` | 12% | 22 s |
| 36 | Thunder Bluff | Anvil (38.8, 56.1) `anvil:18124` | Thunder Bluff Forge (39.5, 56.1) `forge:18126` | 12% | 1 s |
| 37 | Undercity | Anvil (61.1, 30.6) `anvil:44941` | Forge (62.2, 30.2) `forge:44917` | 12% | 2 s |
| 38 | Stormwind | Anvil (63.7, 36.7) `anvil:13810` | Forge (62.8, 37.2) `forge:13970` | 11% | 3 s |
| 39 | Stormwind | Auctioneer Fitch (61.2, 71.3) `ah` | Anvil (63.7, 36.7) `anvil:13810` | 11% | 75 s |
| 40 | Ironforge | Dwarven Brazier (33.6, 65.1) `cooking_fire:867` | Mailbox (33.2, 64.7) `mailbox:866` | 10% | 1 s |

## Per city

Every leg used by at least one profitable plan, grouped by city so a round of measuring can stay in one place.

### Darnassus (Alliance)

824 profitable timed plans (2876 in all, 537 top-200). Hub: `ah`.

| # | From | To | Used by | All plans | Top 200 | Est. |
|---|---|---|---:|---:|---:|---:|
| 1 | Auctioneer Golothas (56.2, 54.0) `ah` | Mailbox (41.6, 41.8) `mailbox:32822` | 95% | 89% | 95% | 33 s |
| 2 | Mailbox (41.6, 41.8) `mailbox:32822` | Saenorion (63.7, 22.3) `vendor:4225` | 31% | 28% | 29% | 51 s |
| 3 | Auctioneer Golothas (56.2, 54.0) `ah` | Saenorion (63.7, 22.3) `vendor:4225` | 30% | 21% | 26% | 44 s |
| 4 | Mailbox (41.6, 41.8) `mailbox:32822` | Chardryn (48.5, 69.0) `vendor:4216` | 21% | 21% | 25% | 38 s |
| 5 | Auctioneer Golothas (56.2, 54.0) `ah` | Chardryn (48.5, 69.0) `vendor:4216` | 20% | 14% | 24% | 25 s |
| 6 | Auctioneer Golothas (56.2, 54.0) `ah` | Forge (59.6, 45.7) `forge:49803` | 13% | 10% | 12% | 13 s |
| 7 | Auctioneer Golothas (56.2, 54.0) `ah` | Stove (48.5, 20.9) `cooking_fire:49526` | 10% | 5% | 12% | 46 s |
| 8 | Forge (59.6, 45.7) `forge:49803` | Mailbox (41.6, 41.8) `mailbox:32822` | 8% | 11% | 7% | 36 s |
| 9 | Stove (48.5, 20.9) `cooking_fire:49526` | Mailbox (41.6, 41.8) `mailbox:32822` | 8% | 7% | 8% | 31 s |
| 10 | Stove (48.5, 20.9) `cooking_fire:49526` | Fyldan (48.5, 21.6) `vendor:4223` | 7% | 9% | 7% | 1 s |
| 11 | Mailbox (41.6, 41.8) `mailbox:32822` | Mythrin'dir (61.0, 17.7) `vendor:4229` | 6% | 4% | 5% | 50 s |
| 12 | Mailbox (41.6, 41.8) `mailbox:32822` | Fyldan (48.5, 21.6) `vendor:4223` | 6% | 6% | 7% | 30 s |
| 13 | Forge (59.6, 45.7) `forge:49803` | Mythrin'dir (61.0, 17.7) `vendor:4229` | 5% | 3% | 4% | 37 s |
| 14 | Auctioneer Golothas (56.2, 54.0) `ah` | Ellandrieth (64.7, 53.0) `vendor:4170` | 4% | 2% | 4% | 17 s |
| 15 | Mailbox (41.6, 41.8) `mailbox:32822` | Ellandrieth (64.7, 53.0) `vendor:4170` | 3% | 2% | 3% | 48 s |
| 16 | Auctioneer Golothas (56.2, 54.0) `ah` | Mythrin'dir (61.0, 17.7) `vendor:4229` | 2% | 1% | 2% | 49 s |
| 17 | Forge (59.6, 45.7) `forge:49803` | Saenorion (63.7, 22.3) `vendor:4225` | 1% | 0% | 1% | 32 s |
| 18 | Mailbox (41.6, 41.8) `mailbox:32822` | Elynna (64.6, 21.6) `vendor:4168` | 1% | 1% | 1% | 52 s |
| 19 | Auctioneer Golothas (56.2, 54.0) `ah` | Elynna (64.6, 21.6) `vendor:4168` | 1% | 1% | 1% | 46 s |
| 20 | Ellandrieth (64.7, 53.0) `vendor:4170` | Chardryn (48.5, 69.0) `vendor:4216` | 0% | 0% | 1% | 38 s |
| 21 | Auctioneer Golothas (56.2, 54.0) `ah` | Fyldan (48.5, 21.6) `vendor:4223` | 0% | 0% | 1% | 45 s |
| 22 | Mailbox (41.6, 41.8) `mailbox:32822` | Cyroen (33.8, 9.5) `vendor:4220` | 0% | 0% | 0% | 45 s |
| 23 | Auctioneer Golothas (56.2, 54.0) `ah` | Cyroen (33.8, 9.5) `vendor:4220` | 0% | 0% | 0% | 73 s |
| 24 | Auctioneer Golothas (56.2, 54.0) `ah` | Cylania (59.2, 46.4) `vendor:4164` | 0% | 1% | 0% | 12 s |
| 25 | Ellandrieth (64.7, 53.0) `vendor:4170` | Saenorion (63.7, 22.3) `vendor:4225` | 0% | 0% | 0% | 40 s |
| 26 | Stove (48.5, 20.9) `cooking_fire:49526` | Saenorion (63.7, 22.3) `vendor:4225` | 0% | 0% | 0% | 30 s |
| 27 | Stove (48.5, 20.9) `cooking_fire:49526` | Innkeeper Saelienne (67.4, 15.6) `vendor:6735` | 0% | 0% | 0% | 38 s |
| 28 | Mailbox (41.6, 41.8) `mailbox:32822` | Innkeeper Saelienne (67.4, 15.6) `vendor:6735` | 0% | 0% | 0% | 61 s |
| 29 | Mailbox (41.6, 41.8) `mailbox:32822` | Voloren (46.9, 57.0) `vendor:4222` | 0% | 8% | 0% | 22 s |
| 30 | Forge (59.6, 45.7) `forge:49803` | Cylania (59.2, 46.4) `vendor:4164` | 0% | 5% | 0% | 1 s |
| 31 | Auctioneer Golothas (56.2, 54.0) `ah` | Kyrai (32.5, 19.7) `vendor:3561` | 0% | 1% | 0% | 65 s |
| 32 | Mailbox (41.6, 41.8) `mailbox:32822` | Cylania (59.2, 46.4) `vendor:4164` | 0% | 1% | 0% | 35 s |
| 33 | Fyldan (48.5, 21.6) `vendor:4223` | Saenorion (63.7, 22.3) `vendor:4225` | 0% | 0% | 0% | 30 s |
| 34 | Cylania (59.2, 46.4) `vendor:4164` | Fyldan (48.5, 21.6) `vendor:4223` | 0% | 0% | 0% | 39 s |
| 35 | Auctioneer Golothas (56.2, 54.0) `ah` | Voloren (46.9, 57.0) `vendor:4222` | 0% | 0% | 0% | 19 s |

### Ironforge (Alliance)

841 profitable timed plans (2876 in all, 540 top-200). Hub: `ah`.

| # | From | To | Used by | All plans | Top 200 | Est. |
|---|---|---|---:|---:|---:|---:|
| 1 | Auctioneer Redmuse (24.2, 74.7) `ah` | Mailbox (33.2, 64.7) `mailbox:866` | 91% | 94% | 88% | 17 s |
| 2 | Mailbox (33.2, 64.7) `mailbox:866` | Fillius Fizzlespinner (38.1, 73.7) `vendor:5100` | 60% | 47% | 56% | 11 s |
| 3 | Auctioneer Redmuse (24.2, 74.7) `ah` | Fillius Fizzlespinner (38.1, 73.7) `vendor:5100` | 50% | 30% | 48% | 21 s |
| 4 | Mailbox (33.2, 64.7) `mailbox:866` | Bombus Finespindle (39.6, 34.5) `vendor:5128` | 12% | 10% | 15% | 31 s |
| 5 | Dwarven Brazier (33.6, 65.1) `cooking_fire:867` | Mailbox (33.2, 64.7) `mailbox:866` | 10% | 6% | 13% | 1 s |
| 6 | Anvil (52.4, 42.3) `anvil:5459` | Forge (52.7, 45.2) `forge:5430` | 10% | 12% | 9% | 3 s |
| 7 | Auctioneer Redmuse (24.2, 74.7) `ah` | Bombus Finespindle (39.6, 34.5) `vendor:5128` | 10% | 5% | 12% | 45 s |
| 8 | Auctioneer Redmuse (24.2, 74.7) `ah` | Anvil (52.4, 42.3) `anvil:5459` | 10% | 8% | 9% | 52 s |
| 9 | Auctioneer Redmuse (24.2, 74.7) `ah` | Dwarven Brazier (33.6, 65.1) `cooking_fire:867` | 10% | 5% | 12% | 17 s |
| 10 | Forge (52.7, 45.2) `forge:5430` | Mailbox (33.2, 64.7) `mailbox:866` | 7% | 10% | 6% | 34 s |
| 11 | Auctioneer Redmuse (24.2, 74.7) `ah` | The Great Anvil (49.8, 43.6) `anvil:6866` | 7% | 8% | 8% | 48 s |
| 12 | The Great Anvil (49.8, 43.6) `anvil:6866` | Mailbox (33.2, 64.7) `mailbox:866` | 5% | 9% | 6% | 32 s |
| 13 | Forge (52.7, 45.2) `forge:5430` | Fillius Fizzlespinner (38.1, 73.7) `vendor:5100` | 5% | 3% | 3% | 35 s |
| 14 | Auctioneer Redmuse (24.2, 74.7) `ah` | Bryllia Ironbrand (39.2, 74.5) `vendor:5101` | 3% | 1% | 4% | 22 s |
| 15 | Dwarven Brazier (39.5, 72.3) `cooking_fire:762` | Bryllia Ironbrand (39.2, 74.5) `vendor:5101` | 3% | 5% | 2% | 2 s |
| 16 | Dwarven Brazier (39.5, 72.3) `cooking_fire:762` | Fillius Fizzlespinner (38.1, 73.7) `vendor:5100` | 3% | 4% | 2% | 2 s |
| 17 | Auctioneer Redmuse (24.2, 74.7) `ah` | Forge (52.7, 45.2) `forge:5430` | 2% | 1% | 1% | 51 s |
| 18 | Mailbox (33.2, 64.7) `mailbox:866` | Bryllia Ironbrand (39.2, 74.5) `vendor:5101` | 2% | 2% | 2% | 13 s |
| 19 | The Great Anvil (49.8, 43.6) `anvil:6866` | Fillius Fizzlespinner (38.1, 73.7) `vendor:5100` | 2% | 1% | 1% | 34 s |
| 20 | Forge (51.0, 36.7) `forge:5258` | Bombus Finespindle (39.6, 34.5) `vendor:5128` | 1% | 0% | 1% | 17 s |
| 21 | Mailbox (21.0, 52.4) `mailbox:1564` | Gwenna Firebrew (18.6, 51.8) `vendor:5112` | 1% | 1% | 1% | 3 s |
| 22 | Auctioneer Redmuse (24.2, 74.7) `ah` | Gwenna Firebrew (18.6, 51.8) `vendor:5112` | 1% | 1% | 1% | 24 s |
| 23 | Fillius Fizzlespinner (38.1, 73.7) `vendor:5100` | Bryllia Ironbrand (39.2, 74.5) `vendor:5101` | 1% | 1% | 1% | 2 s |
| 24 | Fillius Fizzlespinner (38.1, 73.7) `vendor:5100` | Bombus Finespindle (39.6, 34.5) `vendor:5128` | 1% | 1% | 1% | 38 s |
| 25 | The Great Anvil (49.8, 43.6) `anvil:6866` | Bombus Finespindle (39.6, 34.5) `vendor:5128` | 1% | 0% | 1% | 17 s |
| 26 | Auctioneer Redmuse (24.2, 74.7) `ah` | Anvil (52.5, 41.7) `anvil:5453` | 1% | 0% | 1% | 53 s |
| 27 | Anvil (52.5, 41.7) `anvil:5453` | Forge (51.0, 36.7) `forge:5258` | 1% | 0% | 1% | 5 s |
| 28 | Dwarven Brazier (33.6, 65.1) `cooking_fire:867` | Katrina Shimmerstar (34.1, 66.2) `vendor:15353` | 0% | 2% | 0% | 1 s |
| 29 | Dwarven Brazier (21.0, 54.6) `cooking_fire:1566` | Mailbox (21.0, 52.4) `mailbox:1564` | 0% | 0% | 1% | 2 s |
| 30 | Mailbox (33.2, 64.7) `mailbox:866` | Macey Jinglepocket (33.6, 67.7) `vendor:13434` | 0% | 0% | 0% | 3 s |
| 31 | Mailbox (33.2, 64.7) `mailbox:866` | Barim Jurgenstaad (19.2, 56.1) `vendor:5110` | 0% | 0% | 0% | 22 s |
| 32 | Auctioneer Redmuse (24.2, 74.7) `ah` | Barim Jurgenstaad (19.2, 56.1) `vendor:5110` | 0% | 0% | 0% | 20 s |
| 33 | Auctioneer Redmuse (24.2, 74.7) `ah` | Dwarven Brazier (21.0, 54.6) `cooking_fire:1566` | 0% | 0% | 1% | 20 s |
| 34 | Auctioneer Redmuse (24.2, 74.7) `ah` | Macey Jinglepocket (33.6, 67.7) `vendor:13434` | 0% | 0% | 0% | 15 s |
| 35 | Auctioneer Redmuse (24.2, 74.7) `ah` | Forge (51.0, 36.7) `forge:5258` | 0% | 0% | 1% | 54 s |
| 36 | Mailbox (33.2, 64.7) `mailbox:866` | Gwina Stonebranch (55.1, 59.5) `vendor:5138` | 0% | 1% | 0% | 33 s |
| 37 | Auctioneer Redmuse (24.2, 74.7) `ah` | Tynnus Venomsprout (53.0, 13.7) `vendor:5169` | 0% | 1% | 0% | 73 s |
| 38 | Mailbox (21.0, 52.4) `mailbox:1564` | Fillius Fizzlespinner (38.1, 73.7) `vendor:5100` | 0% | 1% | 0% | 33 s |
| 39 | Bryllia Ironbrand (39.2, 74.5) `vendor:5101` | Gwina Stonebranch (55.1, 59.5) `vendor:5138` | 0% | 0% | 0% | 27 s |
| 40 | Anvil (52.4, 42.3) `anvil:5459` | Thurgrum Deepforge (51.7, 42.8) `vendor:4259` | 0% | 4% | 0% | 1 s |
| 41 | The Great Anvil (49.8, 43.6) `anvil:6866` | Thurgrum Deepforge (51.7, 42.8) `vendor:4259` | 0% | 3% | 0% | 3 s |

### Stormwind (Alliance)

817 profitable timed plans (2876 in all, 537 top-200). Hub: `ah`.

| # | From | To | Used by | All plans | Top 200 | Est. |
|---|---|---|---:|---:|---:|---:|
| 1 | Auctioneer Fitch (61.2, 71.3) `ah` | Mailbox (61.6, 76.1) `mailbox:26387` | 88% | 88% | 86% | 10 s |
| 2 | Auctioneer Fitch (61.2, 71.3) `ah` | Edna Mullby (64.7, 71.3) `vendor:1286` | 40% | 29% | 35% | 11 s |
| 3 | Mailbox (61.6, 76.1) `mailbox:26387` | Edna Mullby (64.7, 71.3) `vendor:1286` | 40% | 35% | 32% | 14 s |
| 4 | Mailbox (61.6, 76.1) `mailbox:26387` | Keldric Boucher (62.8, 75.0) `vendor:1257` | 19% | 15% | 24% | 4 s |
| 5 | Auctioneer Fitch (61.2, 71.3) `ah` | Keldric Boucher (62.8, 75.0) `vendor:1257` | 17% | 7% | 22% | 10 s |
| 6 | Anvil (63.7, 36.7) `anvil:13810` | Forge (62.8, 37.2) `forge:13970` | 11% | 13% | 9% | 3 s |
| 7 | Auctioneer Fitch (61.2, 71.3) `ah` | Anvil (63.7, 36.7) `anvil:13810` | 11% | 8% | 9% | 75 s |
| 8 | Warm Fire (78.5, 52.5) `cooking_fire:26516` | Mailbox (74.5, 55.4) `mailbox:26463` | 9% | 7% | 10% | 14 s |
| 9 | Mailbox (74.5, 55.4) `mailbox:26463` | Edna Mullby (64.7, 71.3) `vendor:1286` | 9% | 7% | 10% | 47 s |
| 10 | Forge (62.8, 37.2) `forge:13970` | Mailbox (61.6, 76.1) `mailbox:26387` | 8% | 10% | 6% | 84 s |
| 11 | Auctioneer Fitch (61.2, 71.3) `ah` | Anvil (63.8, 37.1) `anvil:13812` | 7% | 7% | 8% | 74 s |
| 12 | Auctioneer Fitch (61.2, 71.3) `ah` | Warm Fire (78.5, 52.5) `cooking_fire:26516` | 6% | 2% | 7% | 69 s |
| 13 | Forge (62.8, 37.2) `forge:13970` | Edna Mullby (64.7, 71.3) `vendor:1286` | 5% | 3% | 4% | 73 s |
| 14 | Mailbox (61.6, 76.1) `mailbox:26387` | Alexandra Bolero (53.1, 81.8) `vendor:1347` | 5% | 4% | 8% | 30 s |
| 15 | Auctioneer Fitch (61.2, 71.3) `ah` | Alexandra Bolero (53.1, 81.8) `vendor:1347` | 5% | 2% | 7% | 34 s |
| 16 | Auctioneer Fitch (61.2, 71.3) `ah` | Warm Fire (51.3, 96.2) `cooking_fire:944` | 4% | 2% | 5% | 62 s |
| 17 | Anvil (63.8, 37.1) `anvil:13812` | Mailbox (61.6, 76.1) `mailbox:26387` | 4% | 9% | 5% | 84 s |
| 18 | Warm Fire (78.5, 52.5) `cooking_fire:26516` | Erika Tate (78.5, 52.9) `vendor:5483` | 3% | 5% | 2% | 1 s |
| 19 | Warm Fire (51.3, 96.2) `cooking_fire:944` | Mailbox (61.6, 76.1) `mailbox:26387` | 3% | 3% | 2% | 55 s |
| 20 | Anvil (63.8, 37.1) `anvil:13812` | Edna Mullby (64.7, 71.3) `vendor:1286` | 3% | 2% | 2% | 74 s |
| 21 | Auctioneer Fitch (61.2, 71.3) `ah` | Forge (62.8, 37.2) `forge:13970` | 3% | 1% | 1% | 73 s |
| 22 | Auctioneer Fitch (61.2, 71.3) `ah` | Innkeeper Allison (60.4, 75.3) `vendor:6740` | 1% | 2% | 2% | 9 s |
| 23 | Warm Fire (51.3, 96.2) `cooking_fire:944` | Mailbox (50.6, 89.7) `mailbox:42913` | 1% | 1% | 2% | 14 s |
| 24 | Mailbox (50.6, 89.7) `mailbox:42913` | Innkeeper Allison (60.4, 75.3) `vendor:6740` | 1% | 1% | 2% | 44 s |
| 25 | Auctioneer Fitch (61.2, 71.3) `ah` | Thurman Mullby (64.8, 72.2) `vendor:1285` | 1% | 1% | 1% | 12 s |
| 26 | Mailbox (61.6, 76.1) `mailbox:26387` | Thurman Mullby (64.8, 72.2) `vendor:1285` | 1% | 1% | 0% | 13 s |
| 27 | Warm Fire (51.3, 96.2) `cooking_fire:944` | Joachim Brenlow (51.4, 94.1) `vendor:1311` | 0% | 3% | 0% | 4 s |
| 28 | Auctioneer Fitch (61.2, 71.3) `ah` | Khole Jinglepocket (62.2, 70.1) `vendor:13435` | 0% | 1% | 0% | 4 s |
| 29 | Mailbox (61.6, 76.1) `mailbox:26387` | Innkeeper Allison (60.4, 75.3) `vendor:6740` | 0% | 0% | 1% | 4 s |
| 30 | Warm Fire (51.3, 96.2) `cooking_fire:944` | Innkeeper Allison (60.4, 75.3) `vendor:6740` | 0% | 0% | 1% | 54 s |
| 31 | Keldric Boucher (62.8, 75.0) `vendor:1257` | Thurman Mullby (64.8, 72.2) `vendor:1285` | 0% | 0% | 1% | 9 s |
| 32 | Forge (62.8, 37.2) `forge:13970` | Alexandra Bolero (53.1, 81.8) `vendor:1347` | 0% | 0% | 1% | 101 s |
| 33 | Mailbox (61.6, 76.1) `mailbox:26387` | Roberto Pupellyverbos (60.0, 76.9) `vendor:277` | 0% | 0% | 0% | 6 s |
| 34 | Mailbox (61.6, 76.1) `mailbox:26387` | Khole Jinglepocket (62.2, 70.1) `vendor:13435` | 0% | 0% | 0% | 13 s |
| 35 | Mailbox (74.5, 55.4) `mailbox:26463` | Khole Jinglepocket (62.2, 70.1) `vendor:13435` | 0% | 0% | 0% | 51 s |
| 36 | Thurman Mullby (64.8, 72.2) `vendor:1285` | Edna Mullby (64.7, 71.3) `vendor:1286` | 0% | 0% | 0% | 2 s |
| 37 | Auctioneer Fitch (61.2, 71.3) `ah` | Roberto Pupellyverbos (60.0, 76.9) `vendor:277` | 0% | 0% | 0% | 13 s |
| 38 | Anvil (63.7, 36.7) `anvil:13810` | Kaita Deepforge (63.3, 37.7) `vendor:5512` | 0% | 4% | 0% | 3 s |
| 39 | Anvil (63.8, 37.1) `anvil:13812` | Kaita Deepforge (63.3, 37.7) `vendor:5512` | 0% | 4% | 0% | 2 s |
| 40 | Auctioneer Fitch (61.2, 71.3) `ah` | Sloan McCoy (78.6, 70.9) `vendor:1326` | 0% | 1% | 0% | 56 s |
| 41 | Forge (62.8, 37.2) `forge:13970` | Keldric Boucher (62.8, 75.0) `vendor:1257` | 0% | 0% | 0% | 81 s |

### Orgrimmar (Horde)

1094 profitable timed plans (4054 in all, 775 top-200). Hub: `ah`.

| # | From | To | Used by | All plans | Top 200 | Est. |
|---|---|---|---:|---:|---:|---:|
| 1 | Auctioneer Thathung (55.9, 62.7) `ah` | Mailbox (62.3, 40.5) `mailbox:10968` | 54% | 49% | 54% | 42 s |
| 2 | Auctioneer Thathung (55.9, 62.7) `ah` | Borya (63.1, 51.4) `vendor:3364` | 47% | 39% | 50% | 27 s |
| 3 | Mailbox (62.3, 40.5) `mailbox:10968` | Borya (63.1, 51.4) `vendor:3364` | 46% | 35% | 50% | 19 s |
| 4 | Auctioneer Thathung (55.9, 62.7) `ah` | Mailbox (50.7, 70.4) `mailbox:10107` | 38% | 35% | 39% | 19 s |
| 5 | Auctioneer Thathung (55.9, 62.7) `ah` | Anvil (79.7, 23.1) `anvil:10187` | 17% | 13% | 17% | 93 s |
| 6 | Mailbox (50.7, 70.4) `mailbox:10107` | Shimra (47.9, 80.3) `vendor:5817` | 12% | 11% | 10% | 19 s |
| 7 | Anvil (79.7, 23.1) `anvil:10187` | Forge (71.8, 27.0) `forge:10054` | 12% | 15% | 10% | 22 s |
| 8 | Forge (71.8, 27.0) `forge:10054` | Mailbox (62.3, 40.5) `mailbox:10968` | 10% | 13% | 9% | 34 s |
| 9 | Auctioneer Thathung (55.9, 62.7) `ah` | Shimra (47.9, 80.3) `vendor:5817` | 9% | 5% | 8% | 37 s |
| 10 | Anvil (79.7, 23.1) `anvil:10187` | Mailbox (62.3, 40.5) `mailbox:10968` | 7% | 15% | 9% | 55 s |
| 11 | Mailbox (50.7, 70.4) `mailbox:10107` | Xen'to (57.6, 52.9) `vendor:3400` | 5% | 3% | 6% | 36 s |
| 12 | Forge (71.8, 27.0) `forge:10054` | Mailbox (50.7, 70.4) `mailbox:10107` | 5% | 3% | 4% | 93 s |
| 13 | Auctioneer Thathung (55.9, 62.7) `ah` | Tamar (63.0, 45.5) `vendor:3366` | 4% | 3% | 3% | 35 s |
| 14 | Mighty Blaze (57.0, 53.2) `cooking_fire:9912` | Xen'to (57.6, 52.9) `vendor:3400` | 4% | 2% | 6% | 2 s |
| 15 | Auctioneer Thathung (55.9, 62.7) `ah` | Mighty Blaze (57.0, 53.2) `cooking_fire:9912` | 4% | 2% | 6% | 17 s |
| 16 | Mailbox (62.3, 40.5) `mailbox:10968` | Tamar (63.0, 45.5) `vendor:3366` | 4% | 2% | 3% | 9 s |
| 17 | Mighty Blaze (50.4, 69.2) `cooking_fire:10995` | Mailbox (50.7, 70.4) `mailbox:10107` | 3% | 3% | 3% | 2 s |
| 18 | Auctioneer Thathung (55.9, 62.7) `ah` | Mighty Blaze (50.4, 69.2) `cooking_fire:10995` | 3% | 2% | 3% | 18 s |
| 19 | Auctioneer Thathung (55.9, 62.7) `ah` | Xen'to (57.6, 52.9) `vendor:3400` | 3% | 4% | 2% | 18 s |
| 20 | Auctioneer Thathung (55.9, 62.7) `ah` | Forge (71.8, 27.0) `forge:10054` | 3% | 1% | 2% | 75 s |
| 21 | Mailbox (62.3, 40.5) `mailbox:10968` | Xen'to (57.6, 52.9) `vendor:3400` | 2% | 4% | 1% | 25 s |
| 22 | Mighty Blaze (62.7, 40.5) `cooking_fire:10962` | Handor (62.9, 44.7) `vendor:3316` | 2% | 3% | 1% | 7 s |
| 23 | Mighty Blaze (62.7, 40.5) `cooking_fire:10962` | Mailbox (62.3, 40.5) `mailbox:10968` | 2% | 3% | 1% | 1 s |
| 24 | Anvil (79.7, 23.1) `anvil:10187` | Shimra (47.9, 80.3) `vendor:5817` | 2% | 1% | 2% | 129 s |
| 25 | Auctioneer Thathung (55.9, 62.7) `ah` | Barkeep Morag (54.6, 67.7) `vendor:5611` | 2% | 2% | 2% | 9 s |
| 26 | Mailbox (50.7, 70.4) `mailbox:10107` | Barkeep Morag (54.6, 67.7) `vendor:5611` | 2% | 2% | 2% | 11 s |
| 27 | Auctioneer Thathung (55.9, 62.7) `ah` | Trak'gen (48.1, 80.5) `vendor:3313` | 1% | 0% | 1% | 37 s |
| 28 | Mailbox (50.7, 70.4) `mailbox:10107` | Trak'gen (48.1, 80.5) `vendor:3313` | 1% | 0% | 1% | 19 s |
| 29 | Borya (63.1, 51.4) `vendor:3364` | Shimra (47.9, 80.3) `vendor:5817` | 1% | 1% | 0% | 64 s |
| 30 | Auctioneer Thathung (55.9, 62.7) `ah` | Horthus (45.4, 56.5) `vendor:3323` | 1% | 0% | 1% | 29 s |
| 31 | Anvil (79.7, 23.1) `anvil:10187` | Tumi (82.6, 23.6) `vendor:5812` | 0% | 10% | 0% | 8 s |
| 32 | Mailbox (62.3, 40.5) `mailbox:10968` | Handor (62.9, 44.7) `vendor:3316` | 0% | 10% | 1% | 7 s |
| 33 | Mighty Blaze (50.4, 69.2) `cooking_fire:10995` | Alowicious Czervik (52.2, 69.1) `vendor:14480` | 0% | 2% | 0% | 5 s |
| 34 | Horthus (45.4, 56.5) `vendor:3323` | Shimra (47.9, 80.3) `vendor:5817` | 0% | 0% | 0% | 42 s |
| 35 | Auctioneer Thathung (55.9, 62.7) `ah` | Mighty Blaze (62.5, 51.6) `cooking_fire:11582` | 0% | 0% | 1% | 26 s |
| 36 | Mighty Blaze (62.5, 51.6) `cooking_fire:11582` | Borya (63.1, 51.4) `vendor:3364` | 0% | 0% | 1% | 1 s |
| 37 | Auctioneer Thathung (55.9, 62.7) `ah` | Rekkul (42.1, 49.5) `vendor:3334` | 0% | 1% | 0% | 43 s |
| 38 | Mailbox (50.7, 70.4) `mailbox:10107` | Horthus (45.4, 56.5) `vendor:3323` | 0% | 0% | 0% | 28 s |
| 39 | Trak'gen (48.1, 80.5) `vendor:3313` | Borya (63.1, 51.4) `vendor:3364` | 0% | 0% | 0% | 64 s |
| 40 | Mailbox (50.7, 70.4) `mailbox:10107` | Shan'ti (37.4, 52.3) `vendor:3342` | 0% | 0% | 0% | 47 s |
| 41 | Auctioneer Thathung (55.9, 62.7) `ah` | Shan'ti (37.4, 52.3) `vendor:3342` | 0% | 0% | 0% | 52 s |
| 42 | Mailbox (50.7, 70.4) `mailbox:10107` | Alowicious Czervik (52.2, 69.1) `vendor:14480` | 0% | 6% | 0% | 5 s |
| 43 | Mailbox (50.7, 70.4) `mailbox:10107` | Rekkul (42.1, 49.5) `vendor:3334` | 0% | 1% | 0% | 43 s |
| 44 | Mailbox (50.7, 70.4) `mailbox:10107` | Tamar (63.0, 45.5) `vendor:3366` | 0% | 0% | 0% | 54 s |
| 45 | Borya (63.1, 51.4) `vendor:3364` | Xen'to (57.6, 52.9) `vendor:3400` | 0% | 0% | 0% | 15 s |
| 46 | Trak'gen (48.1, 80.5) `vendor:3313` | Shimra (47.9, 80.3) `vendor:5817` | 0% | 0% | 0% | 1 s |

### Thunder Bluff (Horde)

1100 profitable timed plans (4054 in all, 775 top-200). Hub: `ah`.

| # | From | To | Used by | All plans | Top 200 | Est. |
|---|---|---|---:|---:|---:|---:|
| 1 | Auctioneer Stampi (40.4, 51.8) `ah` | Mailbox (45.2, 59.4) `mailbox:20426` | 87% | 88% | 86% | 14 s |
| 2 | Mailbox (45.2, 59.4) `mailbox:20426` | Mahu (43.8, 45.1) `vendor:3005` | 51% | 43% | 53% | 19 s |
| 3 | Auctioneer Stampi (40.4, 51.8) `ah` | Mahu (43.8, 45.1) `vendor:3005` | 51% | 33% | 52% | 11 s |
| 4 | Auctioneer Stampi (40.4, 51.8) `ah` | Anvil (38.8, 56.1) `anvil:18124` | 18% | 13% | 18% | 7 s |
| 5 | Mailbox (45.2, 59.4) `mailbox:20426` | Shadi Mistrunner (40.6, 64.0) `vendor:8363` | 17% | 17% | 17% | 11 s |
| 6 | Auctioneer Stampi (40.4, 51.8) `ah` | Shadi Mistrunner (40.6, 64.0) `vendor:8363` | 15% | 10% | 15% | 16 s |
| 7 | Anvil (38.8, 56.1) `anvil:18124` | Thunder Bluff Forge (39.5, 56.1) `forge:18126` | 12% | 15% | 10% | 1 s |
| 8 | Blazing Fire (45.5, 56.3) `cooking_fire:22028` | Mailbox (45.2, 59.4) `mailbox:20426` | 10% | 7% | 10% | 4 s |
| 9 | Thunder Bluff Forge (39.5, 56.1) `forge:18126` | Mailbox (45.2, 59.4) `mailbox:20426` | 9% | 13% | 9% | 12 s |
| 10 | Auctioneer Stampi (40.4, 51.8) `ah` | Blazing Fire (45.5, 56.3) `cooking_fire:22028` | 7% | 3% | 9% | 12 s |
| 11 | Mailbox (45.2, 59.4) `mailbox:20426` | Taur Stonehoof (39.8, 55.6) `vendor:2999` | 7% | 5% | 7% | 12 s |
| 12 | Anvil (38.8, 56.1) `anvil:18124` | Mailbox (45.2, 59.4) `mailbox:20426` | 7% | 15% | 8% | 13 s |
| 13 | Thunder Bluff Forge (39.5, 56.1) `forge:18126` | Taur Stonehoof (39.8, 55.6) `vendor:2999` | 4% | 3% | 3% | 1 s |
| 14 | Auctioneer Stampi (40.4, 51.8) `ah` | Kuruk (38.9, 64.7) `vendor:8362` | 3% | 1% | 3% | 17 s |
| 15 | Blazing Fire (45.5, 56.3) `cooking_fire:22028` | Hewa (45.6, 56.6) `vendor:8358` | 3% | 5% | 2% | 0 s |
| 16 | Auctioneer Stampi (40.4, 51.8) `ah` | Thunder Bluff Forge (39.5, 56.1) `forge:18126` | 3% | 1% | 2% | 6 s |
| 17 | Anvil (38.8, 56.1) `anvil:18124` | Taur Stonehoof (39.8, 55.6) `vendor:2999` | 3% | 12% | 3% | 2 s |
| 18 | Mailbox (45.2, 59.4) `mailbox:20426` | Kuruk (38.9, 64.7) `vendor:8362` | 2% | 2% | 2% | 14 s |
| 19 | Auctioneer Stampi (40.4, 51.8) `ah` | Fyr Mistrunner (41.4, 53.2) `vendor:3003` | 1% | 2% | 1% | 3 s |
| 20 | Mailbox (45.2, 59.4) `mailbox:20426` | Fyr Mistrunner (41.4, 53.2) `vendor:3003` | 1% | 1% | 1% | 11 s |
| 21 | Kuruk (38.9, 64.7) `vendor:8362` | Shadi Mistrunner (40.6, 64.0) `vendor:8363` | 1% | 1% | 1% | 3 s |
| 22 | Thunder Bluff Forge (39.5, 56.1) `forge:18126` | Shadi Mistrunner (40.6, 64.0) `vendor:8363` | 1% | 0% | 1% | 10 s |
| 23 | Anvil (38.8, 56.1) `anvil:18124` | Shadi Mistrunner (40.6, 64.0) `vendor:8363` | 0% | 0% | 0% | 11 s |
| 24 | Mailbox (45.2, 59.4) `mailbox:20426` | Nan Mistrunner (47.3, 42.5) `vendor:3017` | 0% | 0% | 0% | 22 s |
| 25 | Fyr Mistrunner (41.4, 53.2) `vendor:3003` | Shadi Mistrunner (40.6, 64.0) `vendor:8363` | 0% | 1% | 0% | 14 s |
| 26 | Auctioneer Stampi (40.4, 51.8) `ah` | Roaring Fire (43.1, 44.0) `cooking_fire:20963` | 0% | 0% | 0% | 12 s |
| 27 | Roaring Fire (43.1, 44.0) `cooking_fire:20963` | Nan Mistrunner (47.3, 42.5) `vendor:3017` | 0% | 0% | 0% | 8 s |
| 28 | Auctioneer Stampi (40.4, 51.8) `ah` | Nan Mistrunner (47.3, 42.5) `vendor:3017` | 0% | 0% | 0% | 18 s |
| 29 | Taur Stonehoof (39.8, 55.6) `vendor:2999` | Shadi Mistrunner (40.6, 64.0) `vendor:8363` | 0% | 0% | 0% | 11 s |

### Undercity (Horde)

1102 profitable timed plans (4054 in all, 777 top-200). Hub: `ah`.

| # | From | To | Used by | All plans | Top 200 | Est. |
|---|---|---|---:|---:|---:|---:|
| 1 | Auctioneer Stockton (71.4, 46.7) `ah` | Mailbox (68.2, 38.3) `mailbox:17985` | 89% | 89% | 89% | 12 s |
| 2 | Mailbox (68.2, 38.3) `mailbox:17985` | Felicia Doan (64.1, 50.6) `vendor:4775` | 53% | 44% | 51% | 16 s |
| 3 | Auctioneer Stockton (71.4, 46.7) `ah` | Felicia Doan (64.1, 50.6) `vendor:4775` | 45% | 29% | 42% | 14 s |
| 4 | Auctioneer Stockton (71.4, 46.7) `ah` | Anvil (61.1, 30.6) `anvil:44941` | 17% | 13% | 18% | 26 s |
| 5 | Forge (62.2, 30.2) `forge:44917` | Mailbox (68.2, 38.3) `mailbox:17985` | 14% | 17% | 13% | 15 s |
| 6 | Auctioneer Stockton (71.4, 46.7) `ah` | Joseph Moore (70.1, 58.4) `vendor:4589` | 13% | 7% | 17% | 14 s |
| 7 | Mailbox (68.2, 38.3) `mailbox:17985` | Joseph Moore (70.1, 58.4) `vendor:4589` | 13% | 10% | 17% | 24 s |
| 8 | Anvil (61.1, 30.6) `anvil:44941` | Forge (62.2, 30.2) `forge:44917` | 12% | 15% | 10% | 2 s |
| 9 | Anvil (61.1, 30.6) `anvil:44941` | Mailbox (68.2, 38.3) `mailbox:17985` | 9% | 16% | 11% | 16 s |
| 10 | Auctioneer Stockton (71.4, 46.7) `ah` | Ezekiel Graves (75.2, 51.2) `vendor:4585` | 8% | 7% | 8% | 9 s |
| 11 | Auctioneer Stockton (71.4, 46.7) `ah` | Campfire (62.4, 45.0) `cooking_fire:44924` | 8% | 3% | 9% | 16 s |
| 12 | Mailbox (68.2, 38.3) `mailbox:17985` | Ezekiel Graves (75.2, 51.2) `vendor:4585` | 7% | 6% | 6% | 20 s |
| 13 | Campfire (62.4, 45.0) `cooking_fire:44924` | Felicia Doan (64.1, 50.6) `vendor:4775` | 7% | 5% | 7% | 8 s |
| 14 | Campfire (62.4, 45.0) `cooking_fire:44924` | Mailbox (68.2, 38.3) `mailbox:17985` | 3% | 3% | 3% | 13 s |
| 15 | Auctioneer Stockton (71.4, 46.7) `ah` | Forge (62.2, 30.2) `forge:44917` | 3% | 1% | 2% | 26 s |
| 16 | Campfire (62.4, 45.0) `cooking_fire:44924` | Ronald Burch (62.3, 43.1) `vendor:4553` | 3% | 6% | 2% | 2 s |
| 17 | Auctioneer Stockton (71.4, 46.7) `ah` | Eleanor Rusk (69.2, 48.9) `vendor:4555` | 3% | 2% | 3% | 5 s |
| 18 | Mailbox (68.2, 38.3) `mailbox:17985` | Eleanor Rusk (69.2, 48.9) `vendor:4555` | 3% | 2% | 3% | 13 s |
| 19 | Mailbox (68.2, 38.3) `mailbox:17985` | Jaycrue Copperpinch (68.1, 38.6) `vendor:13430` | 1% | 7% | 1% | 0 s |
| 20 | Eleanor Rusk (69.2, 48.9) `vendor:4555` | Felicia Doan (64.1, 50.6) `vendor:4775` | 1% | 1% | 1% | 9 s |
| 21 | Thomas Mordan (69.7, 39.1) `vendor:4562` | Ezekiel Graves (75.2, 51.2) `vendor:4585` | 1% | 0% | 1% | 18 s |
| 22 | Mailbox (68.2, 38.3) `mailbox:17985` | Thomas Mordan (69.7, 39.1) `vendor:4562` | 1% | 0% | 1% | 3 s |
| 23 | Joseph Moore (70.1, 58.4) `vendor:4589` | Felicia Doan (64.1, 50.6) `vendor:4775` | 1% | 1% | 1% | 15 s |
| 24 | Mailbox (68.2, 38.3) `mailbox:17985` | Merill Pleasance (69.3, 44.8) `vendor:5190` | 1% | 0% | 0% | 8 s |
| 25 | Auctioneer Stockton (71.4, 46.7) `ah` | Merill Pleasance (69.3, 44.8) `vendor:5190` | 1% | 0% | 0% | 4 s |
| 26 | Anvil (61.1, 30.6) `anvil:44941` | Samuel Van Brunt (61.4, 30.1) `vendor:4597` | 0% | 10% | 0% | 1 s |
| 27 | Eleanor Rusk (69.2, 48.9) `vendor:4555` | Ezekiel Graves (75.2, 51.2) `vendor:4585` | 0% | 0% | 0% | 12 s |
| 28 | Ezekiel Graves (75.2, 51.2) `vendor:4585` | Joseph Moore (70.1, 58.4) `vendor:4589` | 0% | 0% | 0% | 13 s |
