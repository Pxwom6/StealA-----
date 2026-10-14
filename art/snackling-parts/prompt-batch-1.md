# Steal a Snackling: 3D model batch 1 of 3 (Commons & Uncommons)

You're designing 3D models for my Roblox game **Steal a Snackling**. Snacklings are collectible food-animal hybrids (a Pizza Pup is a puppy made of pizza). Players buy them off a conveyor belt and show them off on podiums in their bases, where they earn cash, and other players try to steal them. Every Snackling already exists in the game as a simple model built from basic shapes. This is the polished redesign.

Build **batch 1 of 3, 20 Snacklings**, as one design: a gallery page that previews every model in real 3D, with the exact parts data I'll import into the game embedded in it.

## Art direction

- Premium, toy-like Roblox pet style: chunky, soft and rounded, big heads, bright candy colours, a glossy finish. Original designs only: no existing characters, brands, logos or text anywhere.
- Each one must read instantly from across a base. The food is unmistakable (crust, fillings, glaze, sprinkles), and so is the animal (ears, snout, tail, horns). Keep the food, the animal and the main colours from its brief so players still recognise their Snackling. Put the effort into shape, proportion, detail and charm.
- Faces: big glossy eyes (a white Eye, a dark Pupil `#1E1A24`, one or two small white Highlights), a small mouth, and blush Cheeks where they suit. The face points toward -Z and must be clearly visible from the front and from above the front, because players look down at podiums.
- Shade with colour, because Roblox lighting is simple: give big shapes a slightly darker underside piece or rim and a lighter top where it helps.
- Pose: a calm standing or sitting idle pose, stable on a flat podium. The game adds its own bounce, so avoid extreme poses.
- Ambition by rarity: Commons are simple and adorable (about 20-30 parts). Uncommons add a signature detail (about 26-38 parts).

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
5. **Budget.** At most **38 parts** per Snackling, counting everything. Spend the budget on polish, not filler. No dimension of any part is smaller than 0.03 u.
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
{"format": "snackling-parts-1", "batch": 1, "creatures": [{"id": "...", "parts": [PART, PART, ...]}, ...]}
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

## Batch 1: Commons & Uncommons, at most 38 parts each

