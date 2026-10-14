# BALANCE

How the economy is shaped, and how long each rarity takes to reach. Every number here comes from the config
modules in `src/shared/Config/` and is reproduced by:

```sh
lune run tools/simulate.luau      # ~1-2 min, prints the tables below
```

Re-run it after any change to `Creatures.luau`, `Rarities.luau`, `Mutations.luau`, `Economy.luau`,
`Gameplay.luau` or the events in `LiveOps.luau` and paste the new tables here.

## Design intent

1. **The first minutes are fast.** A Common costs $25 and the player starts with $100, so the first purchase
   happens within seconds and the first Uncommon within ~2 minutes. Numbers move constantly.
2. **Every tier is a new goal, and each goal is further away.** A Snackling's *payback time* (price ÷ income)
   ramps from ~30 s (Common) to ~85 min (Secret). Each tier earns roughly 6–10× the previous one, but costs
   20–35× more, so saving for the next tier always takes longer than the last.
3. **Two gates, on purpose.** Low tiers are gated by *price* (you can always afford the next one soon). High
   tiers are also gated by *the belt*: a Mythic appears about 2.6 times per server-hour and a Secret about once
   every 3.5 server-hours, so everyone in the server sees the same rare spawn and races for it. That shared
   moment — announced to the whole server — is the social hook, and it is also where stealing gets exciting.
4. **Paying speeds you up, never locks you out.** 2× Cash roughly halves *saving* time, but the belt gate is the
   same for everyone, so a paying player reaches Legendary ~40% sooner, not 2× sooner, and free players still
   reach every tier. Nothing paid makes a base un-stealable (see DECISIONS.md, "Fairness").

## Rarity tiers (belt odds and creature stats)

Spawn every 2.5 s → 1,440 rolls per server-hour.

| Rarity | Snacklings | Chance per spawn | Per server-hour | With 2× luck | Price range | Income range | Payback |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Common | 10 | 56% | 806 | 47.9% | $25 - $200 | $1 - $6/s | 25s - 33s |
| Uncommon | 10 | 27% | 389 | 23.1% | $500 - $1.5K | $12 - $30/s | 41s - 50s |
| Rare | 10 (+1 event) | 11.5% | 166 | 19.7% | $4.5K - $12.5K | $65 - $160/s | 1m 9s - 1m 18s |
| Epic | 9 (+1 event) | 4.2% | 60.5 | 7.18% | $60K - $150K | $400 - $950/s | 2m 30s - 2m 37s |
| Legendary | 8 (+1 event) | 1.1% | 15.8 | 1.88% | $1.4M - $3.4M | $2.8K - $6.5K/s | 8m 20s - 8m 43s |
| Mythic | 7 (+1 event) | 0.18% | 2.6 | 0.308% | $50M - $85M | $35K - $56K/s | 23m 48s - 25m 17s |
| Secret | 6 | 0.02% | 0.3 | 0.034% | $1.8B - $3.2B | $360K - $620K/s | 1h 23m - 1h 26m |

"With 2× luck" is the Server Luck product (or a `/luck 2` admin boost): Rare-and-up weights double, so Commons
and Uncommons become less likely. The store shows these exact numbers before purchase.

## Time to reach each rarity (simulated)

Median play time until the player owns their first Snackling of each rarity, over 60 simulated players, with a
24 h cap. The model is pessimistic: no stealing, no offline earnings, no daily rewards, no luck boosts, no server
modifiers, and other players win 40% of the belt items this player wanted. Belt spawns roll mutations like the server
does, with the map changing every 20 minutes (so its signature mutation can roll).

| Rarity | Free player | 2x Cash pass | 2x Cash + VIP + Extra Podiums |
| --- | --- | --- | --- |
| Common | 7s | 7s | 7s |
| Uncommon | 1m 52s | 1m 7s | 1m 2s |
| Rare | 4m 52s | 2m 32s | 2m 25s |
| Epic | 11m 5s | 6m 42s | 6m 2s |
| Legendary | 30m 52s | 19m 52s | 18m 17s |
| Mythic | 1h 57m | 1h 20m | 1h 7m |
| Secret | 9h 35m | 5h 58m | 5h 49m |
| First rebirth affordable | 1h 2m | 37m 52s | 33m 47s |

Median cash/sec after N minutes of play:

| Play time | Free player | 2x Cash pass | 2x Cash + VIP + Extra Podiums |
| --- | --- | --- | --- |
| 10m | $1.01K/s | $5.64K/s | $7.25K/s |
| 30m | $8.68K/s | $30.3K/s | $39.2K/s |
| 1h | $31.5K/s | $79.3K/s | $99.2K/s |
| 3h | $173K/s | $389K/s | $496K/s |
| 8h | $568K/s | $1.62M/s | $1.89M/s |
| 24h | $2.26M/s | $4.83M/s | $5.84M/s |

Reading it: a free player gets a Legendary in their first session, a Mythic within a couple of sessions and a
Secret over a few days — and can shortcut any of it by stealing. A 2× Cash owner gets there roughly 35–45% sooner.

## The roster (60 Snacklings)

Each tier has 6-10 regular Snacklings, plus one limited-time Halloween Snackling in each tier from Rare to Mythic
(see "Halloween 2026"). Rules that keep a bigger roster from changing the chase:

* **Tier odds never change.** A new Snackling shares its tier's spawns. Each tier's regular `beltWeight`s add up to
  100 (CI checks it), so a weight reads as "% of the tier".
* **Same bands as before.** Every price, income and payback sits inside its tier's band in the table above (CI checks
  it in `tests/CreatureRecipe.spec.luau`), and within a tier the dearer ones pay back a little slower.
* **Cheap ones stay common.** About 40% of a tier's spawns are its two cheapest Snacklings (the cheapest costs the
  tier's minimum), so the first Snackling of each tier comes as fast as before; Mythic and Secret keep about 60% of
  their spawns at or near their minimum price, because those tiers are where saving up matters most.

