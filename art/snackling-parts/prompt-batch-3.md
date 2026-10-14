# Steal a Snackling: 3D model batch 3 of 3 (Legendaries, Mythics & Secrets)

You're designing 3D models for my Roblox game **Steal a Snackling**. Snacklings are collectible food-animal hybrids (a Pizza Pup is a puppy made of pizza). Players buy them off a conveyor belt and show them off on podiums in their bases, where they earn cash, and other players try to steal them. Every Snackling already exists in the game as a simple model built from basic shapes. This is the polished redesign.

Build **batch 3 of 3, 23 Snacklings**, as one design: a gallery page that previews every model in real 3D, with the exact parts data I'll import into the game embedded in it.

## Art direction

- Premium, toy-like Roblox pet style: chunky, soft and rounded, big heads, bright candy colours, a glossy finish. Original designs only: no existing characters, brands, logos or text anywhere.
- Each one must read instantly from across a base. The food is unmistakable (crust, fillings, glaze, sprinkles), and so is the animal (ears, snout, tail, horns). Keep the food, the animal and the main colours from its brief so players still recognise their Snackling. Put the effort into shape, proportion, detail and charm.
- Faces: big glossy eyes (a white Eye, a dark Pupil `#1E1A24`, one or two small white Highlights), a small mouth, and blush Cheeks where they suit. The face points toward -Z and must be clearly visible from the front and from above the front, because players look down at podiums.
- Shade with colour, because Roblox lighting is simple: give big shapes a slightly darker underside piece or rim and a lighter top where it helps.
- Pose: a calm standing or sitting idle pose, stable on a flat podium. The game adds its own bounce, so avoid extreme poses.
- Ambition by rarity: Legendaries feel grand and special (about 40-52 parts). Mythics are majestic, with a little Neon glow (about 44-56 parts). Secrets are the rarest Snacklings in the game: the most elaborate, iconic designs, with a few glowing accents (about 48-56 parts).

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
5. **Budget.** At most **56 parts** per Snackling, counting everything. Spend the budget on polish, not filler. No dimension of any part is smaller than 0.03 u.
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
{"format": "snackling-parts-1", "batch": 3, "creatures": [{"id": "...", "parts": [PART, PART, ...]}, ...]}
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

## Batch 3: Legendaries, Mythics & Secrets, at most 56 parts each

