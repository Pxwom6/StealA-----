# Steal a Snackling: 3D model batch 8 (Harvest Feast 2026 event Snacklings)

You're designing 3D models for my Roblox game **Steal a Snackling**. Snacklings are collectible food-animal hybrids (a Pizza Pup is a puppy made of pizza). Players buy them off a conveyor belt and show them off on podiums in their bases, where they earn cash, and other players try to steal them. These four only appear during the Harvest Feast 2026 event (20 to 30 November), so they should feel like a harvest feast come to life: warm autumn colours, pies, berries, pumpkins and baskets of produce.

Build **batch 8, 4 Snacklings**, as one design: a gallery page that previews every model in real 3D, with the exact parts data I'll import into the game embedded in it.

(The game already has hand-built versions of these four in `art/snackling-parts/batch-8.json`; your design replaces that file.)

## Art direction

- Premium, toy-like Roblox pet style: chunky, soft and rounded, big heads, bright candy colours, a glossy finish. Original designs only: no existing characters, brands, logos or text anywhere.
- Each one must read instantly from across a base. The food is unmistakable (crust, fillings, glaze, sprinkles), and so is the animal (ears, snout, tail, horns). Keep the food, the animal and the main colours from its brief so players still recognise their Snackling. Put the effort into shape, proportion, detail and charm.
- Faces: big glossy eyes (a white Eye, a dark Pupil `#1E1A24`, one or two small white Highlights), a small mouth, and blush Cheeks where they suit. The face points toward -Z and must be clearly visible from the front and from above the front, because players look down at podiums.
- Shade with colour, because Roblox lighting is simple: give big shapes a slightly darker underside piece or rim and a lighter top where it helps.
- Pose: a calm standing or sitting idle pose, stable on a flat podium. The game adds its own bounce, so avoid extreme poses.
- Ambition by rarity: this is a limited-time harvest collection, so make every one feel warm and special. The Rare is simple and adorable (about 34-44 parts), the Epic adds a signature detail (about 40-48 parts), the Legendary feels grand (about 44-56 parts) and the Mythic is majestic, with a little Neon glow (about 46-56 parts).

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
{"format": "snackling-parts-1", "batch": 8, "creatures": [{"id": "...", "parts": [PART, PART, ...]}, ...]}
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

## Batch 8: Harvest Feast 2026, at most 48 parts (Rare, Epic) or 56 parts (Legendary, Mythic)

1. **Cranberry Crane** (`cranberry_crane`, Rare). *"Jiggles when it walks. Struts anyway."* (Harvest Feast limited edition.) A plump, chesty crane whose body is a log of jellied cranberry sauce (`#C8143C`), tipped up like a crane on alert, with the darker ridges (`#97102F`) of the can it slid out of running round it and a glossy pink shine (`#FF8DA6`) along its top. Lighter jelly wings (`#E2385A`) with dark cranberry tips (`#6E0A20`), and a bustle of dark plumes swept up over its tail. A short neck and a big round head of sugar-frosted cranberry (`#FCE6EB`, Sand), pale like a real crane's, under a red crown of three glossy whole cranberries with two green leaves. A long golden beak (`#F4B942`, a darker lower beak), big eyes, pink cheeks, and short golden legs with three-toed feet.
2. **Pecan Pie Porcupine** (`pecan_pie_porcupine`, Epic). *"Prickly on top. Gooey underneath."* (Harvest Feast limited edition.) A round porcupine whose back is a whole pecan pie: a golden shortcrust shell (`#E3A55A`, a darker base `#C2843E`) with a crimped rim of plump bumps (`#F2BE72`), a glossy dome of dark caramel filling (`#6B3416`) and pecan halves (`#8A4A1E`, `#A8622C`) standing up out of it as quills, swept back. A swirl of whipped cream (`#FFF8EE`) on top is its signature detail. Its face pokes out of the front: a biscuit-golden head (`#E3A55A`) with a cream muzzle (`#F7D6A6`), a dark button nose, small round ears, big eyes and blush cheeks, with little paws under its chin and feet peeking out behind.
3. **Sweet Potato Sloth** (`sweet_potato_sloth`, Legendary). *"Takes it slow. Always gets seconds."* (Harvest Feast limited edition.) A sloth sitting up, made of a whole roasted sweet potato: coppery-rose skin (`#A9543A`) for fur, split open down the front to bright orange flesh (`#F5872E`), the skin curling back along both edges of the split, a few dark "eyes" in the skin on its back, and the tuber's pointy end behind as a stubby tail. A pale orange face (`#F9A75A`) with a sloth's dark eye stripes (`#5A2E1E`), a sleepy, happy smile, a dark nose and blush cheeks. Toasted marshmallows piled on its head for hair (white, with golden-brown toasted tops), a moss-green knitted scarf (`#4E8A4E`, Fabric), and long arms with big cream claws: one resting on its belly, one holding up a toasted marshmallow on a stick.
4. **Cornucopia Kirin** (`cornucopia_kirin`, Mythic). *"Never arrives empty-hooved."* (Harvest Feast limited edition.) A kirin whose body is a woven horn of plenty: wicker bands (`#D19446` and `#A86E2E`, Wood) tapering back from a wide mouth at its chest and curling up into its tail, with a thick woven lip (`#E8B565`) round a dark hollow. The harvest spills out of the mouth: a pumpkin, a red apple, a bunch of grapes and an ear of corn in its husk. Slender honey-gold legs (`#F2C46E`) with gilded hooves (Foil) and glowing flame tufts (`#FF7A1E`), a honey-gold neck and a big round dragon-deer head with a cream snout, big eyes, two swept-back golden horns (Foil), small ears, long whiskers and a flowing flame-coloured mane like autumn leaves (`#E8642A`, `#F28C28`) framing its face. Mythic: the flame tufts and the whiskers may glow in Neon.