Compared with the 20-Snackling roster this replaced, every time to a rarity is within about 8% (Legendary, Mythic,
Secret and the first rebirth are unchanged) and steady income is 0-6% lower (the average Mythic and Secret on the
belt is a little cheaper and earns a little less): the same curve, with three times as much to collect.

| Snackling | Rarity | Price | Income | Payback | Share of its tier | Per server-hour |
| --- | --- | --- | --- | --- | --- | --- |
| Pizza Pup | Common | $25 | $1/s | 25s | 22% | 177.4 |
| Cookie Crab | Common | $30 | $1/s | 30s | 18% | 145.2 |
| Marshmallow Mouse | Common | $50 | $2/s | 25s | 12% | 96.8 |
| Pretzel Pal | Common | $60 | $2/s | 30s | 10% | 80.6 |
| Chip Chick | Common | $75 | $3/s | 25s | 8% | 64.5 |
| Cracker Quacker | Common | $100 | $4/s | 25s | 7% | 56.4 |
| Gummy Grub | Common | $120 | $4/s | 30s | 7% | 56.4 |
| Jellybean Jellyfish | Common | $140 | $5/s | 28s | 6% | 48.4 |
| Cheese Puff Puffer | Common | $165 | $5/s | 33s | 5% | 40.3 |
| Toast Toad | Common | $200 | $6/s | 33s | 5% | 40.3 |
| Sushi Slug | Uncommon | $500 | $12/s | 41s | 22% | 85.5 |
| Fry Fox | Uncommon | $600 | $14/s | 42s | 18% | 70 |
| Pudding Pug | Uncommon | $700 | $16/s | 43s | 10% | 38.9 |
| Nacho Newt | Uncommon | $900 | $20/s | 45s | 9% | 35 |
| Bao Bunny | Uncommon | $1K | $22/s | 45s | 8% | 31.1 |
| Pickle Piglet | Uncommon | $1.1K | $24/s | 45s | 8% | 31.1 |
| Mochi Moth | Uncommon | $1.2K | $25/s | 48s | 7% | 27.2 |
| Hotdog Dachshund | Uncommon | $1.3K | $27/s | 48s | 6% | 23.3 |
| Muffin Moose | Uncommon | $1.4K | $28/s | 50s | 6% | 23.3 |
| Waffle Wombat | Uncommon | $1.5K | $30/s | 50s | 6% | 23.3 |
| Taco Turtle | Rare | $4.5K | $65/s | 1m 9s | 22% | 36.4 |
| Cinnamon Snail | Rare | $5K | $72/s | 1m 9s | 18% | 29.8 |
| Macaron Macaw | Rare | $6K | $85/s | 1m 10s | 10% | 16.6 |
| Bubblegum Bulldog | Rare | $7K | $98/s | 1m 11s | 9% | 14.9 |
| Burrito Bear | Rare | $8K | $110/s | 1m 12s | 8% | 13.2 |
| Boba Beluga | Rare | $9K | $122/s | 1m 13s | 8% | 13.2 |
| Gingersnap Gecko | Rare | $10K | $134/s | 1m 14s | 7% | 11.6 |
| Brownie Beaver | Rare | $11K | $146/s | 1m 15s | 6% | 9.9 |
| Sundae Sheep | Rare | $12K | $155/s | 1m 17s | 6% | 9.9 |
| Cupcake Cub | Rare | $12.5K | $160/s | 1m 18s | 6% | 9.9 |
| Ramen Raccoon | Epic | $60K | $400/s | 2m 30s | 22% | 13.3 |
| Omelet Owl | Epic | $70K | $465/s | 2m 30s | 18% | 10.9 |
| S'more Skunk | Epic | $80K | $530/s | 2m 30s | 12% | 7.3 |
| Tempura Tiger | Epic | $90K | $595/s | 2m 31s | 12% | 7.3 |
| Popcorn Penguin | Epic | $100K | $650/s | 2m 33s | 11% | 6.7 |
| Nugget Narwhal | Epic | $115K | $745/s | 2m 34s | 7% | 4.2 |
| Hamburger Hamster | Epic | $125K | $805/s | 2m 35s | 6% | 3.6 |
| Spaghetti Yeti | Epic | $135K | $865/s | 2m 36s | 6% | 3.6 |
| Bagel Badger | Epic | $150K | $950/s | 2m 37s | 6% | 3.6 |
| Donut Dragon | Legendary | $1.4M | $2.8K/s | 8m 20s | 22% | 3.5 |
| Onigiri Orca | Legendary | $1.6M | $3.18K/s | 8m 23s | 18% | 2.9 |
| Taffy Toucan | Legendary | $1.9M | $3.77K/s | 8m 23s | 12% | 1.9 |
| Pancake Panda | Legendary | $2.3M | $4.5K/s | 8m 31s | 12% | 1.9 |
| Cotton Candy Koala | Legendary | $2.6M | $5.07K/s | 8m 32s | 11% | 1.7 |
| Pavlova Peacock | Legendary | $2.9M | $5.64K/s | 8m 34s | 9% | 1.4 |
| Milkshake Mammoth | Legendary | $3.2M | $6.17K/s | 8m 38s | 8% | 1.3 |
| Churro Cheetah | Legendary | $3.4M | $6.5K/s | 8m 43s | 8% | 1.3 |
| Lasagna Lion | Mythic | $50M | $35K/s | 23m 48s | 30% | 0.78 |
| Souffle Sphinx | Mythic | $52M | $36.3K/s | 23m 52s | 20% | 0.52 |
| Gingerbread Golem | Mythic | $55M | $38.3K/s | 23m 56s | 12% | 0.31 |
| Parfait Pegasus | Mythic | $62M | $42.9K/s | 24m 5s | 10% | 0.26 |
| Hotpot Hydra | Mythic | $70M | $47.9K/s | 24m 21s | 10% | 0.26 |
| Flambe Phoenix | Mythic | $77M | $52K/s | 24m 40s | 8% | 0.21 |
| Dumpling Dino | Mythic | $85M | $56K/s | 25m 17s | 10% | 0.26 |
| Gelato Griffin | Secret | $1.8B | $360K/s | 1h 23m | 30% | 0.09 |
| Matcha Manta | Secret | $1.9B | $379K/s | 1h 23m | 20% | 0.06 |
| Fortune Cookie Kitsune | Secret | $2B | $398K/s | 1h 23m | 12% | 0.03 |
| Bonbon Behemoth | Secret | $2.3B | $456K/s | 1h 24m | 12% | 0.03 |
| Wedding Cake Wyvern | Secret | $2.7B | $533K/s | 1h 24m | 12% | 0.03 |
| Croissant Kraken | Secret | $3.2B | $620K/s | 1h 26m | 14% | 0.04 |

