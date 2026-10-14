# Steal a Snackling: 3D model batch 5 (Valentine's 2027 event Snacklings)

You're designing 3D models for my Roblox game **Steal a Snackling**. Snacklings are collectible food-animal hybrids (a Pizza Pup is a puppy made of pizza). Players buy them off a conveyor belt and show them off on podiums in their bases, where they earn cash, and other players try to steal them. These four only appear during the Valentine's 2027 event (5 to 16 February), so they should feel like a box of Valentine's chocolates come to life.

Build **batch 5, 4 Snacklings**, as one design: a gallery page that previews every model in real 3D, with the exact parts data I'll import into the game embedded in it.

(The game already has hand-built versions of these four in `art/snackling-parts/batch-5.json`; your design replaces that file.)

## Art direction

- Premium, toy-like Roblox pet style: chunky, soft and rounded, big heads, bright candy colours, a glossy finish. Original designs only: no existing characters, brands, logos or text anywhere.
- Each one must read instantly from across a base. The food is unmistakable (crust, fillings, glaze, sprinkles), and so is the animal (ears, snout, tail, horns). Keep the food, the animal and the main colours from its brief so players still recognise their Snackling. Put the effort into shape, proportion, detail and charm.
- Faces: big glossy eyes (a white Eye, a dark Pupil `#1E1A24`, one or two small white Highlights), a small mouth, and blush Cheeks where they suit. The face points toward -Z and must be clearly visible from the front and from above the front, because players look down at podiums.
- Shade with colour, because Roblox lighting is simple: give big shapes a slightly darker underside piece or rim and a lighter top where it helps.
- Pose: a calm standing or sitting idle pose, stable on a flat podium. The game adds its own bounce, so avoid extreme poses.
- Ambition by rarity: this is a limited-time Valentine's collection, so make every one feel sweet and special. The Rare is simple and adorable (about 34-44 parts), the Epic adds a signature detail (about 40-48 parts), the Legendary feels grand (about 44-56 parts) and the Mythic is majestic, with a little Neon glow (about 46-56 parts).

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
{"format": "snackling-parts-1", "batch": 5, "creatures": [{"id": "...", "parts": [PART, PART, ...]}, ...]}
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

## Batch 5: Valentine's 2027, at most 48 parts (Rare, Epic) or 56 parts (Legendary, Mythic)

1. **Candy Heart Hamster** (`candy_heart_hamster`, Rare). *"Says BE MINE. Means ALL MINE."* (Valentine's limited edition.) A round, chubby peach hamster (`#FFD2B3`, a deeper `#FFBE96` for ears, paws and tail) with a cream belly and muzzle (`#FFF6EE`), round ears with pink insides (`#FF9DB6`), little pink feet, whiskers, two buck teeth and cheek pouches stuffed so full they bulge (`#FFE3D0`). It hugs a big lavender conversation heart (`#C9A8FF`) in both paws, its message suggested by two short stamped red lines (`#E8334A`; no real letters), and a small mint candy heart (`#9EF0C6`) sits tilted on its head.
2. **Cherry Cordial Kitten** (`cherry_cordial_kitten`, Epic). *"Hard shell, soft centre, sweet on everyone."* (Valentine's limited edition.) A sitting dark-chocolate kitten (`#4A2818`, milk-chocolate `#8A5A3A` muzzle and paws) in a pleated gold foil candy cup (`#D9A441`, Foil). A pink cherry-cream heart on its chest (`#FF86A6`), white-chocolate drizzle (`#F3E3CF`) zig-zagging across its back, pointy ears with pink insides, cream whiskers, a pink nose and a tail curling round to the front with a pink cream tip. On its head, a glossy cherry (`#D61F3C`) with a green stem and a white shine.
3. **Red Velvet Raccoon** (`red_velvet_raccoon`, Legendary). *"Steals hearts. And the frosting."* (Valentine's limited edition.) A raccoon on four short legs made of crumbly red velvet cake (`#B0173A` with a crumb texture: Sand; darker `#8E1030` legs and ears) with a band of cream cheese frosting (`#FFF7EE`) round its middle like a cake layer. A three-tier frosting swirl on its back topped with a red heart sprinkle (`#E8253A`) and a few pink and white sprinkles. A cream muzzle with a dark nose, a dark raccoon mask across its eyes (`#4A0A1A`), cream inner ears, white whiskers and a big bushy tail curling up behind it in alternating cake and frosting rings with a dark tip.
4. **Rose Petal Pegasus** (`rose_petal_pegasus`, Mythic). *"Flies on rose petals. Lands in your heart."* (Valentine's limited edition.) A graceful blush-pink pegasus (`#FFE4EE`, a paler `#FFF2F6` muzzle) on four slim legs with golden hooves (`#F2C14E`, Foil). Its wings are fans of rose petals in deep to pale pinks (`#E8265E`, `#FF5C8A`, `#FF9AB8`, `#FFC2D6`), and its mane and tail are rose petals too. A rose with a green leaf in its forelock, soft pink cheeks, a rose-red ribbon collar (Fabric) with a golden heart pendant (Foil). Mythic: a few petals or the pendant may glow softly in Neon.
