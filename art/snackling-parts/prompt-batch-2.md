# Steal a Snackling: 3D model batch 2 of 3 (Rares & Epics)

You're designing 3D models for my Roblox game **Steal a Snackling**. Snacklings are collectible food-animal hybrids (a Pizza Pup is a puppy made of pizza). Players buy them off a conveyor belt and show them off on podiums in their bases, where they earn cash, and other players try to steal them. Every Snackling already exists in the game as a simple model built from basic shapes. This is the polished redesign.

Build **batch 2 of 3, 21 Snacklings**, as one design: a gallery page that previews every model in real 3D, with the exact parts data I'll import into the game embedded in it.

## Art direction

- Premium, toy-like Roblox pet style: chunky, soft and rounded, big heads, bright candy colours, a glossy finish. Original designs only: no existing characters, brands, logos or text anywhere.
- Each one must read instantly from across a base. The food is unmistakable (crust, fillings, glaze, sprinkles), and so is the animal (ears, snout, tail, horns). Keep the food, the animal and the main colours from its brief so players still recognise their Snackling. Put the effort into shape, proportion, detail and charm.
- Faces: big glossy eyes (a white Eye, a dark Pupil `#1E1A24`, one or two small white Highlights), a small mouth, and blush Cheeks where they suit. The face points toward -Z and must be clearly visible from the front and from above the front, because players look down at podiums.
- Shade with colour, because Roblox lighting is simple: give big shapes a slightly darker underside piece or rim and a lighter top where it helps.
- Pose: a calm standing or sitting idle pose, stable on a flat podium. The game adds its own bounce, so avoid extreme poses.
- Ambition by rarity: Rares have a stronger silhouette and an accessory or two (about 30-42 parts). Epics are dynamic and full of character, with more layered food detail (about 36-48 parts).

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
5. **Budget.** At most **48 parts** per Snackling, counting everything. Spend the budget on polish, not filler. No dimension of any part is smaller than 0.03 u.
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
{"format": "snackling-parts-1", "batch": 2, "creatures": [{"id": "...", "parts": [PART, PART, ...]}, ...]}
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

## Batch 2: Rares & Epics, at most 48 parts each