## Mutations

Every belt spawn, after its creature is rolled, gets at most one mutation (`Config/Mutations.luau`). Chances are
per spawn, the same for every rarity, and **never changed by luck** (DECISIONS.md #18), so the Server Luck odds in
the store stay exact. Golden Hour (a server modifier) is the only thing that multiplies them.

| Mutation | When | Chance per spawn | Per server-hour | Income | Price | Payback vs plain | Announced |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Golden | always | 3% | 43.2 | x2 | x1.5 | x0.75 | no |
| Diamond | always | 0.8% | 11.5 | x4 | x2.5 | x0.63 | no |
| Rainbow | always | 0.15% | 2.2 | x8 | x4 | x0.5 | spawn, buy, steal |
| Honey | on Sunny Meadow | 1.2% | 17.3 | x3 | x2 | x0.67 | no |
| Sprinkled | on Candy Kingdom | 1.2% | 17.3 | x3 | x2 | x0.67 | no |
| Frozen | on Frosty Peaks | 1.2% | 17.3 | x3 | x2 | x0.67 | no |
| Fossil | on Nacho Dunes | 1.2% | 17.3 | x3 | x2 | x0.67 | no |
| Molten | on Hot Sauce Volcano | 1.2% | 17.3 | x3 | x2 | x0.67 | no |
| Moonlit | on Midnight Market | 1.2% | 17.3 | x3 | x2 | x0.67 | no |
| Pearl | on Coconut Cove | 1.2% | 17.3 | x3 | x2 | x0.67 | no |
| Candy Apple | on Apple Pie Orchard | 1.2% | 17.3 | x3 | x2 | x0.67 | no |
| Electric | during Thunderstorm | 2% | 28.8 | x4 | x2.5 | x0.63 | spawn |
| Galaxy | during Meteor Shower | 2% | 28.8 | x4 | x2.5 | x0.63 | spawn |
| Toxic | during Toxic Fog | 2% | 28.8 | x4 | x2.5 | x0.63 | spawn |
| Blossom | on Cherry Blossom Garden | 1.2% | 17.3 | x3 | x2 | x0.67 | no |
| Lunar | on Cookie Moon | 1.2% | 17.3 | x3 | x2 | x0.67 | no |
| Mossy | on Mango Rainforest | 1.2% | 17.3 | x3 | x2 | x0.67 | no |
| Cyber | on Neon Noodle City | 1.2% | 17.3 | x3 | x2 | x0.67 | no |
| Angelic | on Cloud Nine | 1.2% | 17.3 | x3 | x2 | x0.67 | no |
| Abyssal | on Sushi Reef | 1.2% | 17.3 | x3 | x2 | x0.67 | no |
| Fudge | on Cocoa Canyon | 1.2% | 17.3 | x3 | x2 | x0.67 | no |
| Balloon | on Cotton Candy Carnival | 1.2% | 17.3 | x3 | x2 | x0.67 | no |
| Cheesy | on Pizza Piazza | 1.2% | 17.3 | x3 | x2 | x0.67 | no |
| Amethyst | on Rock Candy Caverns | 1.2% | 17.3 | x3 | x2 | x0.67 | no |
| Zesty | on Lemonade Lagoon | 1.2% | 17.3 | x3 | x2 | x0.67 | no |
| Bubblegum | on Bubblegum Bayou | 1.2% | 17.3 | x3 | x2 | x0.67 | no |
| Aurora | during Northern Lights | 2% | 28.8 | x4 | x2.5 | x0.63 | spawn |
| Toasted | during Heatwave | 2% | 28.8 | x4 | x2.5 | x0.63 | spawn |

"Per server-hour" is while the mutation can roll. Any mutation on an ordinary spawn (the map's signature included,
no modifier): 5.15% of spawns (74.2 per server-hour). Expected value of one spawn: income x1.0885, price x1.0435.

* **A mutation is always a lucky find:** income grows faster than price (CI checks `incomeMultiplier >=
  priceMultiplier`), so a mutated Snackling pays itself back sooner than the plain one, and sells for the mutated
  price × the normal refund.
* **It doesn't move the chase.** Compared with the same simulation without mutations, the time to each rarity
  changes by at most ~4% (Legendary 32m 12s → 30m 52s free, first rebirth 1h 5m → 1h 2m), because rarity is still
  gated by the belt and by base prices. Steady income rises by ~5–10% in most cells (the expected x1.06 per spawn), up
  to ~16–18% in a few (around 8 h), where one lucky Diamond or Rainbow high-tier Snackling is a big share of a base
  (more variance, not a faster chase).
* **Rainbow is a server moment** (about twice per server-hour, announced like a Mythic) and a prime steal target;
  Golden and Diamond are personal surprises.
* **Map signatures** (`mapTheme`): each map has exactly one, only while it is up — about 6 in a 20-minute map. At
  x3 they sit between Golden and Diamond (rarer than Golden, weaker than Diamond; CI checks both), so a map is worth
  voting for (the vote buttons and the title card name its mutation) without making the permanent ones pointless.
  Collectors chase all twenty through the Snackdex, which shows a pip for each one owned.
* **Weather mutations** (`modifierId`): only while their weather modifier runs (5 minutes, a few times a day per
  server), about 2–3 per storm, each announced to the whole server so everyone races to the belt. x4 like Diamond.
* **Event-only mutations** (with an `eventId`) roll only while that LiveOps event runs.
* **The worst case stays small.** Only one map and one modifier are ever live, so CI checks any one seasonal event
  plus the strongest map and modifier together (9.15% today) against 10%, every event at once (only possible if an
  admin starts them together with `/event`; `MutationRules.worstCaseTotal`, today 13.15%) against 15%, and the total
  with Golden Hour on any map against 30%.
* Want mutations rarer or stronger? Change `chance` (how often) or `incomeMultiplier` (how much) and re-run the
  simulation; keep `incomeMultiplier >= priceMultiplier`.

## Halloween 2026 (limited-time event)

`Halloween2026` runs Fri 23 Oct 17:00 UTC → Mon 2 Nov 08:00 UTC; `HalloweenLuck2026` adds **2× luck** from Fri 30 Oct
17:00 UTC → Sun 1 Nov 23:59 UTC (`Config/LiveOps.luau`). While Halloween runs:

| Snackling | Rarity | Price | Income | Payback | Share of its tier | Per server-hour | With 2x luck |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Candy Corn Cat | Rare | $10K | $135/s | 1m 14s | 23.1% | 38.2 | 65.3 |
| Pumpkin Pie Bat | Epic | $120K | $780/s | 2m 33s | 23.1% | 14 | 23.9 |
| Caramel Apple Ghoul | Legendary | $2.8M | $5.5K/s | 8m 29s | 23.1% | 3.7 | 6.2 |
| Jack-o'-Lantern Latte | Mythic | $70M | $47K/s | 24m 49s | 28.6% | 0.7 | 1.3 |

| Mutation | Chance per spawn | Per server-hour | Income | Price | Payback vs plain | Announced |
| --- | --- | --- | --- | --- | --- | --- |
| Haunted (event only) | 2% | 28.8 | x3 | x2 | x0.67 | no |

Haunted is rarer than Golden (2% vs 3%) and stronger (x3 vs x2), so it is the event's chase without making Golden
feel worthless while it runs. With Haunted (and the map's signature), any mutation is 7.15% of spawns (103 per
server-hour; CI keeps the worst case below 10%), and one spawn's expected value is income x1.1285, price x1.0635
(x1.0885 / x1.0435 without the event).

Time to reach each rarity and income for a **new free player whose whole session is inside the event** (same model as
above; the last column has the luck weekend on for the whole session too):

| Rarity | No event | Halloween | Halloween + 2x luck weekend |
| --- | --- | --- | --- |
| Common | 7s | 7s | 7s |
| Uncommon | 1m 52s | 1m 52s | 2m 2s |
| Rare | 4m 52s | 4m 50s | 4m 37s |
| Epic | 11m 5s | 10m 52s | 10m 20s |
| Legendary | 30m 52s | 30m 45s | 26m 40s |
| Mythic | 1h 57m | 1h 50m | 1h 28m |
| Secret | 9h 35m | 9h 22m | 5h 41m |
| First rebirth affordable | 1h 2m | 59m 12s | 54m 32s |

| Play time | No event | Halloween | Halloween + 2x luck weekend |
| --- | --- | --- | --- |
| 10m | $1.01K/s | $1.13K/s | $1.53K/s |
| 30m | $8.68K/s | $10K/s | $14.9K/s |
| 1h | $31.5K/s | $33.6K/s | $51.9K/s |
| 3h | $173K/s | $200K/s | $308K/s |
| 8h | $568K/s | $624K/s | $1.11M/s |
| 24h | $2.26M/s | $2.45M/s | $3.6M/s |

A free player buys a median of 28 event Snacklings in 24 hours of event play (30 with the luck weekend), the first
after about 7½ minutes (a Candy Corn Cat).

* **Normal progression outside the event is untouched.** Event Snacklings are listed after every regular one and
  only join the roll while their event runs, and Haunted rolls after the permanent mutations, so with no event active
  every belt roll is exactly what it was (CI replays 60,000 rolls with and without them), and the tables at the top
  of this file are unchanged.
* **Event Snacklings share their tier's odds instead of adding to them**: the tier odds (and so the Server Luck
  disclosure) are the same during the event; within a tier, an event Snackling takes about a quarter of the spawns.
  Their price and payback sit inside their tier's regular range (CI checks it), so they are a fun collectible and
  steal target, not a shortcut.
