# Steal a Snackling: 3D model batch 4 (Winter 2026 event Snacklings)

You're designing 3D models for my Roblox game **Steal a Snackling**. Snacklings are collectible food-animal hybrids (a Pizza Pup is a puppy made of pizza). Players buy them off a conveyor belt and show them off on podiums in their bases, where they earn cash, and other players try to steal them. These four only appear during the Winter 2026 event (18 December to 4 January), so they should feel like a holiday treat.

Build **batch 4, 4 Snacklings**, as one design: a gallery page that previews every model in real 3D, with the exact parts data I'll import into the game embedded in it.

(The game already has hand-built versions of these four in `art/snackling-parts/batch-4.json`; your design replaces that file.)

## Art direction

- Premium, toy-like Roblox pet style: chunky, soft and rounded, big heads, bright candy colours, a glossy finish. Original designs only: no existing characters, brands, logos or text anywhere.
- Each one must read instantly from across a base. The food is unmistakable (crust, fillings, glaze, sprinkles), and so is the animal (ears, snout, tail, horns). Keep the food, the animal and the main colours from its brief so players still recognise their Snackling. Put the effort into shape, proportion, detail and charm.
- Faces: big glossy eyes (a white Eye, a dark Pupil `#1E1A24`, one or two small white Highlights), a small mouth, and blush Cheeks where they suit. The face points toward -Z and must be clearly visible from the front and from above the front, because players look down at podiums.
- Shade with colour, because Roblox lighting is simple: give big shapes a slightly darker underside piece or rim and a lighter top where it helps.
- Pose: a calm standing or sitting idle pose, stable on a flat podium. The game adds its own bounce, so avoid extreme poses.
- Ambition by rarity: this is a limited-time winter collection, so make every one feel festive and special. The Rare is simple and adorable (about 34-44 parts), the Epic adds a signature detail (about 40-48 parts), the Legendary feels grand (about 44-56 parts) and the Mythic is majestic, with a little Neon glow (about 46-56 parts).

## Hard rules (the importer rejects anything else)

1. **Shapes.** Use only these primitives, because Roblox has no others:
   - `sphere`: an ellipsoid; size = [diameter x, diameter y, diameter z], any three values.
   - `box`: size = [x, y, z].
   - `cylinder`: circular only, with its axis along its local Y; size = [diameter, height, diameter], and size[0] must equal size[2].
   - `wedge`: a right-triangular prism filling half of its box [x, y, z]. It has a flat bottom and a full-height vertical face at the back (+Z), and its slope rises from the bottom-front edge (y = -y/2, z = -z/2) to the top-back edge (y = +y/2, z = +z/2). In three.js, build it as a BufferGeometry from those six corners.

   No cones, tori, capsules, tapered cylinders, CSG, meshes, textures or text. Build those shapes from primitives instead: a donut from 10-12 overlapping spheres around a circle, a cone from stacked shrinking cylinders, a capsule from a cylinder with a sphere on each end, a curving tail from a chain of overlapping spheres.
2. **Space.** Right-handed, +Y up, units "u". Every part must lie inside x in [-1, 1], z in [-1, 1] and y in [0, 2], measured on its rotated extent. Nothing goes below y = 0: the feet (or belly) rest exactly on y = 0. Centre the creature on x = 0, z = 0 and make it big, with its largest dimension at least 1.8 u. I rescale each model to its in-game size, so only proportions matter.
3. **Facing.** The face looks toward -Z, and tails go toward +Z.
4. **Placement.** Position is the part's centre. Rotation is [rx, ry, rz] in degrees, applied as in three.js Euler order "XYZ" (`object.rotation.set` with those values in radians).
5. **Budget.** At most **48 parts** for the Rare and the Epic and **56 parts** for the Legendary and the Mythic, counting everything. Spend the budget on polish, not filler. No dimension of any part is smaller than 0.03 u.
6. **Overlap.** Overlap parts slightly rather than letting surfaces touch flush, so nothing flickers. Press details like spots and stripes partly into the surface.
7. **Colour and material.** Give each part one `#RRGGBB` colour and one of these materials:
   - `SmoothPlastic`: the default.
   - `Sand`: sugar, salt, crumbs, rice, powdered coatings.
   - `Fabric`: fluffy things like cotton candy, wool and fur.
   - `Glass`: jelly, gummy, syrup and bubbles, with transparency 0.1-0.4.
   - `Ice`: frosty gelato or icing.
   - `Foil`: wrappers and gold foil.
   - `Metal`: spoons and cups.
   - `Wood`: sticks and chopsticks.
   - `Cardboard`: cartons and boxes.
   - `Neon`: glow, only for magical accents on Legendary, Mythic and Secret, a few parts at most.
8. **Roles and names.** Give each part a role:
   - `body`: the shapes that make the silhouette (body, head, limbs, ears, tail, the main food pieces).
   - `face`: eyes, pupils, highlights, mouth, tongue, teeth, cheeks, brows, nose, eye patches.
   - `detail`: small toppings and accessories (sprinkles, seeds, crumbs, chips).

   Name face parts exactly one of Eye, Pupil, Highlight, Mouth, Tongue, Teeth, Cheek, Brow, Nose or Patch; names can repeat. Give other parts short PascalCase names (Body, Head, EarL, Tail, Crust).

