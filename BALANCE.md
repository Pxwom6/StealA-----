# BALANCE

How the economy is shaped, and how long each rarity takes to reach. Every number here comes from the config
modules in `src/shared/Config/` and is reproduced by:

```sh
lune run tools/simulate.luau      # ~40 s, prints the two tables below
```

Re-run it after any change to `Creatures.luau`, `Rarities.luau`, `Economy.luau` or `Gameplay.luau` and paste
the new tables here.

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
players win 40% of the belt items this player wanted.

| Rarity | Free player | 2x Cash pass | 2x Cash + VIP + Extra Podiums |
| --- | --- | --- | --- |
| Common | 7s | 7s | 7s |
| Uncommon | 2m 0s | 1m 15s | 1m 10s |
| Rare | 4m 57s | 2m 47s | 2m 37s |
| Epic | 11m 37s | 7m 0s | 6m 20s |
| Legendary | 32m 12s | 19m 52s | 18m 35s |
| Mythic | 2h 0m | 1h 21m | 1h 8m |
| Secret | 9h 35m | 5h 58m | 5h 49m |
| First rebirth affordable | 1h 4m | 39m 30s | 35m 30s |

Median cash/sec after N minutes of play:

| Play time | Free player | 2x Cash pass | 2x Cash + VIP + Extra Podiums |
| --- | --- | --- | --- |
| 10m | $925/s | $5.26K/s | $6.99K/s |
| 30m | $7.96K/s | $31K/s | $37.6K/s |
| 1h | $27.6K/s | $74.6K/s | $90.4K/s |
| 3h | $164K/s | $378K/s | $485K/s |
| 8h | $473K/s | $1.41M/s | $1.73M/s |
| 24h | $2.2M/s | $5.26M/s | $6.09M/s |

Reading it: a free player gets a Legendary in their first session, a Mythic within a couple of sessions and a
Secret over a few days — and can shortcut any of it by stealing. A 2× Cash owner gets there roughly 35–45% sooner.

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

**Cash packs** (`Economy.cashPacks`) pay N seconds of the buyer's current income, rounded down to 2 significant
digits, with a floor so they are worth something on day one: Snack Pack 15 min (min $2.5K), Snack Crate 1 h
(min $15K), Snack Truck 6 h (min $120K). They therefore stay meaningful at every stage instead of becoming
worthless (fixed amounts) or game-breaking (huge fixed amounts).

**Offline earnings** (`Economy.offline`): 50% of income for up to 2 h away (VIP: 3 h), only after 2+ minutes away.

**Daily streak** (`Economy.daily`): 7-day cycle, reward = max(minimum, N minutes of income), from 3 minutes on
day 1 to 45 minutes on day 7. Missing a day resets the streak.

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
* Events: a `cashMultiplier` event speeds everyone up; a `luckMultiplier` event shortens only the belt gate.