1. **Donut Dragon** (`donut_dragon`, Legendary). *"Breathes powdered sugar."* A baby dragon on two feet whose torso is a glazed donut standing upright (`#E9B26B` dough, thick pink icing `#FF77B7` with rainbow sprinkles, the hole visible). Purple dragon head (`#A68BFF`) with a lilac snout (`#C9B8FF`), cream horn nubs (`#FFE6A8`) and a fangy smile, lilac wings (`#C2ADFF` membranes on `#8E5CFF` bones), a long tail with pink spikes (`#FF77B7`) down its back, purple arms and feet. Signature: a small puff of powdered-sugar breath.
2. **Onigiri Orca** (`onigiri_orca`, Legendary). *"Rice to meet you."* A chubby orca whose body is a triangular onigiri rice ball (`#FBF7EF`, Sand) wrapped in a nori sheet (`#22302A`) over its lower half like an orca's dark side, with white eye patches, a dark dorsal fin, side fins and tail fluke (`#22302A`), sesame seeds and a red pickled plum (`#E8335A`) on top. It rests on its belly.
3. **Taffy Toucan** (`taffy_toucan`, Legendary). *"Stretches every story."* A toucan standing on two feet: glossy dark body and head (`#2A2A35`) with a bright yellow chest (`#FFE45F`) and blue eye patches (`#5FA8FF`). A huge banana-curved beak of stretchy taffy in orange (`#FF8A2E`) with a red tip (`#FF4B4B`) and a twisted candy stripe. Wings tipped pink (`#FF5FA2`), a candy-wrapper bow (white and pink) on its head, a fanned tail, blue feet.
4. **Pancake Panda** (`pancake_panda`, Legendary). *"A tall stack of chill."* A panda sitting upright whose body is a tall stack of four fluffy pancakes (`#F4C27A` with golden edges `#E8A85A`) with maple syrup (`#A0581E`) dripping down. White panda head with black ears, black eye patches (`#2A2A30`), a white muzzle with a black nose, a butter pat on its head, black arms and feet. Relaxed, sleepy-happy expression.
5. **Cotton Candy Koala** (`cotton_candy_koala`, Legendary). *"Melts hearts. And in the rain."* A koala made of fluffy cotton candy (Fabric): a lumpy body of pink (`#FFB3D9`) and baby-blue (`#A8D8FF`) puffs, a head of pink and blue puffs (`#FFC8E4` / `#BFE3FF`), big fluffy round ears (blue with pink inner), a large dark oval nose (`#4A4A5A`) and a sweet smile. It hugs a white paper cone stick like a tree trunk.
6. **Pavlova Peacock** (`pavlova_peacock`, Legendary). *"Struts in meringue. Shows off its fruit."* A peacock on two feet whose body is a crisp white meringue pavlova (`#FFF8F0` with soft peaks `#FFFDF8`) topped with kiwi slices (`#7BC043`), strawberries (`#E8335A`) and blueberries (`#5A4AE0`). Elegant blue head and neck (`#2F8FD8`), a teal crest (`#2FB59C`), a small cream beak, grey legs. A huge fanned tail behind it of teal feathers with fruit 'eye' spots (strawberry red, kiwi green).
7. **Milkshake Mammoth** (`milkshake_mammoth`, Legendary). *"Brain-freeze big."* A big, heavy woolly mammoth on four chunky legs whose body is a strawberry milkshake: pink shake body (`#FF9FC0`) with whipped cream (`#FFFDF6`) swirled on its back, rainbow sprinkles and a cherry on top, and a pink and white striped straw (`#FF5F8F` / `#FFFFFF`) poking out of the cream. Pink head (`#FFB0CC`) with a long curling trunk, floppy ears (`#FF8FB4`) and curved cream tusks (`#FFE8B8`).
8. **Churro Cheetah** (`churro_cheetah`, Legendary). *"Cinnamon-fast. Sugar-spotted."* A sleek cheetah on four long legs, leaning forward as if about to sprint. Its body is a long ridged churro (`#D98E3F` with darker `#B8702E` ridges running lengthwise) coated in cinnamon sugar (Sand) with dark spots (`#6B3A12`). Orange head (`#E8A04A`) with round ears, cream muzzle, dark tear marks and whiskers, a long thin tail with dark rings.
9. **Caramel Apple Ghoul** (`caramel_apple_ghoul`, Legendary). *"Sticky fingers. Stickier grin."* (Halloween limited edition.) A friendly ghoul whose head is a shiny red candy apple (`#E23B4A`) dipped in caramel (`#C7792E`) with drips and crushed peanuts (`#F5D9A4`), a wooden stick (`#E8D2A8`) poking out of the top. Its ghostly sheet body (`#F2F0FF` / `#EDE8FF`) flows down beneath in wavy tendrils that touch the ground. Big eyes with green pupils (`#2E8A4A`), mischievous brows (`#5A1A2A`), a wide grin.
10. **Lasagna Lion** (`lasagna_lion`, Mythic). *"King of the layers."* A majestic lion on four legs whose body is a block of lasagna: alternating pasta (`#F5C45A`), red sauce (`#D63A2A`) and white béchamel (`#FFF2C0`) layers on the sides, with melted cheese dripping from the top. A big wavy mane of rippled lasagna sheets (`#F5C45A` with saucy `#D63A2A` edges) around a golden head with a cream muzzle, brows (`#B8571E`) and a basil leaf (`#3FA34D`) on top. A tail with a saucy tuft. Mythic: a subtle golden Neon crown of light.
11. **Souffle Sphinx** (`souffle_sphinx`, Mythic). *"Asks riddles. Never falls flat."* A sphinx sitting upright like an ancient statue: its body is a tall golden soufflé (`#F2C45A`) rising out of a white fluted ramekin (`#FFFFFF`). Golden cat head with a blue and gold striped royal headdress (`#3A6FD8` / `#FFD23F`) draping down both sides, a gold band across the forehead, sleepy wise eyes with dark brows, a cat mouth, whiskers and a dusting of powdered sugar. Mythic: faint Neon gold accents on the headdress.
12. **Gingerbread Golem** (`gingerbread_golem`, Mythic). *"Baked from a recipe older than time."* A big, blocky gingerbread golem standing upright with a heavy stance and wide feet: chunky square torso, head and limbs (`#B9733A` / `#C27E42`) outlined in white icing (`#FFFFFF`), with zigzags on the arms. Three gumdrop buttons (`#E8433A`, `#5BBF3A`, `#FFD23F`) down the chest, dot eyes, a white icing smile and brows, icing dripping off the head. Mythic: a few glowing icing runes (Neon).
13. **Parfait Pegasus** (`parfait_pegasus`, Mythic). *"Layered, lofty and always in a glass."* A winged horse on four legs whose body is a layered parfait: cream (`#FFF6E8`) with red berry (`#E8335A`) and purple (`#5A4AE0`) bands, whipped cream on its back with berries and a mint leaf. Cream head with a pink muzzle (`#FFE4EC`) and pointy ears, a flowing pink-to-lavender mane (`#FF8FB8` / `#B57BFF`), big white feathered wings with pink tips (`#FFD1E8`), a fluffy pastel tail. Mythic: faint Neon sparkle on the wing tips.
14. **Hotpot Hydra** (`hotpot_hydra`, Mythic). *"Three heads, one simmering mood."* A three-headed hydra sitting in a bubbling hotpot: a big clay pot body (`#B8572E`) holding a split broth (red `#E8433A` on one side, golden `#FFD23F` on the other) with tofu, greens, mushrooms and chilli around the rim. Three green dragon necks (`#5BBF7A`) rise out of the pot, each with a small head, cream horn nubs (`#FFE6A8`) and a fangy smile; the middle head is the tallest. A tail curls out of the back, and soft steam puffs rise (white, Glass, slightly transparent).
15. **Flambe Phoenix** (`flambe_phoenix`, Mythic). *"Rises from the dessert cart in a whoosh."* A phoenix standing upright made of a flambéed dessert: an orange body (`#FF9A3C`) with a yellow belly (`#FFE05A`), an orange head (`#FFB347`), a golden beak (`#FFD23F`) and fierce brows (`#C2410C`). Huge spread wings of flame-shaped feathers (`#FF5A1F` to `#FFB33C`), a crest of flames on its head and a fanned flame tail, with Neon orange and yellow flame tips and a dusting of powdered sugar.
16. **Dumpling Dino** (`dumpling_dino`, Mythic). *"Steamed. Ancient. Adorable."* A chubby dinosaur standing upright made of a steamed dumpling: soft pale dough skin (`#F5F0E1`, matte) with the pleated dumpling fold running down its back as its spikes (green `#6FCF97` accents along the pleats), a creamy belly (`#FFFDF4`), small arms, a long tail, its tongue out and green herb flecks (`#6FCF97`) on its head. Mythic: a soft Neon jade glow along the pleats.
17. **Jack-o'-Lantern Latte** (`jack_o_lantern_latte`, Mythic). *"Extra foam, extra boo."* (Halloween limited edition.) A pumpkin-spice latte cup creature: a tall orange cup (`#F28C28`) with a handle on one side, a swirl of whipped foam (`#FFF4DC`) on top with cinnamon crumbs (`#8A4A1E`) and a little green stem and leaf (`#5BBF3A`), foam dripping down. A jack-o'-lantern face on the cup: triangle eyes (`#4A2210` pupils) and a jagged grin, with a Neon orange glow inside the eyes and mouth. Stubby legs (`#C8601A`).
18. **Gelato Griffin** (`gelato_griffin`, Secret). *"Never melts. Never forgets."* A regal griffin on four legs (eagle at the front, lion at the back). Its body is lumpy gelato scoops in mint-blue (`#9BE7FF`) and pink (`#FFB3D1`), Ice material, with wafer sticks (`#E8B86A`) poking out. Cream eagle head (`#FFF4D6`) with a caramel-gold beak (`#D99A4E`), a crest of pink and blue gelato curls, big white wings tipped pink (`#FFD1F0`), a lion tail with a pink tuft, rainbow sprinkles and a cherry on its head. Secret: a few frosty Neon sparkles.
19. **Matcha Manta** (`matcha_manta`, Secret). *"Glides through a sea of calm."* A serene manta ray hovering just above the ground: a wide, flat matcha-green body and wing fins (`#8FBF5A` with lighter `#A8D27A` powder), a cream latte-art swirl (`#FFFFFF`) on its back, red bean (`#7A2A2A`) and white mochi balls on top, small horn-like head fins (`#7AAE48`) at the front, a long thin tail (`#6E9E3E`), a calm smile. It rests on its wing tips and belly at y = 0. Secret: soft Neon jade lines along the wing edges.
20. **Fortune Cookie Kitsune** (`fortune_cookie_kitsune`, Secret). *"Already knew you'd steal it."* A fox spirit on four legs made of fortune cookie: a golden cookie body (`#F2C45A`) with the folded crescent fortune-cookie shape forming its back and a blank paper slip (`#FFFFFF` with red `#E8433A` edge lines, no text) sticking out. Head (`#F5CF6A`) with tall pointy ears tipped red, a cream muzzle, red brow markings and a knowing smile. Three to five fluffy tails fanned out behind with white tips, a red and gold bow (`#E8433A` / `#FFD23F`) at the neck. Secret: a few Neon gold flecks on the tails.
21. **Bonbon Behemoth** (`bonbon_behemoth`, Secret). *"A colossal box of surprises."* A huge, heavy beast on four legs made of luxury chocolate bonbons: a rich dark chocolate body (`#4A2A16`) with a white-chocolate zigzag drizzle (`#FFF4E0`) and gold-foil discs (`#FFD23F`, Foil). Brown head (`#5A3420`) with a light snout (`#8A5A3A`), big curved golden horns (`#FFD23F` / `#FFE88A`, Foil), cream tusks (`#FFF4E0`), round ears, a crown of truffles (`#B8783A`) on its head and a grin under heavy brows. Secret: a few Neon gold glints.
22. **Wedding Cake Wyvern** (`wedding_cake_wyvern`, Secret). *"Three tiers, two wings, zero chill."* An elegant wyvern standing upright whose body is a three-tier white wedding cake (`#FFFFFF` tiers with pink `#FFD1E8` piping and pearl beads, icing drips). Its lavender head (`#E6DCFF`) sits on top with curved golden horns (`#FFD23F` / `#FFE88A`) and a tiny pink rose topper. White dragon wings with pink membranes, a long lavender tail with pink spikes, small lavender arms and feet (`#D8C8FF`). Secret: soft Neon pink sparkle on the pearls.
23. **Croissant Kraken** (`croissant_kraken`, Secret). *"Flaky on the outside. Legendary on the inside."* A kraken whose dome head is a big glossy croissant (`#E0A84E` with darker `#C98A3C` baked bands curving around it like croissant layers) with a butter pat on top, big eyes, brows (`#8A5A2A`) and an 'o' mouth on the front. Eight curling tentacles (`#E8B45A`) of flaky pastry segments spread across the ground, some tips curling up, with flaky crumbs (`#F5D08A`). Secret: a few warm Neon highlights on the tentacle tips.