* **The event itself is a gentle boost**: about +5-15% income (Haunted's expected value is +3.75% per spawn; the
  rest is a cheaper Mythic option and more variety to upgrade into), the first Mythic ~4% sooner and the first
  rebirth ~5% sooner. The **luck weekend** is the big lever, as any 2× luck is: belt-gated tiers come
  much sooner (Secret 9h 35m → 5h 41m) and income is ~1.4-2× higher. It lasts about 55 hours of one weekend, so for a
  regular player it is a burst, not a new baseline.
* **Server Luck during the luck weekend**: the event's 2× and a bought 2× multiply to 4× (the cap is 6×); the store's
  before/after odds include the event's luck, and a test proves they match what the server rolls exactly.
* **After the event** event Snacklings stop spawning but owned ones (and Haunted ones) keep earning forever, sell at
  their normal value and can still be stolen; nothing about them is saved differently (no save-format change).

## Winter 2026 (limited-time event)

`Winter2026` runs Fri 18 Dec 17:00 UTC → Mon 4 Jan 08:00 UTC; `WinterLuck2026` adds **2× luck** for Christmas, Thu 24
Dec 17:00 UTC → Sat 26 Dec 23:59 UTC, and `NewYearCash2026` doubles **everyone's income** for New Year's Eve, Thu 31
Dec 17:00 UTC → Fri 1 Jan 23:59 UTC (`Config/LiveOps.luau`). While Winter runs:

