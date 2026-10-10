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
24 h cap. The model is pessimistic: no stealing, no offline earnings, no daily rewards, no luck boosts, and other
players win 40% of the belt items this player wanted. Belt spawns roll mutations like the server does.

| Rarity | Free player | 2x Cash pass | 2x Cash + VIP + Extra Podiums |
| --- | --- | --- | --- |
| Common | 7s | 7s | 7s |
| Uncommon | 1m 52s | 1m 7s | 1m 2s |
| Rare | 4m 52s | 2m 32s | 2m 25s |
| Epic | 11m 5s | 6m 37s | 5m 52s |
| Legendary | 30m 52s | 19m 42s | 17m 55s |
| Mythic | 1h 57m | 1h 20m | 1h 8m |
| Secret | 9h 35m | 5h 58m | 5h 49m |
| First rebirth affordable | 1h 3m | 37m 52s | 33m 47s |

Median cash/sec after N minutes of play:

| Play time | Free player | 2x Cash pass | 2x Cash + VIP + Extra Podiums |
| --- | --- | --- | --- |
| 10m | $976/s | $5.57K/s | $7.25K/s |
| 30m | $8.44K/s | $31.8K/s | $39.2K/s |
| 1h | $28.1K/s | $76.4K/s | $94.4K/s |
| 3h | $167K/s | $389K/s | $484K/s |
| 8h | $532K/s | $1.62M/s | $1.88M/s |
| 24h | $2.17M/s | $4.71M/s | $5.84M/s |

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
the store stay exact.

| Mutation | Chance per spawn | Per server-hour | Income | Price | Payback vs plain | Announced |
| --- | --- | --- | --- | --- | --- | --- |
| Golden | 3% | 43.2 | x2 | x1.5 | x0.75 | no |
| Diamond | 0.8% | 11.5 | x4 | x2.5 | x0.63 | no |
| Rainbow | 0.15% | 2.2 | x8 | x4 | x0.5 | spawn, buy, steal |

Any mutation: 3.95% of spawns (56.9 per server-hour). Expected value of one spawn: income x1.0645, price x1.0315.

* **A mutation is always a lucky find:** income grows faster than price (CI checks `incomeMultiplier >=
  priceMultiplier`), so a mutated Snackling pays itself back sooner than the plain one, and sells for the mutated
  price × the normal refund.
* **It doesn't move the chase.** Compared with the same simulation without mutations, the time to each rarity
  changes by at most ~4% (Legendary 32m 12s → 30m 52s free, first rebirth 1h 5m → 1h 3m), because rarity is still
  gated by the belt and by base prices. Steady income rises by ~5–10% in most cells (the expected x1.06 per spawn), up
  to ~16–18% in a few (around 8 h), where one lucky Diamond or Rainbow high-tier Snackling is a big share of a base
  (more variance, not a faster chase).
* **Rainbow is a server moment** (about twice per server-hour, announced like a Mythic) and a prime steal target;
  Golden and Diamond are personal surprises.
* **Event-only mutations** (with an `eventId`) roll only while that LiveOps event runs; keep every chance together,
  events included, well under 10% (CI requires the total to stay below 1).
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
feel worthless while it runs. With Haunted, any mutation is 5.95% of spawns (85.7 per server-hour; CI keeps all
chances together below 10%), and one spawn's expected value is income x1.1045, price x1.0515 (x1.0645 / x1.0315
without the event).

Time to reach each rarity and income for a **new free player whose whole session is inside the event** (same model as
above; the last column has the luck weekend on for the whole session too):

| Rarity | No event | Halloween | Halloween + 2x luck weekend |
| --- | --- | --- | --- |
| Common | 7s | 7s | 7s |
| Uncommon | 1m 52s | 1m 52s | 2m 2s |
| Rare | 4m 52s | 4m 52s | 4m 32s |
| Epic | 11m 5s | 10m 50s | 10m 22s |
| Legendary | 30m 52s | 30m 52s | 26m 47s |
| Mythic | 1h 57m | 1h 53m | 1h 29m |
| Secret | 9h 35m | 9h 22m | 5h 41m |
| First rebirth affordable | 1h 3m | 1h 0m | 54m 52s |

| Play time | No event | Halloween | Halloween + 2x luck weekend |
| --- | --- | --- | --- |
| 10m | $976/s | $1.03K/s | $1.36K/s |
| 30m | $8.44K/s | $9.55K/s | $14.4K/s |
| 1h | $28.1K/s | $32.7K/s | $50.6K/s |
| 3h | $167K/s | $191K/s | $295K/s |
| 8h | $532K/s | $608K/s | $1.09M/s |
| 24h | $2.17M/s | $2.4M/s | $3.56M/s |

A free player buys a median of 28 event Snacklings in 24 hours of event play (29 with the luck weekend), the first
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
rounded down to 2 significant digits, with a floor so they are worth something on day one: Snack Pack 15 min (min $2.5K), Snack Crate 1 h
(min $15K), Snack Truck 6 h (min $120K). They therefore stay meaningful at every stage instead of becoming
worthless (fixed amounts) or game-breaking (huge fixed amounts).

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
| Common | 3 min of steady income | $250 |
| Uncommon | 5 min | $1K |
| Rare | 8 min | $10K |
| Epic | 10 min | $100K |
| Legendary | 15 min | $2.5M |
| Mythic | 20 min | $75M |
| Secret | 30 min | $2.5B |

Each minimum is about the tier's cheapest Snackling, so even a tier completed early (by stealing) is worth one. All
seven tiers pay about 91 minutes of income over a player's whole life, less than half of one Snack Truck. Each
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
