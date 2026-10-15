# Offline 3D preview

A dev tool for looking at maps and Snacklings without Studio. Not part of the game.

`tools/worldsim` runs the game's real map and model code in Lune and exports what it built as JSON; this renders
that JSON with three.js in headless Chromium and writes PNGs. Lighting, materials and terrain are approximations of
Roblox's, so use it to check shapes, layout, proportions and colours. Studio has the final say on materials and
lighting.

```sh
npm install --prefix tools/preview             # once: three + playwright-core (no browser download)

# A map theme (see Config/MapThemes for ids): overview, aerial, plaza, plots, belt, south, north, west, east
lune run tools/worldsim/export.luau candy build/candy.json
node tools/preview/render.mjs build/candy.json build/candy
node tools/preview/render.mjs build/candy.json build/candy --shots plaza,plots
node tools/preview/render.mjs build/candy.json build/candy --cam 0,80,200:0,10,60:50    # x,y,z:tx,ty,tz:fov

# A map with a seasonal event's theme on (its decorations and lighting), e.g. the Harvest Feast
lune run tools/worldsim/exportSeason.luau meadow Harvest2026 build/harvest-meadow.json
node tools/preview/render.mjs build/harvest-meadow.json build/harvest-meadow --shots plots,belt

# Snacklings in a row: front, threeQuarter, back, side, top
lune run tools/worldsim/exportCreatures.luau build/lineup.json pizza_pup pizza_pup:golden matcha_manta
lune run tools/worldsim/exportCreatures.luau build/lineup.json rarity:Mythic
lune run tools/worldsim/exportCreatures.luau build/lineup.json event:Winter2026
lune run tools/worldsim/exportCreatures.luau build/lineup.json mutations:pizza_pup
node tools/preview/render.mjs build/lineup.json build/lineup --labels
```

Options: `--size 1280x720`, `--cell 4` (terrain voxel size in studs), `--no-shadows`, `--no-fog`, `--labels`
(names over a lineup). Chromium comes from Playwright's browser folder; set `CHROMIUM_PATH` to use another one.
A map takes about 10 s per shot on a software renderer.