| Snackling | Rarity | Price | Income | Payback | Share of its tier | Per server-hour | With 2x luck |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Peppermint Puffin | Rare | $11.5K | $152/s | 1m 15s | 23.1% | 38.2 | 65.3 |
| Candy Cane Chameleon | Epic | $130K | $840/s | 2m 34s | 23.1% | 14 | 23.9 |
| Yule Log Yak | Legendary | $3M | $5.85K/s | 8m 32s | 23.1% | 3.7 | 6.2 |
| Spun Sugar Stag | Mythic | $75M | $50.5K/s | 24m 45s | 28.6% | 0.7 | 1.3 |

| Mutation | Chance per spawn | Per server-hour | Income | Price | Payback vs plain | Announced |
| --- | --- | --- | --- | --- | --- | --- |
| Festive (event only) | 2% | 28.8 | x3 | x2 | x0.67 | no |

The same shape as Halloween, on purpose: four Snacklings sharing their tiers' odds (a little pricier than the
Halloween ones, still inside each tier's regular price and payback range), and an event mutation exactly as rare and
strong as Haunted. With Festive (and the map's signature), any mutation is 7.15% of spawns, and one spawn's expected
value is income x1.1285, price x1.0635, the same as during Halloween.

Time to reach each rarity and income for a **new free player whose whole session is inside the event** (the last
column has the Christmas luck on for the whole session too):

| Rarity | No event | Winter | Winter + 2x Christmas luck |
| --- | --- | --- | --- |
| Common | 7s | 7s | 7s |
| Uncommon | 1m 52s | 1m 52s | 2m 2s |
| Rare | 4m 52s | 4m 52s | 4m 37s |
| Epic | 11m 5s | 10m 50s | 10m 22s |
| Legendary | 30m 52s | 30m 45s | 26m 40s |
| Mythic | 1h 57m | 1h 50m | 1h 28m |
| Secret | 9h 35m | 9h 22m | 5h 41m |
| First rebirth affordable | 1h 2m | 58m 35s | 54m 17s |

| Play time | No event | Winter | Winter + 2x Christmas luck |
| --- | --- | --- | --- |
| 10m | $1.01K/s | $1.14K/s | $1.52K/s |
| 30m | $8.68K/s | $10.2K/s | $14.7K/s |
| 1h | $31.5K/s | $34.4K/s | $53K/s |
| 3h | $173K/s | $202K/s | $316K/s |
| 8h | $568K/s | $639K/s | $1.12M/s |
| 24h | $2.26M/s | $2.48M/s | $3.6M/s |

A free player buys a median of 29 event Snacklings in 24 hours of event play (32 with the Christmas luck), the first
after about 7½ minutes (a Peppermint Puffin). Re-run with `lune run tools/simulate.luau Winter2026 WinterLuck2026
"Christmas luck"`.

* **Everything said about Halloween holds**: no regular roll changes outside the event (CI replays the rolls for
  both events), the tier odds and the Server Luck disclosure are the same during it, and after it the Snacklings
  (and Festive ones) keep earning forever.
* **New Year's Eve 2x Cash** is a ~31-hour party: income doubles for everyone. It stacks with the 2x Cash pass, and
  with a Cash Splash modifier (×1.5) up to the 3× cap on event and modifier cash together (`maxCashMultiplier`).
  Cash packs and rewards are sized from steady income without LiveOps events, so buying a pack during it is no better
  or worse. Its banner ("New Year's Eve: 2x Cash!", counting down) replaces the Winter one while it runs.
* **The Christmas luck** is shorter than Halloween's weekend (about 55 hours over the 24th-26th) and works the same
  (2× of 6×; the store's odds stay exact).

## Valentine's 2027 (limited-time event)

`Valentine2027` runs Fri 5 Feb 17:00 UTC → Tue 16 Feb 08:00 UTC (it takes in Valentine's Day and the US Presidents'
Day holiday after it); `ValentineLuck2027` adds **2× luck** over Valentine's weekend, Fri 12 Feb 17:00 UTC → Sun 14
Feb 23:59 UTC (`Config/LiveOps.luau`). While Valentine's runs:

| Snackling | Rarity | Price | Income | Payback | Share of its tier | Per server-hour | With 2x luck |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Candy Heart Hamster | Rare | $12K | $158/s | 1m 15s | 23.1% | 38.2 | 65.3 |
| Cherry Cordial Kitten | Epic | $140K | $905/s | 2m 34s | 23.1% | 14 | 23.9 |
| Red Velvet Raccoon | Legendary | $3.2M | $6.25K/s | 8m 32s | 23.1% | 3.7 | 6.2 |
| Rose Petal Pegasus | Mythic | $80M | $54K/s | 24m 41s | 28.6% | 0.7 | 1.3 |

| Mutation | Chance per spawn | Per server-hour | Income | Price | Payback vs plain | Announced |
| --- | --- | --- | --- | --- | --- | --- |
| Sweetheart (event only) | 2% | 28.8 | x3 | x2 | x0.67 | no |

The same shape as Halloween and Winter again: four Snacklings sharing their tiers' odds (a little pricier than the
Winter ones, still inside each tier's regular price and payback range) and an event mutation exactly as rare and
strong as Haunted and Festive, so any mutation is 7.15% of spawns and one spawn's expected value is income x1.1285,
price x1.0635 while it runs.

Time to reach each rarity and income for a **new free player whose whole session is inside the event** (the last
column has the Valentine's luck on for the whole session too):

| Rarity | No event | Valentine's | Valentine's + 2x luck |
| --- | --- | --- | --- |
| Common | 7s | 7s | 7s |
| Uncommon | 1m 52s | 1m 52s | 2m 2s |
| Rare | 4m 52s | 4m 52s | 4m 37s |
| Epic | 11m 5s | 11m 2s | 10m 22s |
| Legendary | 30m 52s | 30m 45s | 26m 40s |
| Mythic | 1h 57m | 1h 50m | 1h 29m |
| Secret | 9h 35m | 9h 22m | 5h 41m |
| First rebirth affordable | 1h 2m | 58m 12s | 54m 2s |

| Play time | No event | Valentine's | Valentine's + 2x luck |
| --- | --- | --- | --- |
| 10m | $1.01K/s | $1.15K/s | $1.54K/s |
| 30m | $8.68K/s | $10.6K/s | $15K/s |
| 1h | $31.5K/s | $35.4K/s | $53.3K/s |
| 3h | $173K/s | $204K/s | $324K/s |
| 8h | $568K/s | $652K/s | $1.14M/s |
| 24h | $2.26M/s | $2.52M/s | $3.75M/s |

A free player buys a median of 32 event Snacklings in 24 hours of event play (35 with the Valentine's luck), the
first after about 7½ minutes (a Candy Heart Hamster). Re-run with `lune run tools/simulate.luau Valentine2027
ValentineLuck2027 "Valentine's luck"`.

* **Everything said about Halloween holds**: no regular roll changes outside the event (CI replays the rolls for every
  event), the tier odds and the Server Luck disclosure are the same during it, and after it the Snacklings (and
  Sweetheart ones) keep earning forever.
* **The Valentine's luck** is a weekend like Halloween's (about 55 hours) and works the same (2× of 6×; the store's
  odds stay exact).
* **Three event mutations exist now**, months apart. If an admin started every event at once with `/event`, all
  mutations together would reach 13.15% of spawns (CI keeps that below 15%); any one event with the strongest map and
  modifier stays at 9.15%.

## Server modifiers

A modifier runs for 5 minutes, then the server waits 4-8 minutes (6 on average) before the next one
(`Config/Modifiers.luau` `schedule`), so one is running about **45% of the time**. Twenty modifiers share the picks
by weight (eighteen at 1, Snack Party at 0.5, Jackpot at 0.35), never the same twice in a row: each regular one runs
about **1.45 minutes per server-hour**, Snack Party about 0.7 and Jackpot about 0.5. A player in a 30-minute session
sees about three: a weather one more often than not, a drop one (crates, coins, runaways or a Snack Attack) about
half the time.

| Modifier | Effect while it runs | Effect over a server-hour |
| --- | --- | --- |
| Rush Hour | belt spawns every 1.25 s instead of 2.5 (the belt holds 32 instead of 16) | about +3% Snacklings on the belt (with Snack Party) |
| Clearance Sale | belt prices x0.7 (rounded to whole cash, at least 1) | about 1% off what an always-buying player spends |
| Golden Hour | every mutation chance x3 (5.15% → 15.5% of spawns; 7.15% → 21.5% while Halloween runs) | about +5% mutations |
| Lucky Breeze | 2x luck (a LiveOps boost: shows in the luck pill, capped with everything else at 6x) | rare odds doubled ~3.6% of the time (with Snack Party) |
| Cash Splash | income x1.5 (with LiveOps cash events, capped at 3x) | about +1.2% income; cash packs and quest rewards are not inflated (they use the steady income) |
| Sugar Rush | everyone walks (and carries) 25% faster | – |
| Quick Hands | the steal hold is 0.75 s instead of 1.5 | – |
| Fortress | locks started while it runs last 1.5x (the open window grows with them: at least half the lock) | – |
| Snack Patrol | tag reach 13 → 19.5 studs | – |
| Snack Party (rare) | spawns every 1.7 s and 2x luck | – |
| Jackpot (rare) | income x2 (with LiveOps cash events, capped at 3x) | about +0.9% income |
| Thunderstorm | rain, lightning and a dark sky; Electric Snacklings can roll (2% of spawns) | about 2–3 Electric per storm |
| Meteor Shower | a starry midnight with shooting stars; Galaxy Snacklings can roll (2%) | about 2–3 Galaxy per shower |
| Toxic Fog | green haze and glowing spores; Toxic Snacklings can roll (2%) | about 2–3 Toxic per fog |
| Northern Lights | a polar night with an aurora swaying across the sky; Aurora Snacklings can roll (2%) | about 2–3 Aurora per night |
| Heatwave | a blazing, hazy noon with heat shimmer; Toasted Snacklings can roll (2%) | about 2–3 Toasted per heatwave |
| Supply Drop | 4 crates parachute onto the walkways; hold one open (2.5 s) to win it | see below |
| Coin Rain | 8 showers of 12 coins over the walkways; walk through them | see below |
| Great Escape | 6 Snacklings break out (one every 50 s) and run along the walkways; walk into one to catch it | see below |
| Snack Attack | 3 giant Snacklings (one every 100 s) hover over the belt; everyone taps them down together | see below |

They are spice, not an economy change: the biggest, Golden Hour, adds under a tenth to a server's mutations per hour.

**Drops** (`Config/Drops.luau`) are the exception that hands out something, so they are sized like cash packs, from
the player's steady income:

* **A supply crate** holds a Snackling rolled at 3x luck (and 2x mutation chance) plus 45 seconds of the opener's
  income (at least $300); with a full base the Snackling is sold for its usual refund instead. At 3x luck a crate is
  Common 42%, Uncommon 20%, Rare 26%, Epic 9.4%, Legendary 2.5%, Mythic 0.4%, Secret 0.04% (the belt: 56 / 27 / 11.5
  / 4.2 / 1.1 / 0.18 / 0.02). A server sees about 1.2 crates an hour and only one player wins each, so a new player's
  lucky Legendary is a story, not a shortcut everyone takes.
* **Coins** pay 3 seconds of the collector's income each (at least $30); a whole Coin Rain is 96 coins, about 5
  minutes of income shared by everyone in the server. A newcomer grabbing a dozen gets a few hundred dollars early on
  (a Rare costs $4.5K); a big base gets a few seconds per coin.
* **A runaway** is a Snackling rolled at 2x luck (and 2x mutation chance), no cash: Common 48%, Uncommon 23%, Rare
  20%, Epic 7.2%, Legendary 1.9%, Mythic 0.31%, Secret 0.03% (the "With 2× luck" column above). A server sees about
  two an hour, and only the first player to reach each one gets it. It runs slower than players (9 studs/s wandering,
  14.5 while someone is within 40 studs; players walk at 16), so it is always catchable: in offline chases with these
  numbers one player catches it in about 15 s (mostly running to it), four in about 4 s, well inside its 45 seconds.
* **A Snack Attack giant** (`Config/Boss.luau`) has 90 health per player in the server (at least 120) and the server
  counts at most 5 taps a second from each player, so everyone tapping flat out takes about 18-24 seconds whatever
  the server size; it flies off after 75 seconds. Everyone who landed 5 taps or more gets their own income x (20 s +
  120 s x their share of the taps): four even helpers get about 50 seconds of income each, a solo takedown 140
  seconds. The top hitter also wins a Snackling rolled like a crate's (3x luck, 2x mutation chance). A server sees
  about one giant an hour.
* Pickups, catches and taps are checked against the player's trusted position (no teleporting to coins, runaways or
  the giant) and a crate's hold is re-checked like a steal's.
The weather ones change only the sky (a lighting overlay above the map's and a seasonal theme's, the client's
particles and sky effects) and unlock their mutation; lightning flashes are soft, at most two in a quarter second,
and off with Reduce effects.
Every effect is clamped by `limits` (CI), and a speed modifier widens the server's movement checks by exactly its own
multiplier (and keeps the faster speed allowed for 4 s after it ends), so the anti-cheat never flags a player for
running at a speed the server gave them.

## Playtime gifts and the Lucky Spin

**Gifts** (`Config/Gifts.luau`) unlock with time in game each UTC day: 5 min 30 s of income (at least $150), 10 min a
Lucky Spin, 15 min 60 s of income (at least $400), 25 min a Snackling at 2x luck, 40 min two spins, 60 min a Snackling
at 4x luck. An hour of play collects all six: 90 seconds of income, three spins and two lucky Snacklings. Unclaimed
gifts that were unlocked are paid at midnight, so nobody loses one by logging off.

**The Lucky Spin** (`Config/Spin.luau`): a free spin every 12 hours (a new player's first is ready at once) plus the
banked ones from gifts (up to 20; more are paid as a minute of income each).

| Prize | Chance | What it pays |
| --- | --- | --- |
| Cash | 30% | 30 s of income (at least $200) |
| Big Cash | 25% | 90 s (at least $600) |
| Snackling | 18% | a Snackling at 2x luck |
| Huge Cash | 14% | 5 min (at least $2,000) |
| Golden! | 8% | a Golden Snackling at 2x luck |
| Diamond! | 3.5% | a Diamond Snackling at 2x luck (announced) |
| JACKPOT | 1.5% | 20 min of income (at least $10K; announced) |

One spin is worth about 90 seconds of income in cash on average, plus a 30% chance of a Snackling. At 2x luck a
Snackling is Common 48%, Uncommon 23%, Rare 20%, Epic 7.2%, Legendary 1.9%, Mythic 0.31%, Secret 0.03%; at 4x (the
last gift) Rare 30%, Epic 11%, Legendary 2.9%, Mythic 0.48%. A player who plays an hour a day and spins twice gets
roughly 9 minutes of extra income a day from gifts and spins, about +15% for that hour: a reason to come back and stay,
not a new economy. Every prize scales with steady income like a cash pack, and the server decides every spin.

## Other knobs

**Podiums** (`Economy.podiumUpgrade`): 8 to start, then +1 at a time for
$2.5K, $7.5K, $22.5K, $67.5K, $202K, $607K, $1.82M, $5.46M (16 total). The Extra Podiums pass adds 4 more (20 max,
the map's limit). More podiums mostly help in the mid game; the top tiers are gated by price and the belt.

**Rebirth** (`Economy.rebirth`): cost ×6 per rebirth, multiplier +0.5 per rebirth, +5 s lock per rebirth (max +60 s).
Cash and Snacklings reset; podium upgrades, passes and stats stay.

| Rebirth | Cost | Earnings multiplier after | Lock bonus after |
| --- | --- | --- | --- |
| 0 → 1 | $25M | ×1.5 | +5s |
| 1 → 2 | $150M | ×2 | +10s |
| 2 → 3 | $900M | ×2.5 | +15s |
| 3 → 4 | $5.4B | ×3 | +20s |
| 4 → 5 | $32.4B | ×3.5 | +25s |

The first rebirth lands around the first-Legendary stage (~1 h free); later ones need Mythic-level income, so
rebirths become a multi-session goal. The multiplier is saved when earned, so later tuning never lowers it.

**Cash packs** (`Economy.cashPacks`) pay N seconds of the buyer's steady income (creatures on active podiums that
are not being stolen, at the rebirth and pass multipliers, without LiveOps cash events or the friend & group bonus),
rounded down to 2 significant digits, with a floor so they are worth something on day one. They therefore stay
meaningful at every stage instead of becoming worthless (fixed amounts) or game-breaking (huge fixed amounts).

| Pack | Launch price | Income | Floor | Minutes per 10 R$ |
| --- | --- | --- | --- | --- |
| Snack Bite | 5 R$ | 2 min | $400 | 4 |
| Snack Bag | 15 R$ | 8 min | $1.3K | 5.3 |
| Snack Pack | 25 R$ | 15 min | $2.5K | 6 |
| Snack Basket | 49 R$ | 35 min | $6K | 7.1 |
| Snack Crate | 75 R$ | 1 h | $15K | 8 |
| Snack Truck | 199 R$ | 6 h | $120K | 18 |

Each step up is better value per Robux, the usual ladder in Roblox stores: the cheap packs are low-risk first
purchases and impulse top-ups ("just need a bit more for that Snackling"), the big ones reward committed players.
Prices are set on the Creator Hub, so if one changes, keep this column (and the comment in `Economy.cashPacks`) in
step and keep the ladder rising. A test checks that income time and floor both rise in store order.

**"Need $X more?" offers** (`Monetization.cashOffer`): when a belt or podium purchase fails for lack of cash, the
player is offered the cheapest pack above that covers the gap, at most once per 90 s and never during the
tutorial (DECISIONS.md #25). Because the floors rise with the ladder, a brand-new player short of a few hundred is
offered the 5 R$ Snack Bite, not a big pack.

**Offline earnings** (`Economy.offline`): 50% of income for up to 2 h away (VIP: 3 h), only after 2+ minutes away.

**Daily streak** (`Economy.daily`): 7-day cycle, reward = max(minimum, N minutes of income), from 3 minutes on
day 1 to 45 minutes on day 7. Missing a day resets the streak.

**Friends & group** (`Config/Social`): +10% income per Roblox friend playing in the same server (at most 3 counted,
+30%) and +10% for members of the owner's group (once `groupId` is set): at most **+40%**, multiplied on top of
everything else. It only raises live income: cash packs, daily rewards, offline earnings and the best cash/sec stat
(leaderboard) are all computed without it (DECISIONS.md #19), so it can't be farmed into a pack or a saved value. For
scale: one rebirth is ×1.5 and 2× Cash is ×2, so the social bonus is a nice extra for playing together, not a gate.
Group members also get a one-time welcome gift of 10 minutes of steady income (at least $1K). The simulation above
assumes no social bonus.

**Base lock** (`Gameplay.lock`): 60 s lock (up to 150 s with the max rebirth bonus and the Longer Lock pass), 90 s
recharge after it ends; nobody can re-lock within 30 s — or half the lock's length, if longer (75 s for a 150 s
lock) — of a lock ending, even with Instant Lock. So every base is open at least a third of the time while its owner
spams locks, whatever the lock length.

**New-player shield** (`Gameplay.grace`): the first 4 minutes of total play time; stealing ends it early.

**First-time tutorial** (`Config/Tutorial`): finishing it pays a one-time **$500** (the price of the cheapest
Uncommon), usually within the first one to two minutes. Skipping it pays nothing, and players who already had progress
when it shipped never get it. The simulation above does not include it; it can only bring the first Uncommon forward by
a minute or so and changes nothing after that.

## Snackdex and daily quests

Both pay in "minutes of steady income" (the cash-pack basis: rebirths, passes and the collection bonus; no LiveOps cash
event, no friend & group bonus), never below a minimum, so they stay meaningful at every stage without breaking it.
The simulation above includes neither.

**Snackdex** (`Config/Snackdex`): owning every regular Snackling of a tier (event Snacklings never count) pays once:

| Tier | Reward | Minimum |
| --- | --- | --- |
| Common | 3 min of steady income | $10 |
| Uncommon | 5 min | $250 |
| Rare | 8 min | $1K |
| Epic | 10 min | $15K |
| Legendary | 15 min | $350K |
| Mythic | 20 min | $12.5M |
| Secret | 30 min | $450M |

Each minimum is about a quarter of the tier's cheapest Snackling (a test keeps it at most half). The minimum only
matters for a player who completes a tier very early, mostly by stealing; keeping it below the cheapest price means
lending Snacklings to a second account by stealing can't mint cash. For a normal player the income-based amount is
far bigger. All seven tiers pay about 91 minutes of income over a player's whole life, less than half of one Snack Truck. Each
completed tier also adds **+3% income forever** (all seven: +21%, the cap), which counts like rebirths everywhere
(cash packs, daily and offline rewards, the leaderboard). For scale: one rebirth is ×1.5, so the whole collection is
worth less than half a rebirth; it rewards collecting without replacing the rebirth chase. A new mutation of a known
Snackling only fills its pip (no cash).

**Daily quests** (`Config/Quests`): 2 easy + 1 hard a day.

| | Reward | Minimum | Examples |
| --- | --- | --- | --- |
| Easy | 3 min of steady income | $250 | buy 5 from the belt, collect 5 min of income from pads (at least $250), sell 2, lock twice |
| Hard | 10 min | $1K | steal one, buy a Rare or rarer, find something new for the Snackdex, collect 20 min of income (at least $2.5K) |
| All three done | 5 min | $500 | paid with the last claim |

A full day pays about **21 minutes of steady income** (at least $2K), between the daily streak's day-5 (18 min) and
day-6 (25 min) rewards, and it takes a session of real play to earn (CI keeps a day under an hour). Collect targets are
fixed from steady income when the day's quests are rolled, so they always mean a few minutes of normal play.

## Tuning checklist

* Change one tier at a time and keep the strict ordering (CI enforces it): every tier must be rarer, pricier,
  higher-earning and have a longer payback than the one below.
* Want the chase longer? Raise high-tier prices (price gate) or lower `beltWeight` (belt gate). Price gates make
  2× Cash more valuable; belt gates affect everyone equally.
* Events: a `cashMultiplier` event speeds everyone up; a `luckMultiplier` event shortens only the belt gate (it
  never changes mutation chances).
* Event Snacklings: keep price and payback inside their tier's regular range, and keep their `beltWeight` modest
  (Halloween's take ~25% of their tier). Append them after the regular creatures and event mutations after the
  permanent ones, so rolls outside the event stay identical. The simulation's "During an event" tables (set
  `EVENT_ID` in `tools/simulate.luau`) show the event's effect.