1. **Taco Turtle** (`taco_turtle`, Rare). *"Slow, crunchy, unstoppable."* A turtle whose shell is a hard taco: a folded golden shell (`#F5C451` with darker `#E0A43A` toasted spots) standing along its back like a half-moon, stuffed with lettuce (`#5BBF3A`), tomato (`#E8433A`) and cheese (`#FFE066`) poking out of the top edge. Green turtle head, legs and stubby tail (`#8FD16A`), a cute smile and blush.
2. **Cinnamon Snail** (`cinnamon_snail`, Rare). *"Takes its sweet time. Literally."* A snail carrying a big cinnamon-roll shell: dough (`#D9A15B`) with a dark cinnamon swirl (`#8A4A1E`) spiralling in, and white icing (`#FFF8EE`) drizzled over it. Soft cream body (`#F3DDB8`) stretched long and low on the ground, two eye stalks with eyes at the front and a sweet smile.
3. **Macaron Macaw** (`macaron_macaw`, Rare). *"Talks in two flavors at once."* A parrot standing on two feet. Its head is a pink macaron (`#FF7FAF` shells with a cream `#FFF4E0` filling band and a ruffled edge) with rainbow sprinkles on top. Bright blue round body (`#3A8DFF`), a curved yellow beak (`#FFE07A`, dark `#3A3A40` lower half), a red and yellow crest (`#FF4B4B` / `#FFD23F`), wings with red and yellow feather tips, long fanned tail feathers (`#FF4B4B`, `#FFD23F`, `#3A8DFF`), grey feet.
4. **Bubblegum Bulldog** (`bubblegum_bulldog`, Rare). *"Chews loudly. Blows bigger."* A sturdy bulldog on four legs in bubblegum pink (`#FF8FC8` body, `#FFA3D2` head) with lighter pink spots (`#FFC2E2`). Wide jowly muzzle (`#FFD1E8`) with a dark pink nose (`#C8306A`), two little underbite teeth and grumpy-cute brows (`#D84A92`), floppy ears (`#E06AAA`), a stubby tail. It's blowing a big glossy bubblegum bubble (`#FF6FC0`, Glass) from its mouth.
5. **Burrito Bear** (`burrito_bear`, Rare). *"Wrapped up and ready for a hug."* A bear cub wrapped in a burrito like a blanket: a fat tortilla (`#F3E1B6` with toasted `#E0BE86` spots) wrapped around its body, open at the top with fillings poking out (lettuce `#5BBF3A`, tomato `#E8433A`, beans `#6B3A1E`, cheese `#FFD23F`). Brown bear head (`#8C5A2B`) with round ears (inner `#C8955F`), tan muzzle and dark nose, little brown paws poking out.
6. **Boba Beluga** (`boba_beluga`, Rare). *"Sings in bubbles. Pearls included."* A beluga made of a bubble-tea drink: a pearly white body (`#F4F7FB`) with a big rounded melon forehead, a milk-tea belly (`#D9B48F`) full of dark tapioca pearls (`#3B2418`) showing through, and a pink and white striped straw (`#FF7FA8` / `#FFFFFF`) sticking out of its back like a blowhole. Side flippers and a tail fluke (`#E2E8F0`). It rests on its belly and flippers.
7. **Gingersnap Gecko** (`gingersnap_gecko`, Rare). *"Crunchy tail, sticky feet."* A gecko walking low on four legs, made of gingersnap cookie (`#B9733A` body, `#C27E42` head) with white icing stripes (`#FFFFFF`) across its back and white icing brows. Three candy buttons (`#E8433A`, `#5BBF3A`, `#FFD23F`) down its back, big eyes, a white icing smile, a long curling tail and wide round toe pads.
8. **Brownie Beaver** (`brownie_beaver`, Rare). *"Builds its dams out of fudge."* A beaver on four legs whose body is a fudgy brownie block (`#5C3A21`) with a darker glossy top layer (`#3E2414`) and crumbs (`#D9B48A`). Brown head (`#8A5A3A`) with round ears, a light snout (`#C89A6A`), two big white buck teeth and a smile. A flat dark chocolate tail (`#4A2A16`) scored in a grid like a chocolate bar.
9. **Sundae Sheep** (`sundae_sheep`, Rare). *"Woolly, chilly and has a cherry on top."* A sheep whose fluffy wool is a scoop of vanilla ice cream: lumpy white wool (`#FFFDF6` / `#FFF8EC`) with chocolate sauce (`#5A3A2A`) dripping down it, rainbow sprinkles and a cherry (`#E8233A` with a stem) on top. Dark brown sheep face (`#7A4A32`), floppy dark ears (`#6B3E28`), dark legs, a sweet smile.
10. **Cupcake Cub** (`cupcake_cub`, Rare). *"Frosting first, questions later."* A bear cub standing upright whose body is a cupcake: chocolate cake (`#8B5A3C`) in a cyan fluted liner (`#7FD8F0`), and a pink frosting-swirl head (`#FF9FCF`) with round ears (inner `#FFD6EA`), a light muzzle (`#FFE3F1`) and a magenta nose (`#C8306A`). Rainbow sprinkles and a cherry on top of its head, pink paws.
11. **Candy Corn Cat** (`candy_corn_cat`, Rare). *"Nine lives, three stripes, zero chill."* (Halloween limited edition.) A cat on four legs in candy-corn bands: yellow (`#FFD23F`) at the bottom, orange (`#FF9F1C`) in the middle and white (`#FFF4DC`) on top. Orange head with pointy ears (white inner), cream muzzle with a pink nose (`#FF5FA2`), whiskers (`#5A3A2A`), a cheeky cat smile, a thin tail with a white tip.
12. **Ramen Raccoon** (`ramen_raccoon`, Epic). *"Slurps louder than you'd think."* A raccoon sitting upright in a ramen bowl that forms its lower body: a red bowl (`#E8433A`) with a white rim, golden broth (`#F2C46D`), wavy noodles (`#FFE9A0`) spilling over the rim, a halved soft-boiled egg (white with an orange `#FFB72B` yolk) and a pink-swirl fish cake slice. Grey raccoon head (`#9A9AA8`) with a dark bandit mask (`#4A4A55`), pointy ears and a white muzzle. A grey and dark ringed tail curls out of the bowl, and grey paws hold a pair of chopsticks (Wood).
13. **Omelet Owl** (`omelet_owl`, Epic). *"Up all night. Sunny side up all day."* A round owl made of a fluffy folded omelet: yellow egg body and head (`#FFD45C`) with a lighter folded belly (`#FFE89A`) along the fold seam, fillings peeking out of the fold (green herbs `#5BBF3A`, red pepper `#E8433A`, ham `#FF8FA0`). Big round eyes with orange brows (`#E8A93B`), a short orange beak, pointy ear tufts, feathered wings (`#F5C04A` tipped `#E8A93B`), orange feet.
14. **S'more Skunk** (`smore_skunk`, Epic). *"Smells like a campfire. In a good way."* A skunk on four legs whose body is a s'more: two graham-cracker slabs (`#D9A15B`) sandwiching a layer of chocolate (`#4A2A16`) and a gooey toasted marshmallow (`#FFF8EE` with golden toasty edges) that bulges out. Dark grey head (`#4A3A3A`) with round ears and a white stripe running from its head along its back. A huge fluffy dark tail with a white marshmallow stripe curling up and over. Tongue out.
15. **Tempura Tiger** (`tempura_tiger`, Epic). *"Crispy stripes, light and fierce."* A tiger on four legs made of crispy tempura: a lumpy golden batter body (`#F5C45A` with puffy `#FFD97A` bumps) with orange-brown tiger stripes (`#B8571E`) showing through. Orange tiger head (`#FF9A3C`) with round ears, cream muzzle, whiskers and a fierce-cute cat smile. Its tail ends in a tempura shrimp tail fan (`#FF5A3C` / `#FF7A4A`).
16. **Popcorn Penguin** (`popcorn_penguin`, Epic). *"Pops when excited. Pops a lot."* A penguin standing upright: navy body and head (`#2E3A59`) with a white belly and face mask, an orange beak and feet (`#FF9F2E`), tiny flippers. Its head is crowned with an overflowing heap of popcorn (fluffy kernels in `#FFF6D5`, `#FFE9A0` and `#FFFFFF` with buttery `#FFD25A` bits), plus a few kernels popping off. Optional: a red and white striped popcorn-box band around its middle.
17. **Nugget Narwhal** (`nugget_narwhal`, Epic). *"Comes with a dip of its choice."* A narwhal made of a chicken nugget: a lumpy golden-brown breaded body (`#E8A93B` with `#F5C45A` lumps and darker crumbs `#C9782E`), a long twisted tusk (`#FFD25A` spiralled with `#FFE07A`), side flippers and a tail fluke. It rests on its belly with a small dip cup of red sauce tucked against its side.
18. **Hamburger Hamster** (`hamburger_hamster`, Epic). *"Keeps fries in its cheeks for later."* A round hamster whose body is a cheeseburger: a sesame-seeded top bun (`#E8A24A` with cream `#FFF6E0` seeds), a lettuce frill (`#5BBF3A`), melted cheese (`#FFC83D`) drooping at the corners, a beef patty (`#6B3A1E`) and a bottom bun. The face sits on the front of the top bun: round ears (inner pink `#FFB8C8`), pink nose, a little cat-like mouth and chubby cheeks stuffed with fries (`#FFD25A`) poking out. Tiny paws.
19. **Spaghetti Yeti** (`spaghetti_yeti`, Epic). *"Abominably saucy."* A friendly yeti standing upright made of spaghetti: shaggy pale noodle fur (`#F5D98A`) built from many overlapping strands and loops, a red tomato-sauce cap on its head (`#D63A2A`) topped with meatballs (`#7A3A1E`) and parmesan crumbs (white, Sand). A big grin with bushy brows (`#E8C060`), long arms, big feet.
20. **Bagel Badger** (`bagel_badger`, Epic). *"Everything bagel. Everything attitude."* A badger on four legs whose body is an everything bagel lying flat (`#D9A15B`, glossy) with cream cheese (`#FFF8E8`) showing in the hole and white, black and tan seeds all over. Grey badger head (`#8A8A92`) with a white stripe from its nose over its head and down its back, dark round ears, a white muzzle with a dark nose, short dark legs (`#3A3A40`), a stubby tail. A confident little smirk.
21. **Pumpkin Pie Bat** (`pumpkin_pie_bat`, Epic). *"Hangs upside down. Never drops a crumb."* (Halloween limited edition.) A round bat whose body is a whole pumpkin pie standing on its edge: orange filling face (`#E07A2E`), a crimped golden crust ring (`#D9A15B`) around it and a whipped-cream swirl (`#FFF8EE`) on top. Wide dark purple bat wings (`#3B2A4A` with `#5A3F6E` membranes), pointy ears, big eyes, a fangy smile, tiny feet.
