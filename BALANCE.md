# BALANCE

How the economy is shaped, and how long each rarity takes to reach. Every number here comes from the config
modules in `src/shared/Config/` and is reproduced by:

```sh
lune run tools/simulate.luau      # ~40 s, prints the tables below
```

Re-run it after any change to `Creatures.luau`, `Rarities.luau`, `Mutations.luau`, `Economy.luau` or
`Gameplay.luau` and paste the new tables here.

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

| Rarity | Chance per spawn | Per server-hour | With 2× luck | Price range | Income range | Payback |
| --- | --- | --- | --- | --- | --- | --- |
| Common | 56% | 806 | 47.9% | $25 - $200 | $1 - $6/s | 25s - 33s |
| Uncommon | 27% | 389 | 23.1% | $500 - $1.5K | $12 - $30/s | 41s - 50s |
| Rare | 11.5% | 166 | 19.7% | $4.5K - $12.5K | $65 - $160/s | 1m 9s - 1m 18s |
| Epic | 4.2% | 60.5 | 7.18% | $60K - $150K | $400 - $950/s | 2m 30s - 2m 37s |
| Legendary | 1.1% | 15.8 | 1.88% | $1.4M - $3.4M | $2.8K - $6.5K/s | 8m 20s - 8m 43s |
| Mythic | 0.18% | 2.6 | 0.308% | $50M - $85M | $35K - $56K/s | 23m 48s - 25m 17s |
| Secret | 0.02% | 0.3 | 0.034% | $1.8B - $3.2B | $360K - $620K/s | 1h 23m - 1h 26m |

"With 2× luck" is the Server Luck product (or a `/luck 2` admin boost): Rare-and-up weights double, so Commons
and Uncommons become less likely. The store shows these exact numbers before purchase.

## Time to reach each rarity (simulated)

Median play time until the player owns their first Snackling of each rarity, over 60 simulated players, with a
24 h cap. The model is pessimistic: no stealing, no offline earnings, no daily rewards, no luck boosts, and other
players win 40% of the belt items this player wanted. Belt spawns roll mutations like the server does.

| Rarity | Free player | 2x Cash pass | 2x Cash + VIP + Extra Podiums |
| --- | --- | --- | --- |
| Common | 7s | 7s | 7s |
| Uncommon | 2m 2s | 1m 15s | 1m 7s |
| Rare | 4m 55s | 2m 45s | 2m 32s |
| Epic | 11m 37s | 7m 0s | 6m 10s |
| Legendary | 30m 52s | 19m 15s | 18m 17s |
| Mythic | 1h 58m | 1h 20m | 1h 8m |
| Secret | 9h 35m | 5h 58m | 5h 49m |
| First rebirth affordable | 1h 2m | 37m 45s | 33m 40s |

Median cash/sec after N minutes of play:

| Play time | Free player | 2x Cash pass | 2x Cash + VIP + Extra Podiums |
| --- | --- | --- | --- |
| 10m | $980/s | $6.09K/s | $7.39K/s |
| 30m | $8.62K/s | $32.6K/s | $39.3K/s |
| 1h | $29.9K/s | $81.3K/s | $97.9K/s |
| 3h | $174K/s | $401K/s | $504K/s |
| 8h | $560K/s | $1.64M/s | $1.93M/s |
| 24h | $2.32M/s | $5.29M/s | $6.28M/s |

Reading it: a free player gets a Legendary in their first session, a Mythic within a couple of sessions and a
Secret over a few days — and can shortcut any of it by stealing. A 2× Cash owner gets there roughly 35–45% sooner.

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
  changes by at most ~4% (Legendary 32m 12s → 30m 52s free, first rebirth 1h 4m → 1h 2m), because rarity is still
  gated by the belt and by base prices. Steady income rises by ~5–10% in most cells (the expected x1.06 per spawn), up
  to ~16–18% in a few (around 8 h), where one lucky Diamond or Rainbow high-tier Snackling is a big share of a base
  (more variance, not a faster chase).
* **Rainbow is a server moment** (about twice per server-hour, announced like a Mythic) and a prime steal target;
  Golden and Diamond are personal surprises.
* **Event-only mutations** (with an `eventId`) roll only while that LiveOps event runs; keep every chance together,
  events included, well under 10% (CI requires the total to stay below 1).
* Want mutations rarer or stronger? Change `chance` (how often) or `incomeMultiplier` (how much) and re-run the
  simulation; keep `incomeMultiplier >= priceMultiplier`.

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

## Tuning checklist

* Change one tier at a time and keep the strict ordering (CI enforces it): every tier must be rarer, pricier,
  higher-earning and have a longer payback than the one below.
* Want the chase longer? Raise high-tier prices (price gate) or lower `beltWeight` (belt gate). Price gates make
  2× Cash more valuable; belt gates affect everyone equally.
* Events: a `cashMultiplier` event speeds everyone up; a `luckMultiplier` event shortens only the belt gate (it
  never changes mutation chances).