1. **Pizza Pup** (`pizza_pup`, Common). *"Extra cheesy. Fetches crusts."* A puppy on four short legs. Its body is a thick pizza slice lying flat along its back, the point toward the tail and a puffy golden crust (`#D98A3A`) across the front like a collar. Melted cheese top (`#FFD34E`) with 3 pepperoni discs (`#D64933`) and 2 cheese drips running down the sides. Round dough-coloured head (`#F4BE7A`), floppy ears (`#C9782E`), cream muzzle (`#FFE6C2`) with a dark nose (`#3A2A2E`), happy open smile, thin tail tipped `#C9782E`.
2. **Cookie Crab** (`cookie_crab`, Common). *"Walks sideways. Leaves a trail of crumbs."* A wide, flat chocolate-chip cookie (`#E2A85C`, a slightly darker baked rim) is the crab's whole body, with 4-5 chocolate chips (`#4A2A16`) pressed into the top. Big round eyes sit up on the front edge with a wide grin below. Two chunky claws (`#C98A45`, lighter `#E9B872` pincer tips) raised at the sides, 3 short legs per side (`#B8783A`).
3. **Marshmallow Mouse** (`marshmallow_mouse`, Common). *"Squishy, sweet and a little bit toasty."* A plump standing marshmallow (a short cylinder with softly rounded top edges, `#FFF8F0`) is body and head in one, with a lightly toasted golden top (`#F2C48A`). Round mouse ears (`#FFF8F0`, pink inner `#FFC2D1`), pink nose (`#FF7FA0`), little cat-like mouth, blush cheeks (`#FF9FB8`), thin whiskers (`#D8C0C0`), tiny pink feet and a thin curling pink tail.
4. **Pretzel Pal** (`pretzel_pal`, Common). *"Gets itself in knots."* A small two-legged buddy whose torso is a soft pretzel knot standing upright and facing front: the classic twist with three holes, glossy baked brown (`#A0602A`) with darker edges (`#5E3414`). Round bready head (`#B8732E`) on top, coarse white salt crystals (Sand) on the head and pretzel, a big grin with blush (`#FF9F7A`), stubby arms and feet (`#A0602A`).
5. **Chip Chick** (`chip_chick`, Common). *"Crunchy on the outside, chirpy on the inside."* A round chick made of a golden potato chip: a wavy yellow body (`#FFD45C`) with a few curved ridge bands (`#E0A030`), a slightly bigger round head (`#FFDE6A`) with a two-feather crest (`#FFD45C` / `#F2B33D`), an orange beak (`#FF9F2E`, darker `#E8782A` lower half), tiny wings (`#F2B33D`), orange feet and a few salt crumbs on the head. Beak only, no mouth.
6. **Cracker Quacker** (`cracker_quacker`, Common). *"Quacks up at its own jokes."* A duckling with a square saltine-cracker body (`#E8B25E`) with a neat grid of small docking holes (`#C88A3C` dots) on its front and white salt crumbs. Round yellow head (`#FFE07A`), flat orange bill (`#FF9F2E`, darker `#E8782A` lower), tiny cracker-coloured wings and a stubby tail, orange webbed feet, blush cheeks (`#FF8FA8`).
7. **Gummy Grub** (`gummy_grub`, Common). *"Wobbles when happy. Always happy."* A plump gummy caterpillar standing upright: lime gummy body (`#7CDB4C`) ringed by three coloured gummy segment bands (`#FFE14D`, `#FF9F2E`, `#FF5A5A`). Big shiny eyes, a cheeky smile, blush (`#FF7FAF`), two antennae with pink gummy tips (`#FF5FA2`), little green feet (`#5FC23A`). Glass at low transparency suits the bands; keep the face opaque.
8. **Jellybean Jellyfish** (`jellybean_jellyfish`, Common). *"Every tentacle is a different flavor."* A bell-shaped jellyfish dome (`#FF6FAE`, a lighter `#FFC2DE` rim and underside) with a cute face on the front of the dome and white and yellow speckles on top. Six tentacles hang down to the ground, each a short stack of 2-3 jellybeans in different flavour colours (pink, yellow, lime, purple, orange, light blue). It stands on its tentacles, so they reach y = 0.
9. **Cheese Puff Puffer** (`cheese_puff_puffer`, Common). *"Puffs up when surprised. Leaves orange fingerprints."* A round pufferfish made of a lumpy orange cheese puff (`#FF9A2E` with `#FFB347` lumps), covered in short soft spikes (`#FFD07A`), with a small dorsal fin and a tail fin (`#FFB347`), big surprised eyes, a little round 'o' mouth and cheese-dust crumbs (Sand). It rests on its belly and two small side fins.
10. **Toast Toad** (`toast_toad`, Common). *"Pops up when you least expect it."* A frog sitting upright whose body is a slice of toast standing on its edge: pale bread face (`#F7DFA8`) framed by a thick golden-brown crust (`#C07A32`) all round. A melting butter pat (`#FFE680`) on top with two drips. Big froggy eyes bulge up over the top edge, a wide smile below, green frog legs and feet (`#7CC35A`) folded at the bottom sides.
11. **Sushi Slug** (`sushi_slug`, Uncommon). *"Rolls everywhere. Literally."* A slug whose body is a long sushi roll lying on the ground: white rice (`#FBF7EF`, Sand for texture) with a salmon slab draped over the top (`#FF8A5B` with lighter `#FFC2A0` stripes), a nori band (`#22302A`) around the middle and a sprinkle of sesame seeds. Two eye stalks with eyes at the front end and a small smile.
12. **Fry Fox** (`fry_fox`, Uncommon). *"Sly, salty and always comes in a box."* A fox standing on four legs whose body is a red fry carton (`#E8403A`, Cardboard) packed with golden fries sticking out of the top at different heights and angles (`#FFD25A` / `#FFC83D`). Orange fox head (`#F28A3C`) with big pointy ears, cream muzzle (`#FFF1E0`) and dark nose, a sly little smile, a fluffy orange tail with a cream tip, dark brown legs (`#7A4A32`).
13. **Pudding Pug** (`pudding_pug`, Uncommon). *"Wobbles. Snorts. Wobbles some more."* A pug-shaped caramel pudding: a squat, wobbly golden custard body (`#FFD27A`) with a glossy dark caramel top (`#9A521C`) dripping down the sides. Pug face on the front with a dark wrinkly muzzle (`#6B4428`), nose (`#2A1A14`), big eyes and a tongue poking out, floppy brown ears, stubby legs (`#E8B860`), a curly tail at the back.
14. **Nacho Newt** (`nacho_newt`, Uncommon). *"Cheese-powered and proud."* A newt on four legs whose back is a big triangular tortilla chip (`#F2C14E`, slightly curled) drizzled with nacho cheese (`#FFB627`) that drips over the edges, plus a few jalapeño rings (`#5BBF3A`). Orange newt head (`#FF9F45`) with big eyes and a smile, a long tapering tail (`#FF9F45` fading to `#F2C14E`), little orange legs.
15. **Bao Bunny** (`bao_bunny`, Uncommon). *"Fluffy, steamy and extra huggable."* A round, fluffy steamed bao bun (`#FFF6EA`, soft and matte) is the bunny's whole body, with the pleated twist on top (`#FFFDF8`). Two long upright ears (`#FFF6EA`, inner pink `#FFC2D1`) with a pink bow (`#FF7FAF`) between them, happy closed-arc eyes, a little 'o' mouth, pink nose (`#FF8FAF`), blush, a white puff tail and tiny feet. Optional: a wisp of steam.
16. **Pickle Piglet** (`pickle_piglet`, Uncommon). *"Briny, bumpy and very oinky."* A piglet on four short legs whose body is a bumpy green pickle lying lengthwise (`#6FB536` with lighter `#8FD14F` bumps). Round green head (`#7CC340`), a pale green pig snout (`#A8E06A`) with two dark nostrils (`#3F7A1E`), pointy ears, a curly tail, darker green legs (`#5FA02E`), a happy smile and blush.
17. **Mochi Moth** (`mochi_moth`, Uncommon). *"Squishy wings, powdery hugs."* A round pink mochi body (`#FFD6E8`) dusted with white powder dots, with four soft mochi wings: pale mint upper wings (`#C8F0D8`) and pink lower wings (`#FF9FC8`), flat and rounded, angled up and back. Two feathery antennae (`#8A6A5A` with white fluffy tips), big shiny eyes, a smile, tiny pink feet.
18. **Hotdog Dachshund** (`hotdog_dachshund`, Uncommon). *"Twice as long, twice the relish."* A very long, low dachshund (fill the box along Z) whose body is a hot dog: a glossy sausage (`#C8553D`) lying lengthwise in a split bun (`#F2C27A`) that wraps its sides, with a yellow mustard zigzag (`#FFD23F`) along the top. Brown dog head (`#B5653A`) at the front with long floppy dark ears (`#7A3A1E`), tan muzzle (`#D9945F`) and dark nose, four short brown legs (`#8A4A2A`), a stubby tail.
19. **Muffin Moose** (`muffin_moose`, Uncommon). *"Berry tall. Berry proud."* A small moose whose body is a blueberry muffin: a fluted sky-blue paper cup (`#7FB8E8`) with the golden-brown domed top (`#C98A4B`) overflowing it, studded with blueberries (`#3A3A8F` / `#4A4AA8`). Brown moose head (`#8A5A3C`) with a tan muzzle (`#C08A62`) and big flat cream antlers (`#E8C28A`) with three points each, dark legs (`#6B4428`).
20. **Waffle Wombat** (`waffle_wombat`, Uncommon). *"Has a pocket for syrup."* A chunky wombat on four short legs whose body is a thick square waffle (`#E3A857`) with a raised grid of bars (`#C98A3C`) on top, a butter pat (`#FFE680`) and syrup (`#8A4A1A`) running down the sides. Round grey-brown wombat head (`#9A7A62`) with small round ears, a broad pale muzzle (`#C8A890`) and dark nose, stubby dark legs (`#7A5A42`).
