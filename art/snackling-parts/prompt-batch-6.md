# Steal a Snackling: 3D model batch 6 (Easter 2027 event Snacklings)

You're designing 3D models for my Roblox game **Steal a Snackling**. Snacklings are collectible food-animal hybrids (a Pizza Pup is a puppy made of pizza). Players buy them off a conveyor belt and show them off on podiums in their bases, where they earn cash, and other players try to steal them. These four only appear during the Easter 2027 event (19 March to 6 April), so they should feel like an Easter basket come to life: pastel colours, chocolate, eggs and spring.

Build **batch 6, 4 Snacklings**, as one design: a gallery page that previews every model in real 3D, with the exact parts data I'll import into the game embedded in it.

(The game already has hand-built versions of these four in `art/snackling-parts/batch-6.json`; your design replaces that file.)

## Art direction

- Premium, toy-like Roblox pet style: chunky, soft and rounded, big heads, bright candy colours, a glossy finish. Original designs only: no existing characters, brands, logos or text anywhere.
- Each one must read instantly from across a base. The food is unmistakable (crust, fillings, glaze, sprinkles), and so is the animal (ears, snout, tail, horns). Keep the food, the animal and the main colours from its brief so players still recognise their Snackling. Put the effort into shape, proportion, detail and charm.
- Faces: big glossy eyes (a white Eye, a dark Pupil `#1E1A24`, one or two small white Highlights), a small mouth, and blush Cheeks where they suit. The face points toward -Z and must be clearly visible from the front and from above the front, because players look down at podiums.
- Shade with colour, because Roblox lighting is simple: give big shapes a slightly darker underside piece or rim and a lighter top where it helps.
- Pose: a calm standing or sitting idle pose, stable on a flat podium. The game adds its own bounce, so avoid extreme poses.
- Ambition by rarity: this is a limited-time Easter collection, so make every one feel sweet and special. The Rare is simple and adorable (about 34-44 parts), the Epic adds a signature detail (about 40-48 parts), the Legendary feels grand (about 44-56 parts) and the Mythic is majestic, with a little Neon glow (about 46-56 parts).

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
{"format": "snackling-parts-1", "batch": 6, "creatures": [{"id": "...", "parts": [PART, PART, ...]}, ...]}
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

## Batch 6: Easter 2027, at most 48 parts (Rare, Epic) or 56 parts (Legendary, Mythic)

1. **Custard Chick** (`custard_chick`, Rare). *"Fresh out of the egg. Still a little runny."* (Easter limited edition.) A round, glossy custard-yellow chick (`#FFE27A`, deeper `#F6C445` wings and tail feathers, a paler `#FFEDA0` chest tuft) just hatched from a milk-chocolate egg (`#6E3B1F`): it sits in the bottom half, which has a jagged cracked rim, a pastel pink icing ribbon round its middle (`#FF9EC7`) and piped icing dots in mint, lilac and lemon. Little wings raised, an orange beak (`#FF9A2E`, a darker lower beak), pink cheeks, and a glossy caramel cap (`#C8761E`) on its head dripping down at the front, like the top of a crème caramel.
2. **Hot Cross Bunny** (`hot_cross_bunny`, Epic). *"Glazed, spiced and very hoppy about it."* (Easter limited edition.) A sitting bunny whose body is a glazed hot cross bun (`#C77A35`, a shiny lighter top `#DC9248`, a darker underside `#A85F25`) with a thick white icing cross (`#FFF8EE`) piped over its back, a pat of butter (`#FFE680`) melting where the cross meets, and dark raisins (`#3E1E14`) pressed into it. A round bun-coloured head with a smaller icing cross on its forehead (so it reads from the front), a cream muzzle (`#FFE7C7`), a pink nose, two buck teeth, pink cheeks, tall ears with cream insides, paws tucked in front, big feet and a white cotton tail.
3. **Lemon Meringue Lamb** (`lemon_meringue_lamb`, Legendary). *"Toasted on top, zesty underneath."* (Easter limited edition.) A lamb built like the pie, in layers: a golden shortcrust underside (`#E3A95C`, Sand), a band of glossy lemon curd (`#FFD84A`) and a fleece of white meringue (`#FFF8EC`) made of soft puffs, each with a toasted golden top (`#EDB25E`). Four short, chunky shortcrust legs with dark hooves, a biscuit-golden face (Sand) with a paler muzzle, floppy ears with pink insides, a meringue tuft on its head and a candied lemon slice (yellow rind, pale segments) tucked by one ear.
4. **Jelly Bean Jackalope** (`jelly_bean_jackalope`, Mythic). *"Hides the eggs. Keeps the jelly beans."* (Easter limited edition.) A proud lavender hare (`#CDB8FF`, a pale `#F3ECFF` belly and muzzle) sitting up tall, with long ears (pink insides), big hind feet, buck teeth and pink cheeks, and a pair of antlers made of jelly beans in candy colours (pink, yellow, mint, orange, sky blue, purple), their tips glowing softly (Neon). Jelly beans dot its coat, a sky-blue ribbon bow sits at its neck and it guards a jewelled golden egg (`#F2C14E`, Foil) with a glowing pink band. Mythic: the antler tips and the egg's band may glow in Neon.