## The data (exact format)

Put every model in ONE JSON object, embedded in the page as `<script type="application/json" id="snackling-parts">...</script>`. Render the previews from that same data, so the preview is exactly what I import:

```json
{"format": "snackling-parts-1", "batch": 4, "creatures": [{"id": "...", "parts": [PART, PART, ...]}, ...]}
```

`PART = [name, shape, size, position, rotation, color, material, role]`, with an optional 9th value for transparency (0-0.6). For example:

```json
["Body", "sphere", [1.2, 0.62, 1.5], [0, 0.55, 0.1], [0, 0, 0], "#FFD34E", "SmoothPlastic", "body"]
```

Round numbers to 3 decimals. Use each id exactly as given, in the order given. The preview podium is not part of the data.

## The page

- A grid of cards, one per Snackling, each with a 3D render, the name, a rarity tag, the part count and its checks.
- Use ONE `THREE.WebGLRenderer` for the whole page, because browsers allow only about 16 WebGL contexts. Render each card's thumbnail with it and copy the result to a 2D canvas, or use scissor viewports. Load three.js r128 from `https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js` and write drag-to-rotate yourself (no OrbitControls).
- Thumbnails show the podium view: the camera above and in front of the face side (-Z), for example at (1.4, 2.3, -3.4) looking at (0, 0.85, 0), with the creature on a simple grey round podium. Light it like Roblox daylight: a sun from above the front plus a soft sky-and-ground hemisphere light.
- Clicking a card opens a large viewer with drag-to-rotate and Front / Side / Back / Top buttons.
- Checks per card, computed in the page from the data: inside the box, lowest point at y = 0, parts within the budget, cylinders circular, a face present (an Eye, plus a Mouth or a beak), and only known shapes, materials and roles. Fix anything that fails before you finish.
- A "Copy JSON" button at the top that copies the whole object.

## How to work

Design and check one Snackling at a time, in the order given. If you run out of room, finish the one you're on completely, then tell me which ids are left and I'll ask you to continue.

## Batch 4: Winter 2026, at most 48 parts (Rare, Epic) or 56 parts (Legendary, Mythic)

1. **Peppermint Puffin** (`peppermint_puffin`, Rare). *"Minty fresh. Slightly flappy."* (Winter limited edition.) A plump, round puffin standing on big orange webbed feet (`#FF7A2E`): a near-black back, wings and head (`#2B2D3A`, a darker `#21232D` underside) and a white face (`#FFFFFF`). Its belly is a round peppermint candy: a white disc with a red six-blade pinwheel swirl (`#E8253A`). A big puffin beak, tall and narrow and tapering to a point, striped like a candy cane: an orange base, red with two white bands. A floppy red Santa hat (`#D7263D`) with a white fluffy brim and pompom (Fabric), its tip falling to one side.
2. **Candy Cane Chameleon** (`candy_cane_chameleon`, Epic). *"Blends in anywhere festive."* (Winter limited edition.) A chameleon low on four short, splayed red legs (`#E8253A`) with white gripping feet. Its white body (`#FFF6F2`, pale `#EFDCDD` underside) is wrapped in thick diagonal red stripes like a candy cane, and its tail rises behind it and hooks forward over its back like the crook of a candy cane, in alternating red and white bands. Big round eyes in red turret sockets, a red rounded casque on the back of its head with a holly sprig (green leaves `#2E8B57`, red berries `#C41C30`), a wide smile, pink cheeks, and small red and white crest bumps down its spine.
3. **Yule Log Yak** (`yule_log_yak`, Legendary). *"Rolled, frosted and ready to roam."* (Winter limited edition.) A yak on four short dark legs (`#41261A`, hooves `#2A1A10`) whose body is a chocolate yule log lying along its back (`#5A3420`): the cut end at the back shows a cream sponge (`#F6E7D2`) rolled around a chocolate spiral (`#6B3E24`), and a cut branch stub sticks up from the top. A shaggy fringe of chocolate fur (`#4A2A18` / `#5C3520`, Fabric) hangs down both sides. A big friendly head (`#6B3E24`) with a tan muzzle (`#A87452`), two nostrils, shaggy bangs, small ears and white-chocolate horns (`#FFF4E2`) curving out and up. On top: powdered-sugar snow (white, Sand), a holly sprig with red berries and a meringue mushroom (`#FFF8EE` cap, `#F5E6D0` stem). A short shaggy tail.
4. **Spun Sugar Stag** (`spun_sugar_stag`, Mythic). *"Glitters in the first snowfall."* (Winter limited edition.) A graceful young stag on four slim legs (`#D9E4FA`) with silver hooves (`#C9D2E6`, Foil): a frosted pale-blue body (`#DCE8FF`) with a white belly, a fluffy white spun-sugar ruff on its chest (Fabric) and a fluffy mane down the back of its neck. Large branching antlers of translucent spun sugar (`#A9DCFF`, Glass, transparency 0.2) hung with little gold and red baubles (`#FFC83D` / `#E8253A`, Foil). A red ribbon collar (`#D7263D`) with a golden bell, a white muzzle with a blue nose (`#7F93D6`), deep navy pupils (`#25305E`), pink cheeks and pink inner ears, a white tail puff. Mythic: a glowing pale-blue Neon snowflake (`#6EC6FF`) on its chest.
