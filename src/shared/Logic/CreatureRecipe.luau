--!strict
--[[
	Snackling models as data: turns a recipe from Config/CreatureLooks into a list of plain part descriptions (shape,
	size, CFrame numbers, colour, material). Pure: no Roblox APIs, so CI checks every recipe (known kinds, part budget,
	a face on the front, nothing below the feet) and CreatureVisuals only turns the list into Parts.

	Model space: studs, origin at the feet, +Y up, the face looks at -Z (podiums and the belt turn -Z to the aisle).
	A part's `cf` holds the 12 numbers of CFrame.new(x, y, z, R00, R01, R02, R10, R11, R12, R20, R21, R22).

	A recipe is a body PLAN (where body, head, legs and face go) + a food SKIN for the body and the head + a FACE +
	FEATURES (which animal it is: ears, tail, wings, snout...) + TOPPINGS (which snack it is: sprinkles, drips, a
	cherry...). Sizes are in units of the recipe's `size` (studs), so a rarity's modelScale scales the whole recipe.
	Faces, features and toppings are placed by casting rays at the skin's real shapes, so they sit on the surface
	whatever the skin.

	Plans     blob       one body with the face on it (optional little feet / arms)
	          biped      torso + head on top, feet, arms (unless arms = false); `legs` adds legs, `neck` a neck
	          quadruped  long body on four legs (`legs` = length), head in front, tail anchor at the back
	          swimmer    long body resting on two side fins, face on the body
	          tentacled  a dome on `tentacles` tentacles (default 6), face on the dome
	Skins     round (ellipsoid)            lumpy (n lumps in color2: popcorn, puffs, nuggets, cotton candy)
	          slice (pizza / chip wedge; color2 = dough layer, color3 = crust; style "chip": no crust)
	          roll (lying cylinder: sushi, sausage; color2/color3 = filling rings on the ends; style "rounded")
	          can (standing cylinder; color2 = top disc; style "dome": a domed top)
	          stack (n discs cycling color/color2/color3: pancakes)   macaron (two shells + color2 filling)
	          cup (color2 liner + color dome: muffin, cupcake)        flan (color body, color2 caramel top)
	          ring (donut; color2 icing, color3 hole; style "flat" lies down)
	          block (style "plain" + color2 top slab, "toast" color2 crust, "layers" n slabs, "grid" waffle bars)
	          bun (burger: color bun, color2 patty, color3 cheese)    cone (color scoop on a color2 waffle cone)
	          pear (two stacked ellipsoids: onigiri, penguin)          bowl (color bowl, color2 broth, color3 rim)
	Face      eyes round | big | dot | happy | sleepy | stalk;  mouth smile | open | tongue | fang | o | cat | grin |
	          none;  optional cheeks, brows, nose colours; spacing / height / scale move the eyes
	Features  ears (round | pointy | floppy | long | mouse), horns (nub | curved | antlers | unicorn | tusk),
	          antennae, tail (stub | puff | curly | thin | fluffy | long | flat | fluke | fin | lion | ringed),
	          wings (tiny | feather | bat | dragon | moth | angel | manta), shell (dome | spiral | taco),
	          mane, snout (dog | pig | cat | beak | bill | toucan | trunk), whiskers, spikes, fins (all | side |
	          dorsal), tusks, claws, legs (crab legs), belly, mask, spots, stripes (rings | bands | back), fan
	          (peacock tail), crest, heads (extra heads on necks), straw, bubble, flame, bow, teeth
	Toppings  sprinkles, seeds, chips, discs, drips, cap, swirl, cherry, leaf, band, sticks, strands, balls, crumbs,
	          egg, swirlmark, zigzag, bits (style "rim" | "ridge"), spikes
]]

local Types = require("../Types")

type CreatureLook = Types.CreatureLook
type LookVolume = Types.LookVolume
type LookFace = Types.LookFace
type LookFeature = Types.LookFeature
type LookTopping = Types.LookTopping

export type PartShape = "Ball" | "Block" | "Cylinder" | "Wedge" | "Ellipsoid"
-- body: shape of the creature (mutations restyle it, big ones cast shadows); face: eyes, mouth, cheeks (mutations
-- never restyle them, so a face always reads); detail: small bits (no shadow).
export type PartRole = "body" | "face" | "detail"

export type PartSpec = {
	name: string,
	shape: PartShape,
	size: { number }, -- studs: x, y, z (a Ball uses x; a Cylinder runs along x)
	cf: { number }, -- CFrame.new's 12 numbers
	color: string,
	material: string?, -- Enum.Material name, nil = SmoothPlastic
	role: PartRole,
	squashAxis: number?, -- 1..3: the part's local axis that points up, on the parts the idle animation squashes
	transparency: number?,
	shadow: boolean?, -- casts a shadow (the biggest shapes only)
}

export type Compiled = {
	parts: { PartSpec },
	minY: number, -- lowest point of any part (0: it stands exactly on its feet; never below)
	maxY: number, -- height of the highest point, studs
	width: number, -- side to side (x), studs
	footprint: number, -- widest horizontal extent (x or z), studs
	base: number, -- the body's widest horizontal size (the Root and the aura ring are this wide)
}

local CreatureRecipe = {}

-- Part budget per rarity order (Root and the Mythic+ aura ring included): CI keeps every recipe under it.
CreatureRecipe.BUDGETS = { 30, 30, 40, 40, 50, 50, 50 }

function CreatureRecipe.budgetFor(rarityOrder: number): number
	return CreatureRecipe.BUDGETS[math.clamp(rarityOrder, 1, #CreatureRecipe.BUDGETS)]
end

local HEX_PATTERN = "^#%x%x%x%x%x%x$"

local SCLERA = "#FFFFFF"
local PUPIL = "#1E1A24"
local MOUTH = "#4A2228"
local TONGUE = "#FF7A8C"
local TEETH = "#FFFFFF"
local NOSE = "#3A2A2E"

-- Vector / matrix maths (3x3 rotation matrices, row-major) ---------------------------------------------------------

type V = { x: number, y: number, z: number }
type M = { number }

local function v3(x: number, y: number, z: number): V
	return { x = x, y = y, z = z }
end
local function vadd(a: V, b: V): V
	return v3(a.x + b.x, a.y + b.y, a.z + b.z)
end
local function vsub(a: V, b: V): V
	return v3(a.x - b.x, a.y - b.y, a.z - b.z)
end
local function vmul(a: V, k: number): V
	return v3(a.x * k, a.y * k, a.z * k)
end
local function vdot(a: V, b: V): number
	return a.x * b.x + a.y * b.y + a.z * b.z
end
local function vcross(a: V, b: V): V
	return v3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
end
local function vlen(a: V): number
	return math.sqrt(vdot(a, a))
end
local function vnorm(a: V): V
	local l = vlen(a)
	if l < 1e-9 then
		return v3(0, 1, 0)
	end
	return vmul(a, 1 / l)
end
-- a + (b - a) * t
-- m * v
local function mv(m: M, a: V): V
	return v3(
		m[1] * a.x + m[2] * a.y + m[3] * a.z,
		m[4] * a.x + m[5] * a.y + m[6] * a.z,
		m[7] * a.x + m[8] * a.y + m[9] * a.z
	)
end

local function vlerp(a: V, b: V, t: number): V
	return v3(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t)
end

local IDENT: M = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }

local function mmul(a: M, b: M): M
	return {
		a[1] * b[1] + a[2] * b[4] + a[3] * b[7],
		a[1] * b[2] + a[2] * b[5] + a[3] * b[8],
		a[1] * b[3] + a[2] * b[6] + a[3] * b[9],
		a[4] * b[1] + a[5] * b[4] + a[6] * b[7],
		a[4] * b[2] + a[5] * b[5] + a[6] * b[8],
		a[4] * b[3] + a[5] * b[6] + a[6] * b[9],
		a[7] * b[1] + a[8] * b[4] + a[9] * b[7],
		a[7] * b[2] + a[8] * b[5] + a[9] * b[8],
		a[7] * b[3] + a[8] * b[6] + a[9] * b[9],
	}
end

-- Same conventions as Roblox's CFrame.Angles: rx(a) * ry(b) * rz(c).
local function rx(t: number): M
	local c, s = math.cos(t), math.sin(t)
	return { 1, 0, 0, 0, c, -s, 0, s, c }
end
local function ry(t: number): M
	local c, s = math.cos(t), math.sin(t)
	return { c, 0, s, 0, 1, 0, -s, 0, c }
end
local function rz(t: number): M
	local c, s = math.cos(t), math.sin(t)
	return { c, -s, 0, s, c, 0, 0, 0, 1 }
end

local function fromColumns(x: V, y: V, z: V): M
	return { x.x, y.x, z.x, x.y, y.y, z.y, x.z, y.z, z.z }
end

-- A rotation whose local Y axis points along `dir` (ellipsoids standing on a surface, segments).
local function aimY(dir: V): M
	local y = vnorm(dir)
	local ref = if math.abs(y.z) > 0.95 then v3(1, 0, 0) else v3(0, 0, 1)
	local z = vnorm(vsub(ref, vmul(y, vdot(ref, y))))
	return fromColumns(vcross(y, z), y, z)
end

-- A rotation whose local X axis points along `dir` (cylinders run along X).
local function aimX(dir: V): M
	local x = vnorm(dir)
	local ref = if math.abs(x.y) > 0.95 then v3(0, 0, 1) else v3(0, 1, 0)
	local y = vnorm(vsub(ref, vmul(x, vdot(ref, x))))
	return fromColumns(x, y, vcross(x, y))
end

-- A rotation whose local Z axis points along `dir` (flat discs facing outwards, elongated shapes).
local function aimZ(dir: V): M
	local z = vnorm(dir)
	local ref = if math.abs(z.y) > 0.95 then v3(0, 0, 1) else v3(0, 1, 0)
	local y = vnorm(vsub(ref, vmul(z, vdot(ref, z))))
	return fromColumns(vcross(y, z), y, z)
end

-- A rotation with local Y along `y` and local Z as close as possible to `z` (a drip lying flat on a surface).
local function frameYZ(y: V, z: V): M
	local yy = vnorm(y)
	local zz = vsub(z, vmul(yy, vdot(z, yy)))
	if vlen(zz) < 1e-6 then
		return aimY(yy)
	end
	zz = vnorm(zz)
	return fromColumns(vcross(yy, zz), yy, zz)
end

local VERTICAL = rz(math.pi / 2) -- a Cylinder standing up (its X axis along world Y)
local ALONG_Z = ry(math.pi / 2) -- a Cylinder lying front to back

-- Deterministic "random" in [0, 1).
local function hash(i: number, k: number): number
	local x = math.sin(i * 12.9898 + k * 78.233) * 43758.5453
	return x - math.floor(x)
end

-- Solids and rays: the shapes faces / features / toppings attach to ----------------------------------------------

type Solid = {
	kind: string, -- "ellipsoid" | "box" | "cyl" | "prism"
	cx: number,
	cy: number,
	cz: number,
	rx: number, -- half extents
	ry: number,
	rz: number,
	axis: number?, -- cyl: 1 = X, 2 = Y, 3 = Z
	tip: number?, -- prism: -1 = the triangle's tip at the front (-Z), 1 = at the back
}

export type Hull = {
	cx: number,
	cy: number,
	cz: number,
	a: number, -- half width / height / depth of the shape's box
	b: number,
	c: number,
	color: string,
	solids: { Solid },
}

local function comp(v: V, axis: number): number
	return if axis == 1 then v.x elseif axis == 2 then v.y else v.z
end

local function axisVector(axis: number, sign: number): V
	return if axis == 1 then v3(sign, 0, 0) elseif axis == 2 then v3(0, sign, 0) else v3(0, 0, sign)
end

-- Entry and exit distances of a ray through a solid, with the surface normals there; nil when it misses.
local function raySolid(s: Solid, o: V, d: V): (number?, number?, V?, V?)
	if s.kind == "ellipsoid" then
		local ox, oy, oz = (o.x - s.cx) / s.rx, (o.y - s.cy) / s.ry, (o.z - s.cz) / s.rz
		local dx, dy, dz = d.x / s.rx, d.y / s.ry, d.z / s.rz
		local a = dx * dx + dy * dy + dz * dz
		local b = 2 * (ox * dx + oy * dy + oz * dz)
		local c = ox * ox + oy * oy + oz * oz - 1
		local disc = b * b - 4 * a * c
		if disc < 0 or a < 1e-12 then
			return nil, nil, nil, nil
		end
		local root = math.sqrt(disc)
		local t0, t1 = (-b - root) / (2 * a), (-b + root) / (2 * a)
		local function normalAt(t: number): V
			local p = vadd(o, vmul(d, t))
			return vnorm(v3((p.x - s.cx) / (s.rx * s.rx), (p.y - s.cy) / (s.ry * s.ry), (p.z - s.cz) / (s.rz * s.rz)))
		end
		return t0, t1, normalAt(t0), normalAt(t1)
	end

	local t0, t1 = -math.huge, math.huge
	local n0, n1 = v3(0, 0, -1), v3(0, 0, 1)
	local function slab(axis: number, lo: number, hi: number): boolean
		local oi, di = comp(o, axis), comp(d, axis)
		if math.abs(di) < 1e-12 then
			return oi >= lo and oi <= hi
		end
		local ta, tb = (lo - oi) / di, (hi - oi) / di
		local sign = -1
		if ta > tb then
			ta, tb = tb, ta
			sign = 1
		end
		if ta > t0 then
			t0 = ta
			n0 = axisVector(axis, sign)
		end
		if tb < t1 then
			t1 = tb
			n1 = axisVector(axis, -sign)
		end
		return true
	end
	local center = v3(s.cx, s.cy, s.cz)
	local half = v3(s.rx, s.ry, s.rz)

	if s.kind == "box" then
		for axis = 1, 3 do
			if not slab(axis, comp(center, axis) - comp(half, axis), comp(center, axis) + comp(half, axis)) then
				return nil, nil, nil, nil
			end
		end
	elseif s.kind == "cyl" then
		local axis = s.axis or 2
		if not slab(axis, comp(center, axis) - comp(half, axis), comp(center, axis) + comp(half, axis)) then
			return nil, nil, nil, nil
		end
		local p, q = if axis == 1 then 2 else 1, if axis == 3 then 2 else 3
		local rp, rq = comp(half, p), comp(half, q)
		local op, oq = (comp(o, p) - comp(center, p)) / rp, (comp(o, q) - comp(center, q)) / rq
		local dp, dq = comp(d, p) / rp, comp(d, q) / rq
		local a = dp * dp + dq * dq
		if a < 1e-12 then
			if op * op + oq * oq > 1 then
				return nil, nil, nil, nil
			end
		else
			local b = 2 * (op * dp + oq * dq)
			local c = op * op + oq * oq - 1
			local disc = b * b - 4 * a * c
			if disc < 0 then
				return nil, nil, nil, nil
			end
			local root = math.sqrt(disc)
			local ta, tb = (-b - root) / (2 * a), (-b + root) / (2 * a)
			local function sideNormal(t: number): V
				local pt = vadd(o, vmul(d, t))
				local n = { 0, 0, 0 }
				n[p] = (comp(pt, p) - comp(center, p)) / (rp * rp)
				n[q] = (comp(pt, q) - comp(center, q)) / (rq * rq)
				return vnorm(v3(n[1], n[2], n[3]))
			end
			if ta > t0 then
				t0 = ta
				n0 = sideNormal(ta)
			end
			if tb < t1 then
				t1 = tb
				n1 = sideNormal(tb)
			end
		end
	else -- prism: a triangle in the XZ plane (tip at z = cz + tip * rz, base edge at the other end), extruded in Y
		if not slab(2, s.cy - s.ry, s.cy + s.ry) then
			return nil, nil, nil, nil
		end
		local tip = s.tip or -1
		local tipZ, baseZ = s.cz + tip * s.rz, s.cz - tip * s.rz
		local planes: { { n: V, at: V } } = {
			{ n = v3(0, 0, -tip), at = v3(s.cx, s.cy, baseZ) },
			{ n = vnorm(v3(2 * s.rz, 0, tip * s.rx)), at = v3(s.cx, s.cy, tipZ) },
			{ n = vnorm(v3(-2 * s.rz, 0, tip * s.rx)), at = v3(s.cx, s.cy, tipZ) },
		}
		for _, plane in planes do
			local denom = vdot(plane.n, d)
			local dist = vdot(plane.n, vsub(o, plane.at))
			if math.abs(denom) < 1e-12 then
				if dist > 0 then
					return nil, nil, nil, nil
				end
			else
				local t = -dist / denom
				if denom < 0 then
					if t > t0 then
						t0 = t
						n0 = plane.n
					end
				elseif t < t1 then
					t1 = t
					n1 = plane.n
				end
			end
		end
	end
	if t0 > t1 then
		return nil, nil, nil, nil
	end
	return t0, t1, n0, n1
end

-- The first surface a ray from far away hits (outside-in): front (+Z ray) or top (-Y ray).
local function firstHit(hull: Hull, o: V, d: V): (V?, V?)
	local bestT, bestN = math.huge, nil :: V?
	for _, s in hull.solids do
		local t0, t1, n0 = raySolid(s, o, d)
		if t0 and t1 and n0 and t1 > 0 and t0 < bestT then
			bestT, bestN = t0, n0
		end
	end
	if bestN == nil then
		return nil, nil
	end
	return vadd(o, vmul(d, bestT)), bestN
end

-- Point on the front of a hull at offsets (x, y) from its centre (studs); falls back towards the centre.
local function frontAt(hull: Hull, x: number, y: number): (V, V)
	for attempt = 0, 6 do
		local k = 1 - attempt * 0.12
		local p, n = firstHit(hull, v3(hull.cx + x * k, hull.cy + y * k, hull.cz - 1000), v3(0, 0, 1))
		if p and n then
			return p, n
		end
	end
	return v3(hull.cx + x, hull.cy + y, hull.cz - hull.c), v3(0, 0, -1)
end

-- Point on the top of a hull at offsets (x, z) from its centre.
local function topAt(hull: Hull, x: number, z: number): (V, V)
	for attempt = 0, 6 do
		local k = 1 - attempt * 0.12
		local p, n = firstHit(hull, v3(hull.cx + x * k, hull.cy + 1000, hull.cz + z * k), v3(0, -1, 0))
		if p and n then
			return p, n
		end
	end
	return v3(hull.cx + x, hull.cy + hull.b, hull.cz + z), v3(0, 1, 0)
end

-- Where a ray from the hull's centre along `dir` leaves the shape (inside-out).
-- Where a ray from `o` (inside the shape) along `dir` leaves it.
local function surfaceFrom(hull: Hull, o: V, dir: V): (V, V)
	local d = vnorm(dir)
	type Span = { t0: number, t1: number, n1: V }
	local spans: { Span } = {}
	for _, s in hull.solids do
		local t0, t1, _, n1 = raySolid(s, o, d)
		if t0 and t1 and n1 and t1 > 0 then
			table.insert(spans, { t0 = t0, t1 = t1, n1 = n1 })
		end
	end
	table.sort(spans, function(a: Span, b: Span): boolean
		return a.t0 < b.t0
	end)
	local reach, normal = 0, nil :: V?
	for _, span in spans do
		if span.t0 <= reach + 1e-6 and span.t1 > reach then
			reach, normal = span.t1, span.n1
		end
	end
	if normal == nil then
		-- the centre is outside every solid: use the bounding ellipsoid
		local k = 1 / math.sqrt((d.x / hull.a) ^ 2 + (d.y / hull.b) ^ 2 + (d.z / hull.c) ^ 2)
		local p = vmul(d, k)
		return vadd(o, p), vnorm(v3(p.x / hull.a ^ 2, p.y / hull.b ^ 2, p.z / hull.c ^ 2))
	end
	return vadd(o, vmul(d, reach)), normal :: V
end

-- Where a ray from the hull's centre along `dir` leaves the shape.
local function surfaceAt(hull: Hull, dir: V): (V, V)
	return surfaceFrom(hull, v3(hull.cx, hull.cy, hull.cz), dir)
end

-- The side of a hull at height y (studs, world), around the vertical axis at angle theta (0 = front, -Z).
local function sideAt(hull: Hull, theta: number, y: number): (V, V)
	local yy = math.clamp(y, hull.cy - hull.b * 0.95, hull.cy + hull.b * 0.95)
	return surfaceFrom(hull, v3(hull.cx, yy, hull.cz), v3(math.sin(theta), 0, -math.cos(theta)))
end

-- The direction straight down along a surface with normal n (straight down where the surface is flat on top).
local function downAlong(n: V): V
	local down = v3(0, -1, 0)
	local t = vsub(down, vmul(n, vdot(down, n)))
	if vlen(t) < 0.2 then
		return down
	end
	return vnorm(t)
end

-- Building parts ----------------------------------------------------------------------------------------------------

type Rig = {
	S: number, -- studs per unit
	body: Hull,
	head: Hull?,
	face: Hull, -- where the eyes go (the head, or the body for blob-like plans)
	hulls: { [string]: Hull },
	tail: V, -- tail anchor at the back of the body
	limb: string, -- limb colour
	muzzle: Hull?, -- set by the snout feature: the mouth goes on it
	mouth: V?, -- centre of the mouth once built
	mouthNormal: V?,
	summit: { [string]: V }, -- highest topping per hull (a cherry goes on top of a swirl)
}

type Ctx = { parts: { PartSpec } }

type Extra = { material: string?, squash: boolean?, transparency: number?, shadow: boolean? }

local MIN_SIZE = 0.05

local function emit(
	ctx: Ctx,
	name: string,
	shape: PartShape,
	size: V,
	pos: V,
	rot: M,
	color: string,
	role: PartRole,
	extra: Extra?
)
	local sx, sy, sz = math.max(size.x, MIN_SIZE), math.max(size.y, MIN_SIZE), math.max(size.z, MIN_SIZE)
	if shape == "Ball" then
		sy, sz = sx, sx
	end
	local spec: PartSpec = {
		name = name,
		shape = shape,
		size = { sx, sy, sz },
		cf = { pos.x, pos.y, pos.z, rot[1], rot[2], rot[3], rot[4], rot[5], rot[6], rot[7], rot[8], rot[9] },
		color = color,
		role = role,
	}
	if extra then
		spec.material = extra.material
		spec.transparency = extra.transparency
		spec.shadow = extra.shadow
		if extra.squash and (shape == "Ellipsoid" or shape == "Block") then
			-- the local axis most aligned with world up (row 2 of the matrix)
			local best, axis = 0, 0
			for i = 1, 3 do
				if math.abs(rot[3 + i]) > best then
					best, axis = math.abs(rot[3 + i]), i
				end
			end
			if best > 0.95 then
				spec.squashAxis = axis
			end
		end
	end
	table.insert(ctx.parts, spec)
end

local function ellipsoid(ctx: Ctx, name: string, size: V, pos: V, rot: M, color: string, role: PartRole, extra: Extra?)
	emit(ctx, name, "Ellipsoid", size, pos, rot, color, role, extra)
end

local function ball(ctx: Ctx, name: string, diameter: number, pos: V, color: string, role: PartRole, extra: Extra?)
	emit(ctx, name, "Ball", v3(diameter, diameter, diameter), pos, IDENT, color, role, extra)
end

local function box(ctx: Ctx, name: string, size: V, pos: V, rot: M, color: string, role: PartRole, extra: Extra?)
	emit(ctx, name, "Block", size, pos, rot, color, role, extra)
end

-- A cylinder `length` long along the rotation's local X axis.
local function cylinder(
	ctx: Ctx,
	name: string,
	length: number,
	diameter: number,
	pos: V,
	rot: M,
	color: string,
	role: PartRole,
	extra: Extra?
)
	emit(ctx, name, "Cylinder", v3(length, diameter, diameter), pos, rot, color, role, extra)
end

-- A rounded stroke between two points (a cylinder along the segment).
local function segment(
	ctx: Ctx,
	name: string,
	a: V,
	b: V,
	diameter: number,
	color: string,
	role: PartRole,
	extra: Extra?
)
	local delta = vsub(b, a)
	cylinder(ctx, name, vlen(delta), diameter, vlerp(a, b, 0.5), aimX(delta), color, role, extra)
end

local function wedge(ctx: Ctx, name: string, size: V, pos: V, rot: M, color: string, role: PartRole, extra: Extra?)
	emit(ctx, name, "Wedge", size, pos, rot, color, role, extra)
end

local function newHull(cx: number, cy: number, cz: number, w: number, h: number, d: number, color: string): Hull
	return { cx = cx, cy = cy, cz = cz, a = w / 2, b = h / 2, c = d / 2, color = color, solids = {} }
end

local function addSolid(hull: Hull, kind: string, center: V, half: V, axis: number?, tip: number?)
	table.insert(hull.solids, {
		kind = kind,
		cx = center.x,
		cy = center.y,
		cz = center.z,
		rx = half.x,
		ry = half.y,
		rz = half.z,
		axis = axis,
		tip = tip,
	})
end

-- Skins: the food shape of a body or a head -------------------------------------------------------------------------

type Box = { cx: number, cy: number, cz: number, w: number, h: number, d: number }
type SkinFn = (ctx: Ctx, box: Box, vol: LookVolume, primary: string, isFace: boolean) -> Hull

local SKINS: { [string]: SkinFn } = {}

local function boxCenter(b: Box): V
	return v3(b.cx, b.cy, b.cz)
end

-- A hair's breadth for this volume (keeps overlapping surfaces apart at any scale).
local function eps(b: Box): number
	return math.max(b.w, b.h, b.d) * 0.008
end

SKINS.round = function(ctx, b, vol, primary)
	local hull = newHull(b.cx, b.cy, b.cz, b.w, b.h, b.d, vol.color)
	ellipsoid(
		ctx,
		primary,
		v3(b.w, b.h, b.d),
		boxCenter(b),
		IDENT,
		vol.color,
		"body",
		{ material = vol.material, squash = true, shadow = true }
	)
	addSolid(hull, "ellipsoid", boxCenter(b), v3(b.w / 2, b.h / 2, b.d / 2))
	return hull
end

SKINS.lumpy = function(ctx, b, vol, primary, isFace)
	local hull = SKINS.round(ctx, b, vol, primary, isFace)
	local lumpColor = vol.color2 or vol.color
	local count = math.clamp(vol.n or 6, 1, 16)
	local candidates = count * 3
	local placed = 0
	for i = 0, candidates - 1 do
		if placed >= count then
			break
		end
		local y = 1 - 2 * (i + 0.5) / candidates
		local r = math.sqrt(1 - y * y)
		local theta = i * 2.39996
		local x, z = r * math.cos(theta), r * math.sin(theta)
		local onFront = z < -0.45 and math.abs(x) < 0.75 and y > -0.7 and y < 0.75
		if y > -0.35 and not (isFace and onFront) then
			placed += 1
			local p, n = surfaceAt(hull, v3(x * b.w, y * b.h, z * b.d))
			local k = 0.34 + 0.08 * hash(i, 3)
			local size = v3(b.w * k, b.h * k * 0.85, b.d * k)
			ellipsoid(
				ctx,
				"Shape",
				size,
				vsub(p, vmul(n, size.y * 0.3)),
				aimY(n),
				lumpColor,
				"body",
				{ material = vol.material }
			)
		end
	end
	return hull
end

SKINS.slice = function(ctx, b, vol, primary)
	local hull = newHull(b.cx, b.cy, b.cz, b.w, b.h, b.d, vol.color)
	local hw = b.w / 2
	-- styles: "pizza" (tip at the front, crust at the back), "chip" (no crust), "pizza-back" / "chip-back" (tip
	-- at the back)
	local style = vol.style or "pizza"
	local back = style == "pizza-back" or style == "chip-back"
	local flip = if back then -1 else 1
	local turn = if back then ry(math.pi) else IDENT
	local left: M = mmul(turn, { 0, -1, 0, 1, 0, 0, 0, 0, 1 })
	local right: M = mmul(turn, { 0, 1, 0, -1, 0, 0, 0, 0, 1 })
	local bottom = b.cy - b.h / 2
	local function layer(name: string, thickness: number, y: number, inset: number, zShift: number, color: string)
		local depth = b.d * inset
		local width = hw * inset
		for _, side in { -1, 1 } do
			wedge(
				ctx,
				if side < 0 then name else "Shape",
				v3(thickness, width, depth),
				v3(b.cx + side * flip * width / 2, y, b.cz + zShift * flip),
				if side < 0 then left else right,
				color,
				"body",
				{ material = vol.material, shadow = true }
			)
		end
	end
	local dough = vol.color2
	if dough then
		local t1, t2 = b.h * 0.56, b.h * 0.46
		layer(primary, t1, bottom + t1 / 2, 1, 0, dough)
		layer("Shape", t2, bottom + t1 + t2 / 2 - b.h * 0.02, 0.9, b.d * 0.02, vol.color)
	else
		layer(primary, b.h, b.cy, 1, 0, vol.color)
	end
	addSolid(hull, "prism", boxCenter(b), v3(hw, b.h / 2, b.d / 2), nil, -flip)
	if style == "pizza" or style == "pizza-back" then
		local crust = b.h * 1.35
		local crustZ = b.cz + flip * (b.d / 2 - crust * 0.3)
		cylinder(
			ctx,
			"Shape",
			b.w * 1.04,
			crust,
			v3(b.cx, bottom + crust / 2, crustZ),
			IDENT,
			vol.color3 or dough or vol.color,
			"body",
			{ material = vol.material, shadow = true }
		)
		addSolid(hull, "cyl", v3(b.cx, bottom + crust / 2, crustZ), v3(b.w * 0.52, crust / 2, crust / 2), 1)
	end
	return hull
end

SKINS.roll = function(ctx, b, vol, primary)
	local hull = newHull(b.cx, b.cy, b.cz, b.w, b.h, b.d, vol.color)
	local dia = math.min(b.w, b.h)
	local rounded = vol.style == "rounded"
	local length = if rounded then math.max(b.d - dia, MIN_SIZE) else b.d
	cylinder(
		ctx,
		primary,
		length,
		dia,
		boxCenter(b),
		ALONG_Z,
		vol.color,
		"body",
		{ material = vol.material, shadow = true }
	)
	addSolid(hull, "cyl", boxCenter(b), v3(dia / 2, dia / 2, length / 2), 3)
	if rounded then
		for _, side in { -1, 1 } do
			local at = v3(b.cx, b.cy, b.cz + side * length / 2)
			ball(ctx, "Shape", dia, at, vol.color, "body", { material = vol.material })
			addSolid(hull, "ellipsoid", at, v3(dia / 2, dia / 2, dia / 2))
		end
	elseif vol.color2 then
		-- filling rings on both ends (one disc running through shows on both faces)
		cylinder(ctx, "Shape", b.d + eps(b) * 2, dia * 0.8, boxCenter(b), ALONG_Z, vol.color2, "detail")
		if vol.color3 then
			cylinder(ctx, "Shape", b.d + eps(b) * 4, dia * 0.38, boxCenter(b), ALONG_Z, vol.color3, "detail")
		end
		addSolid(hull, "cyl", boxCenter(b), v3(dia * 0.4, dia * 0.4, b.d / 2 + eps(b)), 3)
	end
	return hull
end

SKINS.can = function(ctx, b, vol, primary)
	local hull = newHull(b.cx, b.cy, b.cz, b.w, b.h, b.d, vol.color)
	local dia = math.min(b.w, b.d)
	local domed = vol.style == "dome"
	local height = if domed then b.h * 0.78 else b.h
	local center = v3(b.cx, b.cy - b.h / 2 + height / 2, b.cz)
	cylinder(ctx, primary, height, dia, center, VERTICAL, vol.color, "body", { material = vol.material, shadow = true })
	addSolid(hull, "cyl", center, v3(dia / 2, height / 2, dia / 2), 2)
	local top = b.cy - b.h / 2 + height
	if domed then
		local dome = v3(b.cx, top, b.cz)
		local size = v3(dia, b.h * 0.44, dia)
		ellipsoid(ctx, "Shape", size, dome, IDENT, vol.color2 or vol.color, "body", { material = vol.material })
		addSolid(hull, "ellipsoid", dome, vmul(size, 0.5))
	elseif vol.color2 then
		local disc = v3(b.cx, top + eps(b), b.cz)
		cylinder(ctx, "Shape", eps(b) * 6, dia * 0.86, disc, VERTICAL, vol.color2, "detail")
	end
	return hull
end

SKINS.stack = function(ctx, b, vol, primary)
	local hull = newHull(b.cx, b.cy, b.cz, b.w, b.h, b.d, vol.color)
	local count = math.clamp(vol.n or 3, 1, 8)
	local colors = { vol.color, vol.color2 or vol.color, vol.color3 or vol.color2 or vol.color }
	local dia = math.min(b.w, b.d)
	local thick = b.h / count
	local tiers = vol.style == "tiers" -- a tiered cake: every layer narrower than the one below
	for i = 1, count do
		local d = if tiers
			then dia * (1 - 0.6 * (i - 1) / count)
			else dia * (1 - 0.05 * ((i + 1) % 2) - 0.03 * hash(i, 7))
		local center = v3(b.cx + (hash(i, 9) - 0.5) * dia * 0.04, b.cy - b.h / 2 + thick * (i - 0.5), b.cz)
		cylinder(
			ctx,
			if i == 1 then primary else "Shape",
			thick * 1.04,
			d,
			center,
			VERTICAL,
			colors[(i - 1) % 3 + 1],
			"body",
			{ material = vol.material, shadow = i == 1 }
		)
		addSolid(hull, "cyl", center, v3(d / 2, thick / 2, d / 2), 2)
	end
	return hull
end

SKINS.macaron = function(ctx, b, vol, primary)
	local hull = newHull(b.cx, b.cy, b.cz, b.w, b.h, b.d, vol.color)
	local lower = v3(b.cx, b.cy - b.h * 0.26, b.cz)
	local upper = v3(b.cx, b.cy + b.h * 0.26, b.cz)
	local shell = v3(b.w, b.h * 0.5, b.d)
	ellipsoid(
		ctx,
		primary,
		shell,
		upper,
		IDENT,
		vol.color,
		"body",
		{ material = vol.material, squash = true, shadow = true }
	)
	ellipsoid(ctx, "Shape", shell, lower, IDENT, vol.color, "body", { material = vol.material })
	local dia = math.min(b.w, b.d) * 0.9
	cylinder(ctx, "Shape", b.h * 0.24, dia, boxCenter(b), VERTICAL, vol.color2 or "#FFFFFF", "body")
	addSolid(hull, "ellipsoid", upper, vmul(shell, 0.5))
	addSolid(hull, "ellipsoid", lower, vmul(shell, 0.5))
	addSolid(hull, "cyl", boxCenter(b), v3(dia / 2, b.h * 0.12, dia / 2), 2)
	return hull
end

SKINS.cup = function(ctx, b, vol, primary)
	local hull = newHull(b.cx, b.cy, b.cz, b.w, b.h, b.d, vol.color)
	local bottom = b.cy - b.h / 2
	local dia = math.min(b.w, b.d) * 0.86
	local liner = v3(b.cx, bottom + b.h * 0.27, b.cz)
	cylinder(ctx, primary, b.h * 0.54, dia, liner, VERTICAL, vol.color2 or vol.color, "body", { shadow = true })
	addSolid(hull, "cyl", liner, v3(dia / 2, b.h * 0.27, dia / 2), 2)
	local dome = v3(b.cx, bottom + b.h * 0.68, b.cz)
	local size = v3(b.w, b.h * 0.64, b.d)
	ellipsoid(ctx, "Shape", size, dome, IDENT, vol.color, "body", { material = vol.material, squash = true })
	addSolid(hull, "ellipsoid", dome, vmul(size, 0.5))
	return hull
end

SKINS.flan = function(ctx, b, vol, primary)
	local hull = newHull(b.cx, b.cy, b.cz, b.w, b.h, b.d, vol.color)
	local bottom = b.cy - b.h / 2
	local dia = math.min(b.w, b.d)
	local main = v3(b.cx, bottom + b.h * 0.41, b.cz)
	cylinder(
		ctx,
		primary,
		b.h * 0.82,
		dia,
		main,
		VERTICAL,
		vol.color,
		"body",
		{ material = vol.material, shadow = true }
	)
	addSolid(hull, "cyl", main, v3(dia / 2, b.h * 0.41, dia / 2), 2)
	local bevel = v3(b.cx, bottom + b.h * 0.88, b.cz)
	cylinder(ctx, "Shape", b.h * 0.2, dia * 0.86, bevel, VERTICAL, vol.color, "body", { material = vol.material })
	addSolid(hull, "cyl", bevel, v3(dia * 0.43, b.h * 0.1, dia * 0.43), 2)
	if vol.color2 then
		local top = v3(b.cx, bottom + b.h * 0.98, b.cz)
		cylinder(ctx, "Shape", b.h * 0.08, dia * 0.88, top, VERTICAL, vol.color2, "body")
		addSolid(hull, "cyl", top, v3(dia * 0.44, b.h * 0.04, dia * 0.44), 2)
	end
	return hull
end

SKINS.ring = function(ctx, b, vol, primary)
	local hull = newHull(b.cx, b.cy, b.cz, b.w, b.h, b.d, vol.color)
	local hole = vol.color3 or "#5C3A21"
	ellipsoid(
		ctx,
		primary,
		v3(b.w, b.h, b.d),
		boxCenter(b),
		IDENT,
		vol.color,
		"body",
		{ material = vol.material, squash = true, shadow = true }
	)
	addSolid(hull, "ellipsoid", boxCenter(b), v3(b.w / 2, b.h / 2, b.d / 2))
	if vol.style == "flat" then
		local holeDia = math.min(b.w, b.d) * 0.34
		local top = b.cy + b.h / 2
		if vol.color2 then
			local icing = v3(b.cx, b.cy + b.h * 0.25, b.cz)
			local size = v3(b.w * 0.92, b.h * 0.56, b.d * 0.92)
			ellipsoid(ctx, "Shape", size, icing, IDENT, vol.color2, "body")
			addSolid(hull, "ellipsoid", icing, vmul(size, 0.5))
			top = icing.y + size.y / 2
		end
		-- a flat dark (or creamy) dollop hugging the top, so it never pokes out of the curved dough
		local dollop = v3(holeDia, b.h * 0.14, holeDia)
		ellipsoid(ctx, "Shape", dollop, v3(b.cx, top - dollop.y * 0.3, b.cz), IDENT, hole, "detail")
	else
		if vol.color2 then
			local icing = v3(b.cx, b.cy, b.cz - b.d * 0.25)
			local size = v3(b.w * 0.9, b.h * 0.9, b.d * 0.6)
			ellipsoid(ctx, "Shape", size, icing, IDENT, vol.color2, "body")
			addSolid(hull, "ellipsoid", icing, vmul(size, 0.5))
		end
		-- holes (x, y, diameter as shares of the ring): one for a donut, three for a pretzel
		local holes: { { number } } = { { 0, 0, 0.34 } }
		if vol.style == "pretzel" then
			holes = { { -0.2, 0.13, 0.27 }, { 0.2, 0.13, 0.27 }, { 0, -0.22, 0.2 } }
		end
		for _, spec in holes do
			local x, y = spec[1] * b.w, spec[2] * b.h
			local front = frontAt(hull, x, y)
			local back = b.cz + (b.cz - front.z)
			cylinder(
				ctx,
				"Shape",
				back - front.z + eps(b) * 2,
				math.min(b.w, b.h) * spec[3],
				v3(b.cx + x, b.cy + y, (front.z + back) / 2),
				ALONG_Z,
				hole,
				"detail"
			)
		end
	end
	return hull
end

SKINS.block = function(ctx, b, vol, primary)
	local hull = newHull(b.cx, b.cy, b.cz, b.w, b.h, b.d, vol.color)
	local style = vol.style or "plain"
	local bottom = b.cy - b.h / 2
	if style == "toast" then
		local crust = vol.color2 or "#B8732E"
		local lower = v3(b.cx, bottom + b.h * 0.38, b.cz)
		box(ctx, primary, v3(b.w, b.h * 0.76, b.d), lower, IDENT, crust, "body", { squash = true, shadow = true })
		local dome = v3(b.cx, bottom + b.h * 0.76, b.cz)
		ellipsoid(ctx, "Shape", v3(b.w, b.h * 0.48, b.d), dome, IDENT, crust, "body")
		local plate = eps(b) * 6
		local faceLower = v3(b.cx, bottom + b.h * 0.4, b.cz - b.d / 2 - eps(b))
		box(
			ctx,
			"Shape",
			v3(b.w * 0.84, b.h * 0.64, plate),
			faceLower,
			IDENT,
			vol.color,
			"body",
			{ material = vol.material }
		)
		local faceTop = v3(b.cx, bottom + b.h * 0.74, b.cz - b.d / 2 - eps(b))
		ellipsoid(
			ctx,
			"Shape",
			v3(b.w * 0.84, b.h * 0.4, plate),
			faceTop,
			IDENT,
			vol.color,
			"body",
			{ material = vol.material }
		)
		addSolid(hull, "box", v3(b.cx, lower.y, b.cz - eps(b) * 2), v3(b.w / 2, b.h * 0.38, b.d / 2 + eps(b) * 2))
		addSolid(hull, "ellipsoid", v3(b.cx, dome.y, b.cz - eps(b) * 2), v3(b.w / 2, b.h * 0.24, b.d / 2 + eps(b) * 2))
	elseif style == "layers" then
		local count = math.clamp(vol.n or 4, 2, 8)
		local colors = { vol.color, vol.color2 or vol.color, vol.color3 or vol.color2 or vol.color }
		local thick = b.h / count
		for i = 1, count do
			local k = 1 + (hash(i, 5) - 0.5) * 0.06
			local center = v3(b.cx, bottom + thick * (i - 0.5), b.cz)
			box(
				ctx,
				if i == 1 then primary else "Shape",
				v3(b.w * k, thick * 1.02, b.d * k),
				center,
				IDENT,
				colors[(i - 1) % 3 + 1],
				"body",
				{ material = vol.material, shadow = i == 1 }
			)
			addSolid(hull, "box", center, v3(b.w * k / 2, thick / 2, b.d * k / 2))
		end
	else
		box(ctx, primary, v3(b.w, b.h, b.d), boxCenter(b), IDENT, vol.color, "body", {
			material = vol.material,
			squash = true,
			shadow = true,
		})
		addSolid(hull, "box", boxCenter(b), v3(b.w / 2, b.h / 2, b.d / 2))
		local top = b.cy + b.h / 2
		if style == "grid" then
			local bar = vol.color2 or vol.color
			for _, k in { -1, 1 } do
				box(
					ctx,
					"Shape",
					v3(b.w * 1.01, b.h * 0.12, b.d * 0.09),
					v3(b.cx, top, b.cz + k * b.d / 6),
					IDENT,
					bar,
					"detail"
				)
				box(
					ctx,
					"Shape",
					v3(b.w * 0.09, b.h * 0.12, b.d * 1.01),
					v3(b.cx + k * b.w / 6, top, b.cz),
					IDENT,
					bar,
					"detail"
				)
			end
		elseif vol.color2 then
			local slab = v3(b.cx, top - b.h * 0.05, b.cz)
			box(ctx, "Shape", v3(b.w * 1.04, b.h * 0.2, b.d * 1.04), slab, IDENT, vol.color2, "body")
			addSolid(hull, "box", slab, v3(b.w * 0.52, b.h * 0.1, b.d * 0.52))
		end
	end
	return hull
end

SKINS.bun = function(ctx, b, vol, primary)
	local hull = newHull(b.cx, b.cy, b.cz, b.w, b.h, b.d, vol.color)
	local bottom = b.cy - b.h / 2
	local dia = math.min(b.w, b.d)
	local lowerBun = v3(b.cx, bottom + b.h * 0.15, b.cz)
	ellipsoid(ctx, "Shape", v3(b.w * 0.96, b.h * 0.32, b.d * 0.96), lowerBun, IDENT, vol.color, "body", {
		material = vol.material,
		shadow = true,
	})
	local patty = v3(b.cx, bottom + b.h * 0.34, b.cz)
	cylinder(ctx, "Shape", b.h * 0.2, dia, patty, VERTICAL, vol.color2 or "#6B3A1E", "body")
	local cheese = v3(b.cx, bottom + b.h * 0.45, b.cz)
	box(ctx, "Shape", v3(dia * 0.74, b.h * 0.05, dia * 0.74), cheese, ry(math.pi / 4), vol.color3 or "#FFC83D", "body")
	local lettuce = v3(b.cx, bottom + b.h * 0.5, b.cz)
	ellipsoid(ctx, "Shape", v3(b.w * 1.06, b.h * 0.12, b.d * 1.06), lettuce, IDENT, "#7ED957", "body")
	local upper = v3(b.cx, bottom + b.h * 0.66, b.cz)
	local size = v3(b.w, b.h * 0.68, b.d)
	ellipsoid(
		ctx,
		primary,
		size,
		upper,
		IDENT,
		vol.color,
		"body",
		{ material = vol.material, squash = true, shadow = true }
	)
	addSolid(hull, "ellipsoid", lowerBun, v3(b.w * 0.48, b.h * 0.16, b.d * 0.48))
	addSolid(hull, "cyl", patty, v3(dia / 2, b.h * 0.1, dia / 2), 2)
	addSolid(hull, "ellipsoid", lettuce, v3(b.w * 0.53, b.h * 0.06, b.d * 0.53))
	addSolid(hull, "ellipsoid", upper, vmul(size, 0.5))
	return hull
end

SKINS.cone = function(ctx, b, vol, primary)
	local hull = newHull(b.cx, b.cy, b.cz, b.w, b.h, b.d, vol.color)
	local bottom = b.cy - b.h / 2
	local dia = math.min(b.w, b.d)
	local waffle = vol.color2 or "#D99A4E"
	for i, k in { 0.3, 0.5, 0.7 } do
		local center = v3(b.cx, bottom + b.h * 0.09 + (i - 1) * b.h * 0.17, b.cz)
		cylinder(ctx, "Shape", b.h * 0.19, dia * k, center, VERTICAL, waffle, "body", { shadow = i == 3 })
		addSolid(hull, "cyl", center, v3(dia * k / 2, b.h * 0.095, dia * k / 2), 2)
	end
	local scoop = v3(b.cx, bottom + b.h * 0.72, b.cz)
	local size = v3(b.w, b.h * 0.56, b.d)
	ellipsoid(
		ctx,
		primary,
		size,
		scoop,
		IDENT,
		vol.color,
		"body",
		{ material = vol.material, squash = true, shadow = true }
	)
	addSolid(hull, "ellipsoid", scoop, vmul(size, 0.5))
	local rim = v3(b.cx, bottom + b.h * 0.52, b.cz)
	ellipsoid(
		ctx,
		"Shape",
		v3(b.w * 0.98, b.h * 0.16, b.d * 0.98),
		rim,
		IDENT,
		vol.color,
		"body",
		{ material = vol.material }
	)
	return hull
end

SKINS.pear = function(ctx, b, vol, primary)
	local hull = newHull(b.cx, b.cy, b.cz, b.w, b.h, b.d, vol.color)
	local lower = v3(b.cx, b.cy - b.h * 0.14, b.cz)
	local lowerSize = v3(b.w, b.h * 0.72, b.d)
	local upper = v3(b.cx, b.cy + b.h * 0.19, b.cz - b.d * 0.03)
	local upperSize = v3(b.w * 0.76, b.h * 0.62, b.d * 0.82)
	ellipsoid(
		ctx,
		primary,
		lowerSize,
		lower,
		IDENT,
		vol.color,
		"body",
		{ material = vol.material, squash = true, shadow = true }
	)
	ellipsoid(ctx, "Shape", upperSize, upper, IDENT, vol.color2 or vol.color, "body", { material = vol.material })
	addSolid(hull, "ellipsoid", lower, vmul(lowerSize, 0.5))
	addSolid(hull, "ellipsoid", upper, vmul(upperSize, 0.5))
	return hull
end

SKINS.bowl = function(ctx, b, vol, primary)
	local hull = newHull(b.cx, b.cy, b.cz, b.w, b.h, b.d, vol.color)
	local bottom = b.cy - b.h / 2
	local dia = math.min(b.w, b.d)
	local wall = v3(b.cx, bottom + b.h * 0.68, b.cz)
	cylinder(
		ctx,
		primary,
		b.h * 0.64,
		dia,
		wall,
		VERTICAL,
		vol.color,
		"body",
		{ material = vol.material, shadow = true }
	)
	local base = v3(b.cx, bottom + b.h * 0.36, b.cz)
	local baseSize = v3(dia * 0.98, b.h * 0.72, dia * 0.98)
	ellipsoid(ctx, "Shape", baseSize, base, IDENT, vol.color, "body", { material = vol.material })
	local top = bottom + b.h
	cylinder(
		ctx,
		"Shape",
		b.h * 0.08,
		dia * 1.04,
		v3(b.cx, top - b.h * 0.04, b.cz),
		VERTICAL,
		vol.color3 or vol.color,
		"body"
	)
	local broth = v3(b.cx, top - b.h * 0.05, b.cz)
	cylinder(ctx, "Shape", b.h * 0.06, dia * 0.9, broth, VERTICAL, vol.color2 or "#F2C46D", "body")
	addSolid(hull, "cyl", wall, v3(dia / 2, b.h * 0.32, dia / 2), 2)
	addSolid(hull, "ellipsoid", base, vmul(baseSize, 0.5))
	return hull
end

-- Plans: where body, head, limbs and face go -------------------------------------------------------------------------

local function volumeBox(vol: LookVolume?, S: number, w: number, h: number, d: number): (number, number, number)
	if vol == nil then
		return w * S, h * S, d * S
	end
	return (vol.w or w) * S, (vol.h or h) * S, (vol.d or d) * S
end

local function skin(ctx: Ctx, b: Box, vol: LookVolume, primary: string, isFace: boolean): Hull
	local fn = SKINS[vol.skin] or SKINS.round
	return fn(ctx, b, vol, primary, isFace)
end

local function defaultHead(look: CreatureLook): LookVolume
	return look.head or { skin = "round", color = look.limbs or look.body.color }
end

local function newRig(S: number, body: Hull, head: Hull?, look: CreatureLook, tail: V): Rig
	local hulls: { [string]: Hull } = { body = body }
	if head then
		hulls.head = head
	end
	return {
		S = S,
		body = body,
		head = head,
		face = head or body,
		hulls = hulls,
		tail = tail,
		limb = look.limbs or look.body.color,
		summit = {},
	}
end

local function littleFeet(ctx: Ctx, S: number, body: Hull, color: string, spread: number)
	for _, side in { -1, 1 } do
		ellipsoid(
			ctx,
			"Limb",
			v3(0.27 * S, 0.15 * S, 0.34 * S),
			v3(body.cx + side * body.a * spread, 0.075 * S, body.cz - body.c * 0.55),
			IDENT,
			color,
			"body"
		)
	end
end

local function stubbyArms(ctx: Ctx, S: number, body: Hull, color: string, height: number)
	for _, side in { -1, 1 } do
		local p = surfaceAt(body, v3(side, height, -0.25))
		ellipsoid(
			ctx,
			"Limb",
			v3(0.2 * S, 0.36 * S, 0.22 * S),
			v3(p.x + side * 0.04 * S, p.y - 0.1 * S, p.z),
			rz(side * 0.5),
			color,
			"body"
		)
	end
end

type PlanFn = (ctx: Ctx, look: CreatureLook, S: number) -> Rig
local PLANS: { [string]: PlanFn } = {}

PLANS.blob = function(ctx, look, S)
	local w, h, d = volumeBox(look.body, S, 1, 0.86, 0.92)
	local lift = if look.feet then 0.07 * S else 0
	local body = skin(ctx, { cx = 0, cy = lift + h / 2, cz = 0, w = w, h = h, d = d }, look.body, "Body", true)
	local rig = newRig(S, body, nil, look, v3(0, body.cy - h * 0.1, d / 2))
	if look.feet then
		littleFeet(ctx, S, body, rig.limb, 0.48)
	end
	if look.arms then
		stubbyArms(ctx, S, body, rig.limb, -0.1)
	end
	return rig
end

PLANS.biped = function(ctx, look, S)
	local legs = (look.legs or 0) * S
	local feetH = 0.1 * S
	local w, h, d = volumeBox(look.body, S, 0.76, 0.56, 0.66)
	local torsoY = feetH * 0.8 + legs + h / 2
	local torso = skin(ctx, { cx = 0, cy = torsoY, cz = 0, w = w, h = h, d = d }, look.body, "Body", false)
	local headVol = defaultHead(look)
	local hw, hh, hd = volumeBox(look.head, S, 0.84, 0.7, 0.74)
	local neck = (look.neck or 0) * S
	local headY = torsoY + h / 2 + hh * 0.36 + neck
	local head = skin(ctx, { cx = 0, cy = headY, cz = -0.04 * S, w = hw, h = hh, d = hd }, headVol, "Head", true)
	local rig = newRig(S, torso, head, look, v3(0, torsoY - h * 0.2, d / 2))
	if neck > 0 then
		segment(
			ctx,
			"Limb",
			v3(0, torsoY + h * 0.3, 0),
			v3(0, headY - hh * 0.2, -0.03 * S),
			0.3 * S,
			headVol.color,
			"body"
		)
	end
	for _, side in { -1, 1 } do
		ellipsoid(
			ctx,
			"Limb",
			v3(0.27 * S, 0.15 * S, 0.36 * S),
			v3(side * w * 0.27, 0.075 * S, -d * 0.3),
			IDENT,
			rig.limb,
			"body"
		)
		if legs > 0 then
			segment(
				ctx,
				"Limb",
				v3(side * w * 0.22, 0.1 * S, -d * 0.18),
				v3(side * w * 0.22, torsoY - h * 0.3, 0),
				0.11 * S,
				rig.limb,
				"body"
			)
		end
	end
	if look.arms ~= false then
		stubbyArms(ctx, S, torso, rig.limb, 0.15)
	end
	return rig
end

PLANS.quadruped = function(ctx, look, S)
	local legs = (look.legs or 0.22) * S
	local w, h, d = volumeBox(look.body, S, 0.72, 0.54, 0.96)
	local bodyY = legs + h / 2 - 0.04 * S
	local bodyZ = 0.1 * S
	local body = skin(ctx, { cx = 0, cy = bodyY, cz = bodyZ, w = w, h = h, d = d }, look.body, "Body", false)
	local headVol = defaultHead(look)
	local hw, hh, hd = volumeBox(look.head, S, 0.72, 0.62, 0.62)
	local neck = (look.neck or 0) * S
	local headY = bodyY + h / 2 + hh * 0.12 + neck
	local headZ = bodyZ - d / 2 - hd * 0.12 - neck * 0.35
	local head = skin(ctx, { cx = 0, cy = headY, cz = headZ, w = hw, h = hh, d = hd }, headVol, "Head", true)
	local rig = newRig(S, body, head, look, v3(0, bodyY + h * 0.15, bodyZ + d / 2 - 0.02 * S))
	if neck > 0 then
		segment(
			ctx,
			"Limb",
			v3(0, bodyY + h * 0.2, bodyZ - d * 0.32),
			v3(0, headY - hh * 0.15, headZ + hd * 0.1),
			0.32 * S,
			headVol.color,
			"body"
		)
	end
	local legHeight = legs + 0.14 * S
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			ellipsoid(
				ctx,
				"Limb",
				v3(0.22 * S, legHeight, 0.24 * S),
				v3(sx * (w / 2 - 0.12 * S), legHeight / 2, bodyZ + sz * (d / 2 - 0.17 * S)),
				IDENT,
				rig.limb,
				"body"
			)
		end
	end
	return rig
end

PLANS.swimmer = function(ctx, look, S)
	local w, h, d = volumeBox(look.body, S, 0.78, 0.64, 1.12)
	local body = skin(ctx, { cx = 0, cy = 0.09 * S + h / 2, cz = 0, w = w, h = h, d = d }, look.body, "Body", true)
	local rig = newRig(S, body, nil, look, v3(0, body.cy + 0.03 * S, d / 2 - 0.04 * S))
	for _, side in { -1, 1 } do
		ellipsoid(
			ctx,
			"Limb",
			v3(0.36 * S, 0.08 * S, 0.24 * S),
			v3(side * w * 0.42, 0.07 * S, -d * 0.12),
			rz(-side * 0.35),
			rig.limb,
			"body"
		)
	end
	return rig
end

PLANS.tentacled = function(ctx, look, S)
	local w, h, d = volumeBox(look.body, S, 0.96, 0.8, 0.92)
	local body = skin(ctx, { cx = 0, cy = 0.24 * S + h / 2, cz = 0, w = w, h = h, d = d }, look.body, "Body", true)
	local rig = newRig(S, body, nil, look, v3(0, body.cy, d / 2))
	local count = math.clamp(look.tentacles or 6, 2, 10)
	local alt = look.body.color2 or rig.limb
	for i = 1, count do
		local theta = (i - 0.5) / count * math.pi * 2
		local out = v3(math.sin(theta), 0, -math.cos(theta))
		local reach = w / (0.96 * S)
		local first = v3(out.x * 0.38 * S * reach, 0.21 * S, out.z * 0.38 * S * reach)
		ellipsoid(
			ctx,
			"Limb",
			v3(0.24 * S, 0.24 * S, 0.5 * S),
			first,
			aimZ(vadd(out, v3(0, -0.55, 0))),
			rig.limb,
			"body"
		)
		local tip = v3(out.x * 0.62 * S * reach, 0.1 * S, out.z * 0.62 * S * reach)
		ellipsoid(ctx, "Limb", v3(0.18 * S, 0.16 * S, 0.34 * S), tip, aimZ(vadd(out, v3(0, 0.4, 0))), alt, "body")
	end
	return rig
end

-- Face -----------------------------------------------------------------------------------------------------------------

type FacePoint = { p: V, n: V }

local function faceAt(hull: Hull, x: number, y: number): FacePoint
	local p, n = frontAt(hull, x, y)
	return { p = p, n = n }
end

local function buildEye(ctx: Ctx, rig: Rig, at: FacePoint, side: number, e: number, style: string, pupilColor: string)
	local n = at.n
	local gaze = vnorm(vadd(n, v3(-side * 0.06, -0.08, 0)))
	if style == "dot" then
		local p = e * 0.62
		local center = vadd(at.p, vmul(n, p * 0.18))
		ball(ctx, "Pupil", p, center, pupilColor, "face")
		ball(
			ctx,
			"Highlight",
			p * 0.36,
			vadd(vadd(center, vmul(gaze, p * 0.36)), v3(p * 0.16, p * 0.18, 0)),
			SCLERA,
			"face"
		)
		return
	end
	if style == "happy" then
		local t = math.max(e * 0.14, MIN_SIZE)
		local function on(dx: number, dy: number): V
			local q = frontAt(rig.face, at.p.x + dx - rig.face.cx, at.p.y + dy - rig.face.cy)
			return vadd(q, vmul(n, t * 0.35))
		end
		local peak = on(0, e * 0.16)
		segment(ctx, "Eye", on(-e * 0.34, -e * 0.1), peak, t, pupilColor, "face")
		segment(ctx, "Eye", peak, on(e * 0.34, -e * 0.1), t, pupilColor, "face")
		return
	end
	local sclera = vadd(at.p, vmul(n, e * 0.12))
	ball(ctx, "Eye", e, sclera, SCLERA, "face")
	local p = e * 0.58
	local look = if style == "sleepy" then vnorm(vadd(gaze, v3(0, -0.25, 0))) else gaze
	local pupil = vadd(sclera, vmul(look, e / 2 - p * 0.32))
	ball(ctx, "Pupil", p, pupil, pupilColor, "face")
	if style == "sleepy" then
		ellipsoid(
			ctx,
			"Lid",
			v3(e * 1.1, e * 0.64, e * 1.1),
			vadd(sclera, v3(0, e * 0.27, 0)),
			aimZ(n),
			rig.face.color,
			"body"
		)
	else
		local h = p * 0.36
		ball(
			ctx,
			"Highlight",
			h,
			vadd(vadd(pupil, vmul(look, p / 2 - h * 0.2)), v3(p * 0.18, p * 0.2, 0)),
			SCLERA,
			"face"
		)
	end
end

local function buildFace(ctx: Ctx, rig: Rig, face: LookFace)
	local hull = rig.face
	local style = face.eyes or "round"
	local size = math.min(hull.a, hull.b)
	local e = size * 0.62 * (face.scale or 1) * (if style == "big" then 1.25 else 1)
	local u = (face.spacing or 0.36) * hull.a
	local v = (face.height or 0.12) * hull.b
	local pupilColor = face.pupil or PUPIL

	if face.patches then
		-- panda patches: the eyes sit on them
		for _, side in { -1, 1 } do
			local at = faceAt(hull, side * u, v - e * 0.12)
			local center = vadd(at.p, vmul(at.n, -e * 0.14))
			local patch = v3(e * 1.45, e * 1.2, e * 0.55)
			ellipsoid(ctx, "Patch", patch, center, mmul(aimZ(at.n), rz(side * 0.45)), face.patches, "face")
			addSolid(hull, "ellipsoid", center, v3(e * 0.66, e * 0.62, e * 0.275))
		end
	end

	if style == "stalk" then
		for _, side in { -1, 1 } do
			local base = topAt(hull, side * hull.a * 0.3, -hull.c * 0.4)
			local dir = vnorm(v3(side * 0.25, 1, -0.15))
			local top = vadd(base, vmul(dir, hull.b * 0.95))
			segment(ctx, "Stalk", vsub(base, vmul(dir, e * 0.2)), top, e * 0.3, hull.color, "body")
			local front = v3(0, 0, -1)
			local sclera = vadd(top, vmul(dir, e * 0.35))
			ball(ctx, "Eye", e, sclera, SCLERA, "face")
			local p = e * 0.58
			local pupil = vadd(sclera, vmul(front, e / 2 - p * 0.32))
			ball(ctx, "Pupil", p, pupil, pupilColor, "face")
			ball(ctx, "Highlight", p * 0.36, vadd(pupil, v3(p * 0.18, p * 0.2, -p * 0.38)), SCLERA, "face")
		end
	else
		for _, side in { -1, 1 } do
			buildEye(ctx, rig, faceAt(hull, side * u, v), side, e, style, pupilColor)
		end
	end

	if face.brows then
		for _, side in { -1, 1 } do
			local inner = faceAt(hull, side * (u - e * 0.38), v + e * 0.68)
			local outer = faceAt(hull, side * (u + e * 0.38), v + e * 0.6)
			local t = math.max(e * 0.16, MIN_SIZE)
			segment(
				ctx,
				"Brow",
				vadd(inner.p, vmul(inner.n, t * 0.4)),
				vadd(outer.p, vmul(outer.n, t * 0.4)),
				t,
				face.brows,
				"face"
			)
		end
	end

	-- Mouth: on the muzzle if the snout feature made one, else under the eyes.
	local mouthHull = rig.muzzle or hull
	local mw: number
	local mouthAt: FacePoint
	if rig.muzzle then
		local m = rig.muzzle :: Hull
		mw = m.a * 0.95
		mouthAt = faceAt(m, 0, -m.b * 0.42)
	else
		mw = hull.a * 0.42 * math.sqrt(face.scale or 1)
		mouthAt = faceAt(hull, 0, if face.mouthAt then face.mouthAt * hull.b else v - hull.b * 0.5)
	end
	local mouthColor = face.mouthColor or MOUTH
	local t = math.max(mw * 0.13, MIN_SIZE)
	local mouth = face.mouth or "smile"
	local function onMouth(dx: number, dy: number, lift: number): V
		local q = frontAt(mouthHull, mouthAt.p.x + dx - mouthHull.cx, mouthAt.p.y + dy - mouthHull.cy)
		return vadd(q, vmul(mouthAt.n, lift))
	end
	local function smile()
		local xs = { -0.5, -0.17, 0.17, 0.5 }
		local points: { V } = {}
		for _, k in xs do
			table.insert(points, onMouth(k * mw, (k * 2) ^ 2 * mw * 0.16, t * 0.3))
		end
		for i = 1, 3 do
			segment(ctx, "Mouth", points[i], points[i + 1], t, mouthColor, "face")
		end
	end
	local flat = aimZ(mouthAt.n)
	if mouth == "smile" then
		smile()
	elseif mouth == "tongue" then
		smile()
		ellipsoid(
			ctx,
			"Tongue",
			v3(mw * 0.38, mw * 0.4, mw * 0.2),
			onMouth(0, -mw * 0.14, mw * 0.06),
			flat,
			TONGUE,
			"face"
		)
	elseif mouth == "fang" then
		smile()
		for _, side in { -1, 1 } do
			ellipsoid(
				ctx,
				"Teeth",
				v3(mw * 0.13, mw * 0.24, mw * 0.1),
				onMouth(side * mw * 0.2, -mw * 0.06, t * 0.25),
				flat,
				TEETH,
				"face"
			)
		end
	elseif mouth == "open" then
		ellipsoid(ctx, "Mouth", v3(mw * 0.8, mw * 0.6, t * 2), onMouth(0, -mw * 0.1, 0), flat, mouthColor, "face")
		ellipsoid(ctx, "Tongue", v3(mw * 0.5, mw * 0.26, t * 2), onMouth(0, -mw * 0.22, t * 0.3), flat, TONGUE, "face")
	elseif mouth == "o" then
		ellipsoid(ctx, "Mouth", v3(mw * 0.42, mw * 0.48, t * 2), onMouth(0, -mw * 0.1, 0), flat, mouthColor, "face")
	elseif mouth == "cat" then
		local xs = { -0.5, -0.25, 0, 0.25, 0.5 }
		local ys = { 0.05, -0.22, 0, -0.22, 0.05 }
		local points: { V } = {}
		for i, k in xs do
			table.insert(points, onMouth(k * mw, ys[i] * mw, t * 0.3))
		end
		for i = 1, 4 do
			segment(ctx, "Mouth", points[i], points[i + 1], t * 0.9, mouthColor, "face")
		end
	elseif mouth == "grin" then
		ellipsoid(ctx, "Mouth", v3(mw, mw * 0.5, t * 2), onMouth(0, -mw * 0.12, 0), flat, mouthColor, "face")
		box(ctx, "Teeth", v3(mw * 0.72, mw * 0.14, t * 2.1), onMouth(0, mw * 0.03, t * 0.1), flat, TEETH, "face")
	end
	rig.mouth = mouthAt.p
	rig.mouthNormal = mouthAt.n

	if face.cheeks then
		for _, side in { -1, 1 } do
			local at = faceAt(hull, side * (u + e * 0.42), v - e * 0.78)
			ellipsoid(
				ctx,
				"Cheek",
				v3(e * 0.7, e * 0.42, e * 0.2),
				vadd(at.p, vmul(at.n, e * 0.03)),
				aimZ(at.n),
				face.cheeks,
				"face"
			)
		end
	end
	if face.nose and rig.muzzle == nil then
		local at = faceAt(hull, 0, (v + (mouthAt.p.y - hull.cy)) / 2 + e * 0.05)
		ball(ctx, "Nose", e * 0.42, vadd(at.p, vmul(at.n, e * 0.08)), face.nose, "face")
	end
end

-- Features: which animal it is ------------------------------------------------------------------------------------------

type FeatureFn = (ctx: Ctx, rig: Rig, f: LookFeature) -> ()
local FEATURES: { [string]: FeatureFn } = {}

local function target(rig: Rig, on: string?, default: string): Hull
	local key = on or default
	return rig.hulls[key] or (if key == "head" then rig.face else rig.body)
end

local function fx(f: LookFeature): Extra
	return { material = f.material }
end

FEATURES.ears = function(ctx, rig, f)
	local h = target(rig, f.on, "head")
	local color = f.color or h.color
	local sc = f.scale or 1
	local a = h.a
	local style = f.style or "round"
	for _, side in { -1, 1 } do
		if style == "pointy" then
			local p = surfaceAt(h, v3(side * 0.55, 0.85, 0.05))
			local size = v3(0.18 * a * sc, 0.8 * a * sc, 0.62 * a * sc)
			local rot = mmul(rz(-side * 0.22), ry(side * math.pi / 2))
			wedge(ctx, "Feature", size, vadd(p, v3(side * 0.02 * a, size.y * 0.3, 0)), rot, color, "body", fx(f))
			if f.color2 then
				local inner = vmul(size, 0.6)
				local at = vadd(p, v3(side * 0.06 * a * sc, size.y * 0.22, -size.x * 0.45))
				wedge(ctx, "Feature", v3(inner.x, inner.y, inner.z), at, rot, f.color2, "detail")
			end
		elseif style == "floppy" then
			local p = surfaceAt(h, v3(side, 0.62, 0.05))
			local size = v3(0.34 * a * sc, 0.95 * h.b * sc, 0.5 * h.c * sc)
			ellipsoid(
				ctx,
				"Feature",
				size,
				vadd(p, v3(side * 0.08 * a, -0.32 * h.b * sc, 0)),
				rz(side * 0.3),
				color,
				"body",
				fx(f)
			)
		elseif style == "long" then
			local p = surfaceAt(h, v3(side * 0.38, 1, 0))
			local size = v3(0.34 * a * sc, 1.3 * h.b * sc, 0.22 * h.c * sc)
			local center = vadd(p, v3(side * 0.06 * a, size.y * 0.42, 0))
			ellipsoid(ctx, "Feature", size, center, rz(-side * 0.14), color, "body", fx(f))
			if f.color2 then
				ellipsoid(
					ctx,
					"Feature",
					v3(size.x * 0.55, size.y * 0.72, size.z * 0.5),
					vadd(center, v3(0, -size.y * 0.04, -size.z * 0.32)),
					rz(-side * 0.14),
					f.color2,
					"detail"
				)
			end
		else -- round / mouse
			local k = if style == "mouse" then 1.5 else 1
			local p, n = surfaceAt(h, v3(side * 0.62, 0.8, 0.05))
			local size = v3(0.6 * a * sc * k, 0.6 * a * sc * k, 0.24 * a * sc)
			local center = vadd(p, vmul(n, size.x * 0.22))
			ellipsoid(ctx, "Feature", size, center, rz(-side * 0.25), color, "body", fx(f))
			if f.color2 then
				ellipsoid(
					ctx,
					"Feature",
					v3(size.x * 0.58, size.y * 0.58, size.z * 0.6),
					vadd(center, v3(0, 0, -size.z * 0.4)),
					rz(-side * 0.25),
					f.color2,
					"detail"
				)
			end
		end
	end
end

FEATURES.horns = function(ctx, rig, f)
	local h = target(rig, f.on, "head")
	local color = f.color or "#FFF4D6"
	local sc = f.scale or 1
	local a = h.a
	local style = f.style or "nub"
	if style == "unicorn" then
		local p = surfaceAt(h, v3(0, 0.9, -0.5))
		local dir = vnorm(v3(0, 1, -0.3))
		local colors = { color, f.color2 or color, color }
		for i, k in { 0.24, 0.16, 0.08 } do
			local center = vadd(p, vmul(dir, a * sc * (0.1 + (i - 1) * 0.26)))
			cylinder(ctx, "Feature", a * sc * 0.3, a * sc * k, center, aimX(dir), colors[i], "body", fx(f))
		end
		return
	end
	if style == "tusk" then
		local at = faceAt(h, 0, h.b * 0.05)
		local dir = vnorm(v3(0, 0.3, -1))
		local colors = { color, f.color2 or color, color }
		for i, k in { 0.12, 0.085, 0.05 } do
			local center = vadd(at.p, vmul(dir, a * sc * (0.2 + (i - 1) * 0.42)))
			cylinder(ctx, "Feature", a * sc * 0.46, a * sc * k, center, aimX(dir), colors[i], "body", fx(f))
		end
		return
	end
	for _, side in { -1, 1 } do
		local p, n = surfaceAt(h, v3(side * 0.42, 0.9, 0.1))
		if style == "antlers" then
			local dir = vnorm(v3(side * 0.9, 1, 0.1))
			local endPoint = vadd(p, vmul(dir, 0.55 * a * sc))
			segment(ctx, "Feature", vsub(p, vmul(dir, 0.05 * a)), endPoint, 0.17 * a * sc, color, "body", fx(f))
			-- a broad, upright palm with two points on its upper edge
			local palm = vadd(endPoint, v3(side * 0.2 * a * sc, 0.24 * a * sc, 0))
			local tilt = rz(-side * 0.8)
			ellipsoid(ctx, "Feature", v3(0.95 * a * sc, 0.62 * a * sc, 0.16 * a * sc), palm, tilt, color, "body", fx(f))
			for _, along in { 0.05, 0.4 } do
				local point = vadd(palm, mv(tilt, v3(side * along * a * sc, 0.3 * a * sc, 0)))
				ball(ctx, "Feature", 0.22 * a * sc, point, f.color2 or color, "body")
			end
		elseif style == "curved" then
			local d1 = vnorm(v3(side * 0.55, 1, 0.25))
			local c1 = vadd(p, vmul(d1, 0.16 * a * sc))
			ellipsoid(ctx, "Feature", v3(0.2 * a * sc, 0.5 * a * sc, 0.2 * a * sc), c1, aimY(d1), color, "body", fx(f))
			local d2 = vnorm(v3(side * 0.35, 0.45, 1))
			local c2 = vadd(vadd(c1, vmul(d1, 0.22 * a * sc)), vmul(d2, 0.15 * a * sc))
			ellipsoid(
				ctx,
				"Feature",
				v3(0.15 * a * sc, 0.4 * a * sc, 0.15 * a * sc),
				c2,
				aimY(d2),
				f.color2 or color,
				"body",
				fx(f)
			)
		else -- nub
			local dir = vnorm(vadd(n, v3(side * 0.25, 0.6, 0)))
			ellipsoid(
				ctx,
				"Feature",
				v3(0.2 * a * sc, 0.46 * a * sc, 0.2 * a * sc),
				vadd(p, vmul(dir, 0.14 * a * sc)),
				aimY(dir),
				color,
				"body",
				fx(f)
			)
		end
	end
end

FEATURES.antennae = function(ctx, rig, f)
	local h = target(rig, f.on, "head")
	local sc = f.scale or 1
	local a = h.a
	for _, side in { -1, 1 } do
		local p = surfaceAt(h, v3(side * 0.35, 1, 0))
		local dir = vnorm(v3(side * 0.45, 1, -0.1))
		local tip = vadd(p, vmul(dir, 0.75 * a * sc))
		segment(ctx, "Feature", vsub(p, vmul(dir, 0.05 * a)), tip, 0.07 * a * sc, f.color or h.color, "body", fx(f))
		ball(ctx, "Feature", 0.24 * a * sc, tip, f.color2 or f.color or h.color, "body")
	end
end

FEATURES.tail = function(ctx, rig, f)
	local S = rig.S * (f.scale or 1)
	local color = f.color or rig.body.color
	local alt = f.color2 or color
	local t = rig.tail
	local style = f.style or "stub"
	if style == "puff" or style == "stub" then
		local d = if style == "puff" then 0.32 * S else 0.22 * S
		ball(ctx, "Feature", d, vadd(t, v3(0, 0.02 * S, d * 0.25)), color, "body", fx(f))
	elseif style == "curly" then
		local points = { v3(0, 0, 0.06), v3(0.07, 0.07, 0.12), v3(0, 0.14, 0.15), v3(-0.05, 0.1, 0.1) }
		for i = 1, 3 do
			segment(
				ctx,
				"Feature",
				vadd(t, vmul(points[i], S)),
				vadd(t, vmul(points[i + 1], S)),
				0.08 * S,
				color,
				"body",
				fx(f)
			)
		end
	elseif style == "thin" or style == "lion" then
		local dirs = { vnorm(v3(0, 0.25, 1)), vnorm(v3(0, 1, 0.7)), vnorm(v3(0, 1, -0.15)) }
		local p = t
		for i, d in dirs do
			local len = 0.22 * S
			local last = i == #dirs
			local c = if last and style == "thin" then alt else color
			segment(ctx, "Feature", p, vadd(p, vmul(d, len)), 0.09 * S, c, "body", fx(f))
			p = vadd(p, vmul(d, len * 0.9))
		end
		if style == "lion" then
			ball(ctx, "Feature", 0.24 * S, p, alt, "body")
		end
	elseif style == "fluffy" then
		local count = math.clamp(f.n or 1, 1, 9)
		for i = 1, count do
			local spread = if count == 1 then 0 else (i - 1) / (count - 1) * 2 - 1
			local dir = vnorm(v3(spread * 0.7, 0.85 - math.abs(spread) * 0.2, 0.8))
			local main = vadd(t, vmul(dir, 0.3 * S))
			ellipsoid(ctx, "Feature", v3(0.34 * S, 0.62 * S, 0.34 * S), main, aimY(dir), color, "body", fx(f))
			ball(ctx, "Feature", 0.28 * S, vadd(t, vmul(dir, 0.62 * S)), alt, "body", fx(f))
		end
	elseif style == "long" then
		local d = vnorm(v3(0, -0.32, 1))
		local p = vadd(t, vmul(d, 0.12 * S))
		for i, k in { 1, 0.72, 0.48 } do
			local center = vadd(p, vmul(d, 0.2 * S))
			center = v3(center.x, math.max(center.y, 0.16 * S * k), center.z)
			ellipsoid(
				ctx,
				"Feature",
				v3(0.34 * S * k, 0.3 * S * k, 0.5 * S),
				center,
				aimZ(d),
				if i == 3 then alt else color,
				"body",
				fx(f)
			)
			p = vadd(p, vmul(d, 0.27 * S))
		end
	elseif style == "flat" then
		ellipsoid(
			ctx,
			"Feature",
			v3(0.48 * S, 0.1 * S, 0.66 * S),
			v3(t.x, 0.07 * S, t.z + 0.28 * S),
			rx(-0.12),
			color,
			"body",
			fx(f)
		)
	elseif style == "fluke" then
		ellipsoid(
			ctx,
			"Feature",
			v3(0.24 * S, 0.2 * S, 0.36 * S),
			vadd(t, v3(0, 0, 0.12 * S)),
			IDENT,
			color,
			"body",
			fx(f)
		)
		for _, side in { -1, 1 } do
			ellipsoid(
				ctx,
				"Feature",
				v3(0.5 * S, 0.08 * S, 0.26 * S),
				vadd(t, v3(side * 0.2 * S, 0.04 * S, 0.3 * S)),
				ry(side * 0.55),
				alt,
				"body",
				fx(f)
			)
		end
	elseif style == "fin" then
		for _, side in { -1, 1 } do
			ellipsoid(
				ctx,
				"Feature",
				v3(0.07 * S, 0.46 * S, 0.3 * S),
				vadd(t, v3(0, side * 0.13 * S, 0.2 * S)),
				rx(-side * 0.6),
				color,
				"body",
				fx(f)
			)
		end
	elseif style == "ringed" then
		local d = vnorm(v3(0, 0.55, 1))
		local p = t
		for i = 1, 4 do
			local k = 1 - (i - 1) * 0.1
			ellipsoid(
				ctx,
				"Feature",
				v3(0.3 * S * k, 0.3 * S * k, 0.26 * S),
				vadd(p, vmul(d, 0.12 * S)),
				aimZ(d),
				if i % 2 == 1 then color else alt,
				"body",
				fx(f)
			)
			p = vadd(p, vmul(d, 0.21 * S))
			d = vnorm(vadd(d, v3(0, 0.22, -0.05)))
		end
	end
end

FEATURES.wings = function(ctx, rig, f)
	local h = target(rig, f.on, "body")
	local S = rig.S * (f.scale or 1)
	local color = f.color or h.color
	local alt = f.color2 or color
	local style = f.style or "feather"
	for _, side in { -1, 1 } do
		local root = surfaceAt(h, v3(side * 0.85, 0.4, 0.3))
		if style == "tiny" then
			ellipsoid(
				ctx,
				"Feature",
				v3(0.1 * S, 0.34 * S, 0.42 * S),
				vadd(root, v3(side * 0.1 * S, 0.12 * S, 0.06 * S)),
				mmul(rz(-side * 0.55), rx(0.2)),
				color,
				"body",
				fx(f)
			)
		elseif style == "feather" then
			local center = vadd(root, v3(side * 0.03 * S, -0.06 * S, 0.06 * S))
			local rot = mmul(rx(0.3), rz(-side * 0.12))
			ellipsoid(ctx, "Feature", v3(0.12 * S, 0.48 * S, 0.62 * S), center, rot, color, "body", fx(f))
			if f.color2 then
				ellipsoid(
					ctx,
					"Feature",
					v3(0.1 * S, 0.28 * S, 0.36 * S),
					vadd(center, v3(side * 0.02 * S, -0.14 * S, 0.24 * S)),
					rot,
					alt,
					"body"
				)
			end
		elseif style == "bat" or style == "dragon" then
			local big = if style == "dragon" then 1.1 else 0.95
			local sweep = mmul(ry(-side * 0.35), ry(side * math.pi / 2))
			local upper = v3(0.06 * S, 0.56 * S * big, 0.56 * S * big)
			wedge(
				ctx,
				"Feature",
				upper,
				vadd(root, v3(side * 0.26 * S * big, 0.22 * S * big, 0.08 * S)),
				sweep,
				color,
				"body",
				fx(f)
			)
			local lower = v3(0.06 * S, 0.3 * S * big, 0.32 * S * big)
			wedge(
				ctx,
				"Feature",
				lower,
				vadd(root, v3(side * 0.38 * S * big, -0.2 * S * big + 0.14 * S, 0.12 * S)),
				mmul(sweep, rx(math.pi)),
				alt,
				"body",
				fx(f)
			)
			if style == "dragon" then
				local tip = vadd(root, v3(side * 0.52 * S * big, 0.5 * S * big, 0.14 * S))
				segment(ctx, "Feature", root, tip, 0.08 * S, f.color3 or color, "body")
			end
		elseif style == "moth" then
			-- butterfly-like: flat wings facing front / back, spreading up and out
			local up = vnorm(v3(side * 0.75, 1, 0.25))
			local upper = vadd(root, vmul(up, 0.3 * S))
			ellipsoid(
				ctx,
				"Feature",
				v3(0.42 * S, 0.62 * S, 0.06 * S),
				upper,
				frameYZ(up, v3(0, 0, 1)),
				color,
				"body",
				fx(f)
			)
			local low = vnorm(v3(side, -0.55, 0.25))
			ellipsoid(
				ctx,
				"Feature",
				v3(0.3 * S, 0.4 * S, 0.06 * S),
				vadd(root, vmul(low, 0.2 * S)),
				frameYZ(low, v3(0, 0, 1)),
				color,
				"body",
				fx(f)
			)
			if f.color2 then
				ball(
					ctx,
					"Feature",
					0.16 * S,
					vadd(upper, vadd(vmul(up, 0.06 * S), v3(0, 0, -0.04 * S))),
					alt,
					"detail"
				)
			end
		elseif style == "angel" then
			-- three feathers fanning up and out from the shoulder, flat faces to the front
			local colors = { color, alt, f.color3 or color }
			for i = 1, 3 do
				local angle = math.rad(68 - (i - 1) * 24)
				local dir = vnorm(v3(side * math.cos(angle), math.sin(angle), 0.3))
				local long = (0.66 - (i - 1) * 0.08) * S
				ellipsoid(
					ctx,
					"Feature",
					v3(0.24 * S, long, 0.07 * S),
					vadd(vadd(root, vmul(dir, long * 0.42)), v3(0, 0, 0.03 * S * i)),
					frameYZ(dir, v3(0, 0, 1)),
					colors[i],
					"body",
					fx(f)
				)
			end
		elseif style == "manta" then
			-- a flat triangle swept back from the body's side (like half a pizza slice)
			local span = h.a * 1.05
			local chord = h.c * 1.5
			local rot: M = if side > 0 then { 0, 1, 0, -1, 0, 0, 0, 0, 1 } else { 0, -1, 0, 1, 0, 0, 0, 0, 1 }
			wedge(
				ctx,
				"Feature",
				v3(h.b * 0.5, span, chord),
				v3(h.cx + side * (h.a * 0.55 + span / 2), h.cy - h.b * 0.15, h.cz + h.c * 0.1),
				rot,
				color,
				"body",
				fx(f)
			)
		end
	end
end

FEATURES.shell = function(ctx, rig, f)
	local body = target(rig, f.on, "body")
	local color = f.color or "#5BBF3A"
	local alt = f.color2 or color
	local sc = f.scale or 1
	local style = f.style or "dome"
	local hull: Hull
	if style == "spiral" then
		local dia = body.b * 2.5 * sc
		local center = v3(body.cx, body.cy + body.b * 0.75 + dia * 0.28, body.cz + body.c * 0.3)
		hull = newHull(center.x, center.y, center.z, body.a * 1.5, dia, dia, color)
		local thick = body.a * 1.5
		cylinder(ctx, "Feature", thick, dia, center, IDENT, color, "body", { material = f.material, shadow = true })
		addSolid(hull, "cyl", center, v3(thick / 2, dia / 2, dia / 2), 1)
		local colors = { alt, color, alt }
		for i, k in { 0.74, 0.48, 0.22 } do
			local at = vadd(center, v3(0, dia * 0.035 * i, -dia * 0.03 * i))
			cylinder(ctx, "Feature", thick * (1 + 0.03 * i + 0.015), dia * k, at, IDENT, colors[i], "detail")
		end
	else
		local size = v3(body.a * 2 * 0.98 * sc, body.b * 2 * 0.9 * sc, body.c * 2 * 0.92 * sc)
		local center = v3(body.cx, body.cy + body.b * 0.42, body.cz + body.c * 0.04)
		hull = newHull(center.x, center.y, center.z, size.x, size.y, size.z, color)
		ellipsoid(ctx, "Feature", size, center, IDENT, color, "body", { material = f.material, shadow = true })
		addSolid(hull, "ellipsoid", center, vmul(size, 0.5))
		ellipsoid(
			ctx,
			"Feature",
			v3(size.x * 1.05, body.b * 0.36, size.z * 1.03),
			v3(body.cx, body.cy + body.b * 0.12, center.z),
			IDENT,
			alt,
			"body"
		)
		if style == "dome" then
			for i = 1, math.clamp(f.n or 4, 0, 8) do
				local theta = i * 2.39996
				local r = 0.55 * math.sqrt((i - 0.5) / math.max(f.n or 4, 1))
				local p, n = topAt(hull, math.cos(theta) * r * hull.a, math.sin(theta) * r * hull.c)
				ellipsoid(
					ctx,
					"Feature",
					v3(hull.a * 0.5, hull.b * 0.14, hull.a * 0.5),
					p,
					aimY(n),
					f.color3 or alt,
					"detail"
				)
			end
		end
	end
	rig.hulls.shell = hull
end

FEATURES.mane = function(ctx, rig, f)
	local h = target(rig, f.on, "head")
	local count = math.clamp(f.n or 8, 4, 14)
	local sc = f.scale or 1
	local color = f.color or "#C8742B"
	local colors = { color, f.color2 or color }
	local radius = math.max(h.a, h.b) * 0.92
	for i = 1, count do
		local phi = (i - 1) / count * math.pi * 2
		local center = v3(h.cx + math.cos(phi) * radius, h.cy + math.sin(phi) * radius * 0.95, h.cz + h.c * 0.25)
		ellipsoid(
			ctx,
			"Feature",
			v3(0.62 * h.a * sc, 0.62 * h.a * sc, 0.5 * h.c * sc),
			center,
			rz(phi),
			colors[(i - 1) % 2 + 1],
			"body",
			fx(f)
		)
	end
end

FEATURES.snout = function(ctx, rig, f)
	local h = rig.face
	local sc = f.scale or 1
	local color = f.color or "#FFF1DE"
	local nose = f.color2 or NOSE
	local style = f.style or "dog"
	local v = -h.b * 0.32
	local at = faceAt(h, 0, v)
	if style == "beak" or style == "toucan" then
		local len = h.c * (if style == "toucan" then 1.4 else 0.7) * sc
		local width = h.a * (if style == "toucan" then 0.55 else 0.4) * sc
		local height = h.b * (if style == "toucan" then 0.5 else 0.3) * sc
		local base = vadd(at.p, v3(0, h.b * 0.08, 0))
		local center = vadd(base, v3(0, 0, -len * 0.36))
		ellipsoid(ctx, "Feature", v3(width, height, len), center, rx(-0.12), color, "body", fx(f))
		if f.color2 then
			ellipsoid(
				ctx,
				"Feature",
				v3(width * 0.7, height * 0.72, len * 0.34),
				vadd(center, v3(0, -height * 0.05, -len * 0.36)),
				rx(-0.12),
				f.color2,
				"body"
			)
		end
		if style == "toucan" and f.color3 then
			ellipsoid(
				ctx,
				"Feature",
				v3(width * 1.04, height * 0.3, len * 0.18),
				vadd(center, v3(0, height * 0.12, len * 0.05)),
				rx(-0.12),
				f.color3,
				"detail"
			)
		end
		return
	end
	if style == "bill" then
		local len = h.c * 0.75 * sc
		ellipsoid(
			ctx,
			"Feature",
			v3(h.a * 0.7 * sc, h.b * 0.16 * sc, len),
			vadd(at.p, v3(0, 0, -len * 0.32)),
			IDENT,
			color,
			"body",
			fx(f)
		)
		ellipsoid(
			ctx,
			"Feature",
			v3(h.a * 0.6 * sc, h.b * 0.12 * sc, len * 0.8),
			vadd(at.p, v3(0, -h.b * 0.12 * sc, -len * 0.24)),
			IDENT,
			f.color2 or color,
			"body"
		)
		return
	end
	if style == "trunk" then
		local p = vadd(at.p, v3(0, h.b * 0.1, 0))
		local d = vnorm(v3(0, -0.5, -1))
		for i, k in { 1, 0.82, 0.66 } do
			local center = vadd(p, vmul(d, 0.2 * h.a * sc))
			ellipsoid(
				ctx,
				"Feature",
				v3(0.34 * h.a * sc * k, 0.34 * h.a * sc * k, 0.46 * h.a * sc),
				center,
				aimZ(d),
				color,
				"body",
				fx(f)
			)
			p = vadd(p, vmul(d, 0.34 * h.a * sc))
			d = vnorm(vadd(d, v3(0, -0.6 - 0.2 * i, 0.25)))
		end
		return
	end
	if style == "pig" then
		local dia = h.a * 0.5 * sc
		local depth = h.c * 0.22 * sc
		local center = vadd(at.p, vmul(at.n, depth * 0.3))
		cylinder(ctx, "Feature", depth, dia, center, aimX(at.n), color, "body", fx(f))
		for _, side in { -1, 1 } do
			ball(
				ctx,
				"Nose",
				dia * 0.22,
				vadd(vadd(center, vmul(at.n, depth * 0.45)), v3(side * dia * 0.18, 0, 0)),
				nose,
				"face"
			)
		end
		-- the mouth goes on the face just under the snout
		local mb = dia * 0.4
		rig.muzzle = {
			cx = h.cx,
			cy = at.p.y - dia * 0.66 + 0.42 * mb,
			cz = h.cz,
			a = dia * 0.5,
			b = mb,
			c = h.c,
			color = h.color,
			solids = h.solids,
		}
		return
	end
	-- dog / bear / cat: a muzzle the mouth goes on, and a nose on top of it
	local k = if style == "cat" then 0.75 else 1
	local size = v3(h.a * 0.66 * sc * k, h.b * 0.46 * sc * k, h.c * 0.5 * sc * k)
	local center = vadd(at.p, v3(0, 0, -size.z * 0.12))
	local muzzle = newHull(center.x, center.y, center.z, size.x, size.y, size.z, color)
	if style == "cat" then
		for _, side in { -1, 1 } do
			local c = vadd(center, v3(side * size.x * 0.24, 0, 0))
			ellipsoid(ctx, "Feature", v3(size.x * 0.56, size.y * 0.8, size.z), c, IDENT, color, "body", fx(f))
			addSolid(muzzle, "ellipsoid", c, v3(size.x * 0.28, size.y * 0.4, size.z / 2))
		end
	else
		ellipsoid(ctx, "Feature", size, center, IDENT, color, "body", fx(f))
		addSolid(muzzle, "ellipsoid", center, vmul(size, 0.5))
	end
	local nosePoint = frontAt(muzzle, 0, size.y * 0.22)
	ball(ctx, "Nose", h.a * 0.22 * sc * k, vadd(nosePoint, v3(0, 0, -h.a * 0.04)), nose, "face")
	rig.muzzle = muzzle
end

FEATURES.whiskers = function(ctx, rig, f)
	local h = rig.face
	local color = f.color or "#3A2A2E"
	local m = rig.muzzle
	local anchor = if m then v3(m.cx, m.cy, m.cz - m.c * 0.5) else faceAt(h, 0, -h.b * 0.3).p
	local width = if m then m.a else h.a * 0.3
	for _, side in { -1, 1 } do
		for _, dy in { -0.05, 0.12 } do
			local start = vadd(anchor, v3(side * width * 0.85, dy * h.b, 0))
			local finish = vadd(start, v3(side * h.a * 0.55, dy * h.b * 1.2, h.c * 0.1))
			segment(ctx, "Feature", start, finish, math.max(h.a * 0.035, MIN_SIZE), color, "detail")
		end
	end
end

FEATURES.spikes = function(ctx, rig, f)
	local h = target(rig, f.on, "body")
	local count = math.clamp(f.n or 4, 1, 12)
	local sc = f.scale or 1
	local color = f.color or "#FFFFFF"
	local colors = { color, f.color2 or color }
	-- along the ridge from the top to the back (a head's start a little ahead of the top)
	local onHead = h == rig.face and h ~= rig.body
	-- a torso with a head on top (bipeds) only gets spikes down its back
	local head = rig.head
	local upright = not onHead and head ~= nil and head.cy > h.cy + h.b * 0.5
	local from = if onHead then math.rad(-12) elseif upright then math.rad(50) else math.rad(12)
	local to = if onHead then math.rad(70) elseif upright then math.rad(118) else math.rad(100)
	for i = 1, count do
		local phi = from + (to - from) * (if count == 1 then 0.3 else (i - 1) / (count - 1))
		local p, n = surfaceAt(h, v3(0, math.cos(phi) * h.b, math.sin(phi) * h.c))
		local size = v3(0.08 * rig.S * sc, 0.3 * rig.S * sc, 0.28 * rig.S * sc)
		local along = v3(0, -math.sin(phi), math.cos(phi))
		wedge(
			ctx,
			"Feature",
			size,
			vadd(p, vmul(n, size.y * 0.3)),
			frameYZ(n, along),
			colors[(i - 1) % 2 + 1],
			"body",
			fx(f)
		)
	end
end

FEATURES.fins = function(ctx, rig, f)
	local h = target(rig, f.on, "body")
	local S = rig.S * (f.scale or 1)
	local color = f.color or h.color
	local style = f.style or "all"
	if style ~= "dorsal" then
		for _, side in { -1, 1 } do
			local p = surfaceAt(h, v3(side, -0.1, -0.15))
			ellipsoid(
				ctx,
				"Feature",
				v3(0.42 * S, 0.08 * S, 0.26 * S),
				vadd(p, v3(side * 0.12 * S, -0.02 * S, 0.04 * S)),
				mmul(rz(-side * 0.5), ry(side * 0.4)),
				color,
				"body",
				fx(f)
			)
		end
	end
	if style ~= "side" then
		local p = topAt(h, 0, h.c * 0.1)
		local size = v3(0.08 * S, 0.42 * S, 0.44 * S)
		wedge(ctx, "Feature", size, vadd(p, v3(0, size.y * 0.32, 0)), IDENT, f.color2 or color, "body", fx(f))
	end
end

FEATURES.tusks = function(ctx, rig, f)
	local h = rig.face
	local color = f.color or "#FFF8E8"
	local sc = f.scale or 1
	for _, side in { -1, 1 } do
		local at = faceAt(h, side * h.a * 0.3, -h.b * 0.45)
		local d1 = vnorm(v3(side * 0.2, -0.55, -1))
		local c1 = vadd(at.p, vmul(d1, 0.16 * h.a * sc))
		ellipsoid(
			ctx,
			"Feature",
			v3(0.16 * h.a * sc, 0.16 * h.a * sc, 0.46 * h.a * sc),
			c1,
			aimZ(d1),
			color,
			"body",
			fx(f)
		)
		local d2 = vnorm(v3(side * 0.15, 0.7, -1))
		local c2 = vadd(vadd(c1, vmul(d1, 0.2 * h.a * sc)), vmul(d2, 0.16 * h.a * sc))
		ellipsoid(
			ctx,
			"Feature",
			v3(0.13 * h.a * sc, 0.13 * h.a * sc, 0.4 * h.a * sc),
			c2,
			aimZ(d2),
			color,
			"body",
			fx(f)
		)
	end
end

FEATURES.claws = function(ctx, rig, f)
	local h = target(rig, f.on, "body")
	local S = rig.S * (f.scale or 1)
	local color = f.color or h.color
	for _, side in { -1, 1 } do
		local root = surfaceAt(h, v3(side * 0.8, -0.1, -0.6))
		local elbow = vadd(root, v3(side * 0.18 * S, 0.06 * S, -0.16 * S))
		segment(ctx, "Feature", root, elbow, 0.14 * S, color, "body", fx(f))
		local hand = vadd(elbow, v3(side * 0.06 * S, 0.06 * S, -0.16 * S))
		ellipsoid(ctx, "Feature", v3(0.24 * S, 0.2 * S, 0.3 * S), hand, rx(0.35), f.color2 or color, "body", fx(f))
		ellipsoid(
			ctx,
			"Feature",
			v3(0.12 * S, 0.1 * S, 0.24 * S),
			vadd(hand, v3(0, -0.11 * S, -0.1 * S)),
			rx(-0.45),
			f.color2 or color,
			"body",
			fx(f)
		)
	end
end

FEATURES.legs = function(ctx, rig, f)
	local h = target(rig, f.on, "body")
	local count = math.clamp(f.n or 3, 1, 4)
	local color = f.color or rig.limb
	local S = rig.S * (f.scale or 1)
	for _, side in { -1, 1 } do
		for i = 1, count do
			local z = (if count == 1 then 0 else (i - 1) / (count - 1) - 0.5) * 1.1
			local start = surfaceAt(h, v3(side, -0.35, z))
			local knee = v3(start.x + side * 0.22 * S, math.max(start.y, 0.2 * S) + 0.06 * S, start.z + z * 0.08 * S)
			local foot = v3(knee.x + side * 0.12 * S, 0.03 * S, knee.z)
			segment(ctx, "Feature", start, knee, 0.08 * S, color, "body", fx(f))
			segment(ctx, "Feature", knee, foot, 0.07 * S, color, "body", fx(f))
		end
	end
end

FEATURES.belly = function(ctx, rig, f)
	local h = target(rig, f.on, "body")
	local sc = f.scale or 1
	local at = faceAt(h, 0, -h.b * 0.22)
	local size = v3(h.a * 1.3 * sc, h.b * 1.2 * sc, h.c * 0.6)
	ellipsoid(ctx, "Feature", size, vadd(at.p, vmul(at.n, -size.z * 0.38)), IDENT, f.color or "#FFF4E0", "body", fx(f))
	addSolid(h, "ellipsoid", vadd(at.p, vmul(at.n, -size.z * 0.38)), vmul(size, 0.5))
end

FEATURES.mask = function(ctx, rig, f)
	local h = rig.face
	local at = faceAt(h, 0, h.b * 0.12)
	local size = v3(h.a * 1.7, h.b * 0.62, h.c * 0.5)
	local center = vadd(at.p, v3(0, 0, size.z * 0.42))
	ellipsoid(ctx, "Feature", size, center, IDENT, f.color or "#4A4A55", "body", fx(f))
	addSolid(h, "ellipsoid", center, vmul(size, 0.5))
end

FEATURES.spots = function(ctx, rig, f)
	local h = target(rig, f.on, "body")
	local count = math.clamp(f.n or 5, 1, 14)
	local sc = f.scale or 1
	local colors = { f.color or "#6B3A12", f.color2 or f.color or "#6B3A12" }
	for i = 1, count do
		local y = 0.85 - 1.2 * (i - 0.5) / count
		local r = math.sqrt(math.max(1 - y * y, 0))
		local theta = i * 2.39996 + 0.6
		local dir = v3(r * math.cos(theta), y, r * math.sin(theta))
		if rig.face == h and dir.z < -0.4 and math.abs(dir.x) < 0.75 then
			dir = v3(dir.x, dir.y, -dir.z)
		end
		local p, n = surfaceAt(h, dir)
		local d = (0.26 + 0.12 * hash(i, 2)) * math.min(h.a, h.c) * sc
		ellipsoid(ctx, "Feature", v3(d, d * 0.2, d * 0.85), p, aimY(n), colors[(i - 1) % 2 + 1], "detail", fx(f))
	end
end

FEATURES.stripes = function(ctx, rig, f)
	local h = target(rig, f.on, "body")
	local style = f.style or "rings"
	local color = f.color or "#2E2A30"
	local count = math.clamp(f.n or 3, 1, 8)
	local thin = 0.08 * rig.S * (f.scale or 1)
	if style == "back" then
		local size = v3(h.a * 0.62 * (f.scale or 1), h.b * 0.5, h.c * 2.04)
		ellipsoid(ctx, "Feature", size, v3(h.cx, h.cy + h.b * 0.76, h.cz), IDENT, color, "body", fx(f))
		return
	end
	local first = h.solids[1]
	local kind = if first then first.kind else "ellipsoid"
	local axis = if first then first.axis or 2 else 2
	local lip = 1.035
	for i = 1, count do
		local k = (i - 0.5) / count * 1.3 - 0.65
		if style == "bands" then
			-- horizontal rings around a standing shape
			local y = h.cy + k * h.b
			if kind == "box" then
				box(
					ctx,
					"Feature",
					v3(h.a * 2 * lip, thin, h.c * 2 * lip),
					v3(h.cx, y, h.cz),
					IDENT,
					color,
					"detail",
					fx(f)
				)
			elseif kind == "cyl" and axis == 2 then
				cylinder(ctx, "Feature", thin, h.a * 2 * lip, v3(h.cx, y, h.cz), VERTICAL, color, "detail", fx(f))
			else
				local r = math.sqrt(math.max(1 - k * k, 0.05))
				ellipsoid(
					ctx,
					"Feature",
					v3(h.a * 2 * r * lip, thin, h.c * 2 * r * lip),
					v3(h.cx, y, h.cz),
					IDENT,
					color,
					"detail",
					fx(f)
				)
			end
		else
			-- rings around a long body, from the middle to the back (so they don't frame the face)
			local z = h.cz + (k * 0.8 + 0.3) * h.c
			if kind == "box" then
				box(
					ctx,
					"Feature",
					v3(h.a * 2 * lip, h.b * 2 * lip, thin),
					v3(h.cx, h.cy, z),
					IDENT,
					color,
					"detail",
					fx(f)
				)
			elseif kind == "cyl" and axis == 3 then
				cylinder(ctx, "Feature", thin, h.a * 2 * lip, v3(h.cx, h.cy, z), ALONG_Z, color, "detail", fx(f))
			else
				local zz = math.clamp((z - h.cz) / h.c, -0.95, 0.95)
				local r = math.sqrt(1 - zz * zz)
				ellipsoid(
					ctx,
					"Feature",
					v3(h.a * 2 * r * lip, h.b * 2 * r * lip, thin),
					v3(h.cx, h.cy + h.b * 0.03, z),
					IDENT,
					color,
					"detail",
					fx(f)
				)
			end
		end
	end
end

FEATURES.fan = function(ctx, rig, f)
	local count = math.clamp(f.n or 5, 3, 9)
	local S = rig.S * (f.scale or 1)
	local t = rig.tail
	local colors = { f.color or "#2FB59C", f.color3 or f.color or "#2FB59C" }
	for i = 1, count do
		local theta = ((i - 1) / (count - 1) - 0.5) * math.rad(150)
		local dir = v3(math.sin(theta), math.cos(theta), 0.18)
		local center = vadd(t, vadd(vmul(dir, 0.48 * S), v3(0, 0.05 * S, 0.12 * S)))
		ellipsoid(
			ctx,
			"Feature",
			v3(0.3 * S, 0.9 * S, 0.08 * S),
			center,
			rz(-theta),
			colors[(i - 1) % 2 + 1],
			"body",
			fx(f)
		)
		if f.color2 then
			local eye = vadd(t, vadd(vmul(dir, 0.78 * S), v3(0, 0.05 * S, 0.06 * S)))
			ball(ctx, "Feature", 0.16 * S, eye, f.color2, "detail")
		end
	end
end

FEATURES.crest = function(ctx, rig, f)
	local h = target(rig, f.on, "head")
	local count = math.clamp(f.n or 3, 1, 6)
	local sc = f.scale or 1
	local colors = { f.color or "#FF5A3C", f.color2 or f.color or "#FF5A3C" }
	for i = 1, count do
		local w = -0.25 + (i - 1) * 0.28
		local p = topAt(h, 0, w * h.c)
		local dir = vnorm(v3(0, 1, 0.35 + i * 0.3))
		ellipsoid(
			ctx,
			"Feature",
			v3(0.16 * h.a * sc, 0.62 * h.a * sc * (1 - (i - 1) * 0.12), 0.3 * h.a * sc),
			vadd(p, vmul(dir, 0.2 * h.a * sc)),
			aimY(dir),
			colors[(i - 1) % 2 + 1],
			"body",
			fx(f)
		)
	end
end

FEATURES.heads = function(ctx, rig, f)
	local main = rig.head or rig.face
	local body = rig.body
	local count = math.clamp(f.n or 2, 1, 2)
	local color = f.color or main.color
	local sc = f.scale or 0.8
	for i = 1, count do
		local side = if i == 1 then -1 else 1
		local base = v3(body.cx + side * body.a * 0.45, body.cy + body.b * 0.6, body.cz - body.c * 0.1)
		local center = v3(main.cx + side * main.a * 1.55, main.cy - main.b * 0.25, main.cz + main.c * 0.25)
		segment(ctx, "Feature", base, center, 0.24 * rig.S, color, "body", fx(f))
		local size = v3(main.a * 2 * sc, main.b * 2 * sc, main.c * 2 * sc)
		ellipsoid(ctx, "Feature", size, center, IDENT, color, "body", fx(f))
		local mini = newHull(center.x, center.y, center.z, size.x, size.y, size.z, color)
		addSolid(mini, "ellipsoid", center, vmul(size, 0.5))
		local e = math.min(mini.a, mini.b) * 0.58
		for _, eyeSide in { -1, 1 } do
			local at = faceAt(mini, eyeSide * mini.a * 0.38 + side * mini.a * 0.12, mini.b * 0.12)
			local sclera = vadd(at.p, vmul(at.n, e * 0.12))
			ball(ctx, "Eye", e, sclera, SCLERA, "face")
			ball(ctx, "Pupil", e * 0.58, vadd(sclera, vmul(at.n, e * 0.31)), PUPIL, "face")
		end
	end
end

FEATURES.straw = function(ctx, rig, f)
	local h = target(rig, f.on, "body")
	local S = rig.S * (f.scale or 1)
	local p = topAt(h, h.a * 0.3, h.c * 0.2)
	local dir = vnorm(v3(0.35, 1, 0.25))
	local len = 0.8 * S
	segment(
		ctx,
		"Feature",
		vsub(p, vmul(dir, 0.15 * S)),
		vadd(p, vmul(dir, len)),
		0.12 * S,
		f.color or "#FF5F8F",
		"detail"
	)
	if f.color2 then
		local at = vadd(p, vmul(dir, len * 0.55))
		cylinder(ctx, "Feature", 0.1 * S, 0.135 * S, at, aimX(dir), f.color2, "detail")
	end
end

FEATURES.bubble = function(ctx, rig, f)
	local mouth = rig.mouth or faceAt(rig.face, 0, -rig.face.b * 0.3).p
	local n = rig.mouthNormal or v3(0, 0, -1)
	local d = 0.5 * rig.S * (f.scale or 1)
	ball(ctx, "Feature", d, vadd(mouth, vadd(vmul(n, d * 0.42), v3(0, -d * 0.08, 0))), f.color or "#FF8FCF", "detail", {
		transparency = 0.25,
		material = f.material,
	})
end

FEATURES.flame = function(ctx, rig, f)
	local h = target(rig, f.on, "head")
	local count = math.clamp(f.n or 3, 1, 7)
	local sc = f.scale or 1
	local colors = { f.color or "#FF7A1A", f.color2 or "#FFD23F", f.color3 or "#FF4A2A" }
	for i = 1, count do
		local x = if count == 1 then 0 else ((i - 1) / (count - 1) - 0.5) * 1.1
		local p = topAt(h, x * h.a * 0.7, h.c * 0.15)
		local tall = (0.7 - math.abs(x) * 0.35) * rig.S * sc
		local dir = vnorm(v3(x * 0.5, 1, 0.3))
		ellipsoid(
			ctx,
			"Feature",
			v3(0.2 * rig.S * sc, tall, 0.2 * rig.S * sc),
			vadd(p, vmul(dir, tall * 0.4)),
			aimY(dir),
			colors[(i - 1) % 3 + 1],
			"detail",
			{ material = f.material or "Neon" }
		)
	end
end

FEATURES.bow = function(ctx, rig, f)
	local h = target(rig, f.on, "head")
	local sc = f.scale or 1
	local color = f.color or "#FF5FA2"
	local p = surfaceAt(h, v3(0.5, 0.9, -0.1))
	local s = h.a * sc
	for _, side in { -1, 1 } do
		ellipsoid(
			ctx,
			"Feature",
			v3(0.4 * s, 0.3 * s, 0.14 * s),
			vadd(p, v3(side * 0.2 * s, 0.05 * s, 0)),
			rz(side * 0.35),
			color,
			"detail"
		)
	end
	ball(ctx, "Feature", 0.16 * s, vadd(p, v3(0, 0.05 * s, -0.03 * s)), f.color2 or color, "detail")
end

FEATURES.teeth = function(ctx, rig, f)
	local mouth = rig.mouth or faceAt(rig.face, 0, -rig.face.b * 0.3).p
	local n = rig.mouthNormal or v3(0, 0, -1)
	local s = rig.face.a * (f.scale or 1)
	for _, side in { -1, 1 } do
		box(
			ctx,
			"Teeth",
			v3(0.13 * s, 0.2 * s, 0.06 * s),
			vadd(mouth, vadd(vmul(n, 0.03 * s), v3(side * 0.07 * s, -0.1 * s, 0))),
			aimZ(n),
			f.color or TEETH,
			"face"
		)
	end
end

FEATURES.segments = function(ctx, rig, f)
	local body = rig.body
	local count = math.clamp(f.n or 3, 1, 6)
	local colors = { f.color or body.color, f.color2 or f.color or body.color, f.color3 or f.color or body.color }
	local z = body.cz + body.c * 0.55
	local k = 1
	for i = 1, count do
		k *= 0.86
		local size = v3(body.a * 2 * k, body.b * 2 * k, body.c * 2 * k * 0.9)
		z += size.z * 0.62
		local center = v3(body.cx, size.y / 2 + 0.02 * rig.S, z)
		ellipsoid(ctx, "Feature", size, center, IDENT, colors[(i - 1) % 3 + 1], "body", fx(f))
		rig.tail = v3(center.x, center.y, center.z + size.z / 2)
	end
end

FEATURES.sides = function(ctx, rig, f)
	local body = target(rig, f.on, "body")
	local sc = f.scale or 1
	for _, side in { -1, 1 } do
		ellipsoid(
			ctx,
			"Feature",
			v3(body.a * 0.95 * sc, body.b * 1.35 * sc, body.c * 2.06),
			v3(body.cx + side * body.a * 0.88, body.cy - body.b * 0.28, body.cz),
			IDENT,
			f.color or "#F2C27A",
			"body",
			{ material = f.material, shadow = true }
		)
	end
end

FEATURES.handle = function(ctx, rig, f)
	local body = target(rig, f.on, "body")
	local sc = f.scale or 1
	local color = f.color or body.color
	local top = surfaceAt(body, v3(1, 0.42, 0.2))
	local bottom = surfaceAt(body, v3(1, -0.32, 0.2))
	local reach = body.a * 0.42 * sc
	local p2 = vadd(top, v3(reach, body.b * 0.04, 0))
	local p3 = vadd(bottom, v3(reach, -body.b * 0.04, 0))
	local thick = body.a * 0.2 * sc
	segment(ctx, "Feature", vsub(top, v3(thick * 0.4, 0, 0)), p2, thick, color, "body", fx(f))
	segment(ctx, "Feature", p2, p3, thick, color, "body", fx(f))
	segment(ctx, "Feature", p3, vsub(bottom, v3(thick * 0.4, 0, 0)), thick, color, "body", fx(f))
end

FEATURES.slip = function(ctx, rig, f)
	local body = target(rig, f.on, "body")
	local S = rig.S * (f.scale or 1)
	local p, n = surfaceAt(body, v3(1, 0.15, 0.25))
	local rot = mmul(aimX(vadd(n, v3(0, 0.25, 0.2))), rx(0.15))
	local center = vadd(p, vmul(n, 0.16 * S))
	box(ctx, "Feature", v3(0.56 * S, 0.17 * S, 0.025 * S), center, rot, f.color or "#FFFFFF", "detail")
	box(ctx, "Feature", v3(0.34 * S, 0.035 * S, 0.035 * S), center, rot, f.color2 or "#E8433A", "detail")
end

-- Toppings: which snack it is -------------------------------------------------------------------------------------------

type ToppingFn = (ctx: Ctx, rig: Rig, t: LookTopping, hull: Hull, key: string) -> ()
local TOPPINGS: { [string]: ToppingFn } = {}

local function pick(t: LookTopping, i: number): string
	return t.colors[(i - 1) % #t.colors + 1]
end

local function tx(t: LookTopping): Extra
	return { material = t.material }
end

-- Golden-angle scatter over the top of a hull: position, normal, index.
local function scatter(hull: Hull, t: LookTopping, defaultCount: number, defaultSpread: number): { FacePoint }
	local count = math.clamp(t.n or defaultCount, 1, 16)
	local spread = math.clamp(t.spread or defaultSpread, 0, 1)
	local points: { FacePoint } = {}
	local front = t.style == "front"
	for i = 1, count do
		local theta = i * 2.39996 + 0.4
		if front then
			-- a ring on the front face (an upright donut: around the hole)
			local r = 0.45 + (spread - 0.45) * math.sqrt((i - 0.5) / count)
			local p, n = frontAt(hull, math.cos(theta) * r * hull.a, math.sin(theta) * r * hull.b)
			table.insert(points, { p = p, n = n })
		else
			local r = spread * math.sqrt((i - 0.5) / count)
			local p, n = topAt(hull, math.cos(theta) * r * hull.a, math.sin(theta) * r * hull.c)
			table.insert(points, { p = p, n = n })
		end
	end
	return points
end

TOPPINGS.sprinkles = function(ctx, rig, t, hull)
	local sc = t.scale or 1
	for i, at in scatter(hull, t, 8, 0.7) do
		local len = 0.2 * rig.S * sc
		local rot = mmul(aimY(at.n), mmul(ry(i * 1.7), rz(math.pi / 2)))
		cylinder(
			ctx,
			"Topping",
			len,
			0.06 * rig.S * sc,
			vadd(at.p, vmul(at.n, 0.02 * rig.S)),
			rot,
			pick(t, i),
			"detail",
			tx(t)
		)
	end
end

TOPPINGS.seeds = function(ctx, rig, t, hull)
	local sc = t.scale or 1
	for i, at in scatter(hull, t, 7, 0.7) do
		ellipsoid(
			ctx,
			"Topping",
			v3(0.07 * rig.S * sc, 0.045 * rig.S * sc, 0.12 * rig.S * sc),
			at.p,
			mmul(aimY(at.n), ry(i * 1.3)),
			pick(t, i),
			"detail",
			tx(t)
		)
	end
end

TOPPINGS.chips = function(ctx, rig, t, hull)
	local sc = t.scale or 1
	for i, at in scatter(hull, t, 5, 0.75) do
		local d = 0.14 * rig.S * sc
		ellipsoid(
			ctx,
			"Topping",
			v3(d, d * 0.7, d),
			vadd(at.p, vmul(at.n, d * 0.05)),
			aimY(at.n),
			pick(t, i),
			"detail",
			tx(t)
		)
	end
end

TOPPINGS.discs = function(ctx, rig, t, hull)
	local sc = t.scale or 1
	for i, at in scatter(hull, t, 3, 0.6) do
		local d = 0.26 * rig.S * sc
		cylinder(
			ctx,
			"Topping",
			0.05 * rig.S,
			d,
			vadd(at.p, vmul(at.n, 0.01 * rig.S)),
			aimX(at.n),
			pick(t, i),
			"detail",
			tx(t)
		)
	end
end

TOPPINGS.balls = function(ctx, rig, t, hull)
	local sc = t.scale or 1
	for i, at in scatter(hull, t, 4, 0.6) do
		local d = 0.16 * rig.S * sc
		ball(ctx, "Topping", d, vadd(at.p, vmul(at.n, d * 0.25)), pick(t, i), "detail", tx(t))
	end
end

TOPPINGS.crumbs = function(ctx, rig, t, hull)
	local sc = t.scale or 1
	for i, at in scatter(hull, t, 6, 0.75) do
		local d = 0.07 * rig.S * sc
		box(
			ctx,
			"Topping",
			v3(d, d, d),
			vadd(at.p, vmul(at.n, d * 0.2)),
			mmul(ry(i), rx(i * 0.7)),
			pick(t, i),
			"detail",
			tx(t)
		)
	end
end

TOPPINGS.spikes = function(ctx, rig, t, hull)
	local sc = t.scale or 1
	local count = math.clamp(t.n or 8, 1, 16)
	for i = 1, count do
		local y = 0.9 - 1.3 * (i - 0.5) / count
		local r = math.sqrt(math.max(1 - y * y, 0))
		local theta = i * 2.39996
		local dir = v3(r * math.cos(theta), y, r * math.sin(theta))
		if hull == rig.face and dir.z < -0.35 and math.abs(dir.x) < 0.8 and dir.y < 0.75 then
			dir = v3(dir.x, dir.y, -dir.z)
		end
		local p, n = surfaceAt(hull, dir)
		local len = 0.2 * rig.S * sc
		ellipsoid(
			ctx,
			"Topping",
			v3(len * 0.45, len, len * 0.45),
			vadd(p, vmul(n, len * 0.3)),
			aimY(n),
			pick(t, i),
			"detail",
			tx(t)
		)
	end
end

TOPPINGS.cap = function(ctx, _rig, t, hull)
	local color = pick(t, 1)
	local sc = t.scale or 1
	local solid = hull.solids[1]
	if solid == nil then
		return
	end
	-- Fit the cap to the highest solid (the top of the shape).
	for _, s in hull.solids do
		if s.cy + s.ry > solid.cy + solid.ry then
			solid = s
		end
	end
	if solid.kind == "ellipsoid" then
		local size = v3(solid.rx * 2.06, solid.ry * 1.1 * sc, solid.rz * 2.06)
		local center = v3(solid.cx, solid.cy + solid.ry * 0.5, solid.cz)
		ellipsoid(ctx, "Topping", size, center, IDENT, color, "body", tx(t))
		addSolid(hull, "ellipsoid", center, vmul(size, 0.5))
	elseif solid.kind == "cyl" and (solid.axis or 2) ~= 2 then
		-- a lying cylinder: drape it over the top
		local long = solid.axis == 3
		local size =
			v3(solid.rx * (if long then 2.1 else 1.96), solid.ry * 1.05 * sc, solid.rz * (if long then 1.96 else 2.1))
		local center = v3(solid.cx, solid.cy + solid.ry * 0.5, solid.cz)
		ellipsoid(ctx, "Topping", size, center, IDENT, color, "body", tx(t))
		addSolid(hull, "ellipsoid", center, vmul(size, 0.5))
	elseif solid.kind == "cyl" then
		local height = solid.ry * 0.5 * sc
		local center = v3(solid.cx, solid.cy + solid.ry - height / 2 + solid.ry * 0.04, solid.cz)
		cylinder(ctx, "Topping", height, solid.rx * 2.08, center, VERTICAL, color, "body", tx(t))
		addSolid(hull, "cyl", center, v3(solid.rx * 1.04, height / 2, solid.rz * 1.04), 2)
	else
		local height = solid.ry * 0.4 * sc
		local center = v3(solid.cx, solid.cy + solid.ry - height / 2 + solid.ry * 0.04, solid.cz)
		box(ctx, "Topping", v3(solid.rx * 2.06, height, solid.rz * 2.06), center, IDENT, color, "body", tx(t))
		addSolid(hull, "box", center, v3(solid.rx * 1.03, height / 2, solid.rz * 1.03))
	end
end

TOPPINGS.drips = function(ctx, rig, t, hull)
	local count = math.clamp(t.n or 5, 1, 12)
	local sc = t.scale or 1
	local y = hull.cy + (t.at or 0.35) * hull.b
	local isFace = hull == rig.face
	local placed = 0
	for i = 0, count * 2 do
		if placed >= count then
			break
		end
		local theta = (i + 0.5) / count * math.pi * 2 + 0.3
		local wrapped = math.atan2(math.sin(theta), math.cos(theta))
		if not (isFace and math.abs(wrapped) < 0.85) then
			placed += 1
			local p, n = sideAt(hull, theta, y)
			local long = (0.3 + 0.14 * hash(i, 4)) * rig.S * sc
			local down = downAlong(n)
			ellipsoid(
				ctx,
				"Topping",
				v3(0.15 * rig.S * sc, long, 0.1 * rig.S * sc),
				vadd(vadd(p, vmul(down, long * 0.3)), vmul(n, 0.015 * rig.S)),
				frameYZ(down, n),
				pick(t, placed),
				"body",
				tx(t)
			)
		end
	end
end

-- Noodles hanging over the edge: two short wavy segments each.
TOPPINGS.strands = function(ctx, rig, t, hull)
	local count = math.clamp(t.n or 6, 1, 10)
	local sc = t.scale or 1
	local y = hull.cy + (t.at or 0.6) * hull.b
	local isFace = hull == rig.face
	local placed = 0
	local thick = 0.075 * rig.S * sc
	for i = 0, count * 2 do
		if placed >= count then
			break
		end
		local theta = (i + 0.5) / count * math.pi * 2
		local wrapped = math.atan2(math.sin(theta), math.cos(theta))
		if not (isFace and math.abs(wrapped) < 0.75) then
			placed += 1
			local p, n = sideAt(hull, theta, y)
			local out = vnorm(v3(n.x, 0, n.z))
			local long = (0.2 + 0.08 * hash(i, 6)) * rig.S * sc
			local start = vadd(p, v3(0, thick * 0.5, 0))
			local bend = vadd(vadd(start, vmul(out, thick * 1.2)), v3(0, -long, 0))
			local finish = vadd(vadd(bend, vmul(out, -thick * 0.6)), v3(0, -long * 0.9, 0))
			segment(ctx, "Topping", start, bend, thick, pick(t, placed), "body", tx(t))
			segment(ctx, "Topping", bend, finish, thick, pick(t, placed), "body", tx(t))
		end
	end
end

TOPPINGS.swirl = function(ctx, rig, t, hull, key)
	local sc = t.scale or 1
	local count = math.clamp(t.n or 3, 1, 5)
	local base = rig.summit[key] or topAt(hull, 0, 0)
	local width = math.min(hull.a, hull.c) * 1.5 * sc
	local y = base.y
	local p = base
	for i = 1, count do
		local k = 1 - (i - 1) / count * 0.62
		local h = width * 0.42 * k
		p = v3(base.x, y + h * 0.36, base.z)
		ellipsoid(ctx, "Topping", v3(width * k, h, width * k), p, ry(i * 0.9), pick(t, i), "body", tx(t))
		y += h * 0.62
	end
	local summit = v3(base.x, y + width * 0.08, base.z)
	rig.summit[key] = summit
end

TOPPINGS.cherry = function(ctx, rig, t, hull, key)
	local sc = t.scale or 1
	local base = rig.summit[key] or topAt(hull, 0, 0)
	local d = 0.3 * rig.S * sc
	local center = vadd(base, v3(0, d * 0.4, 0))
	ball(ctx, "Topping", d, center, pick(t, 1), "body", tx(t))
	segment(
		ctx,
		"Topping",
		vadd(center, v3(0, d * 0.4, 0)),
		vadd(center, v3(d * 0.35, d * 1.05, 0)),
		0.05 * rig.S,
		t.colors[2] or "#4A7A2A",
		"detail"
	)
	rig.summit[key] = vadd(center, v3(0, d * 0.5, 0))
end

TOPPINGS.leaf = function(ctx, rig, t, hull, key)
	local sc = t.scale or 1
	local base = rig.summit[key] or topAt(hull, 0, 0)
	local stem = vadd(base, v3(0, 0.14 * rig.S * sc, 0))
	segment(
		ctx,
		"Topping",
		vsub(base, v3(0, 0.05 * rig.S, 0)),
		stem,
		0.09 * rig.S * sc,
		t.colors[2] or "#7A4A22",
		"detail"
	)
	ellipsoid(
		ctx,
		"Topping",
		v3(0.36 * rig.S * sc, 0.06 * rig.S * sc, 0.2 * rig.S * sc),
		vadd(stem, v3(0.16 * rig.S * sc, 0, 0)),
		rz(0.35),
		pick(t, 1),
		"detail",
		tx(t)
	)
	rig.summit[key] = stem
end

TOPPINGS.band = function(ctx, _rig, t, hull)
	local at = t.at or 0
	local thick = (t.scale or 1) * hull.b * 0.5
	local y = hull.cy + at * hull.b
	local s = hull.solids[1]
	if s and s.kind == "cyl" and (s.axis or 2) == 3 then
		-- a roll: the band wraps around it at depth `at`
		local z = hull.cz + at * hull.c
		cylinder(ctx, "Topping", thick, s.rx * 2.06, v3(hull.cx, hull.cy, z), ALONG_Z, pick(t, 1), "body", tx(t))
		return
	end
	local kk = math.clamp(at, -0.95, 0.95)
	local r = if s and s.kind ~= "ellipsoid" then 1 else math.sqrt(1 - kk * kk)
	if s and s.kind == "cyl" then
		cylinder(ctx, "Topping", thick, hull.a * 2 * 1.05, v3(hull.cx, y, hull.cz), VERTICAL, pick(t, 1), "body", tx(t))
	elseif s and s.kind == "box" then
		box(
			ctx,
			"Topping",
			v3(hull.a * 2.05, thick, hull.c * 2.05),
			v3(hull.cx, y, hull.cz),
			IDENT,
			pick(t, 1),
			"body",
			tx(t)
		)
	else
		ellipsoid(
			ctx,
			"Topping",
			v3(hull.a * 2 * r * 1.06, thick, hull.c * 2 * r * 1.06),
			v3(hull.cx, y, hull.cz),
			IDENT,
			pick(t, 1),
			"body",
			tx(t)
		)
	end
end

TOPPINGS.sticks = function(ctx, rig, t, hull)
	local sc = t.scale or 1
	for i, at in scatter(hull, t, 6, 0.65) do
		local tall = (0.45 + 0.2 * hash(i, 8)) * rig.S * sc
		local dir = vnorm(vadd(v3(0, 1, 0), v3((hash(i, 1) - 0.5) * 0.5, 0, (hash(i, 2) - 0.5) * 0.5)))
		box(
			ctx,
			"Topping",
			v3(0.1 * rig.S * sc, tall, 0.1 * rig.S * sc),
			vadd(at.p, vmul(dir, tall * 0.3)),
			aimY(dir),
			pick(t, i),
			"body",
			tx(t)
		)
	end
end

TOPPINGS.egg = function(ctx, rig, t, hull)
	local sc = t.scale or 1
	local p, n = topAt(hull, hull.a * 0.35, -hull.c * 0.1)
	local size = v3(0.42 * rig.S * sc, 0.16 * rig.S * sc, 0.3 * rig.S * sc)
	ellipsoid(
		ctx,
		"Topping",
		size,
		vadd(p, vmul(n, size.y * 0.25)),
		mmul(aimY(n), ry(0.4)),
		t.colors[1] or "#FFFFFF",
		"detail"
	)
	ball(ctx, "Topping", 0.17 * rig.S * sc, vadd(p, vmul(n, size.y * 0.5)), t.colors[2] or "#FFB72B", "detail")
end

TOPPINGS.swirlmark = function(ctx, rig, t, hull)
	local sc = t.scale or 1
	local p, n = topAt(hull, -hull.a * 0.35, hull.c * 0.15)
	local d = 0.32 * rig.S * sc
	cylinder(
		ctx,
		"Topping",
		0.05 * rig.S,
		d,
		vadd(p, vmul(n, 0.02 * rig.S)),
		aimX(n),
		t.colors[1] or "#FFFFFF",
		"detail"
	)
	cylinder(
		ctx,
		"Topping",
		0.07 * rig.S,
		d * 0.45,
		vadd(p, vmul(n, 0.03 * rig.S)),
		aimX(n),
		t.colors[2] or "#FF7AA8",
		"detail"
	)
end

TOPPINGS.zigzag = function(ctx, rig, t, hull)
	local count = math.clamp(t.n or 4, 1, 8)
	local sc = t.scale or 1
	local points: { V } = {}
	for i = 0, count do
		local z = (i / count - 0.5) * 1.5 * hull.c
		local x = (if i % 2 == 0 then -1 else 1) * hull.a * 0.35
		local p, n = topAt(hull, x, z)
		table.insert(points, vadd(p, vmul(n, 0.03 * rig.S)))
	end
	for i = 1, count do
		segment(ctx, "Topping", points[i], points[i + 1], 0.08 * rig.S * sc, pick(t, i), "detail", tx(t))
	end
end

TOPPINGS.bits = function(ctx, rig, t, hull)
	local count = math.clamp(t.n or 6, 1, 14)
	local sc = t.scale or 1
	local ridge = t.style == "ridge"
	for i = 1, count do
		local p: V
		local n: V
		if ridge then
			local z = ((i - 0.5) / count - 0.5) * 1.5 * hull.c
			p, n = topAt(hull, (hash(i, 3) - 0.5) * hull.a * 0.25, z)
		else
			local theta = (i - 0.5) / count * math.pi * 2
			p, n = surfaceAt(hull, v3(math.sin(theta), t.at or 0.55, -math.cos(theta)))
		end
		local size = (0.18 + 0.08 * hash(i, 5)) * rig.S * sc
		ellipsoid(
			ctx,
			"Topping",
			v3(size, size * 0.6, size * 0.8),
			vadd(p, vmul(n, size * 0.15)),
			mmul(aimY(n), ry(i * 1.1)),
			pick(t, i),
			"detail",
			tx(t)
		)
	end
end

TOPPINGS.pat = function(ctx, rig, t, hull, key)
	local sc = t.scale or 1
	local base = rig.summit[key]
	local n = v3(0, 1, 0)
	if base == nil then
		local p, normal = topAt(hull, 0, 0)
		base, n = p, normal
	end
	local size = v3(0.34 * rig.S * sc, 0.11 * rig.S * sc, 0.34 * rig.S * sc)
	local center = vadd(base :: V, vmul(n, size.y * 0.3))
	box(ctx, "Topping", size, center, mmul(aimY(n), ry(0.45)), pick(t, 1), "body", tx(t))
	rig.summit[key] = vadd(center, v3(0, size.y / 2, 0))
end

-- Compile ----------------------------------------------------------------------------------------------------------------

local PRE_FACE: { [string]: boolean } = { mask = true, snout = true, belly = true }

-- Vertical half extent of a part's oriented box.
local function halfHeight(part: PartSpec): number
	local c = part.cf
	local hx, hy, hz = part.size[1] / 2, part.size[2] / 2, part.size[3] / 2
	if part.shape == "Ball" then
		hy, hz = hx, hx
	end
	return math.abs(c[7]) * hx + math.abs(c[8]) * hy + math.abs(c[9]) * hz
end

local function extents(parts: { PartSpec }): (number, number, number, number)
	local minY, maxY, wide, wideX = math.huge, -math.huge, 0, 0
	for _, part in parts do
		local c = part.cf
		local hx, hy, hz = part.size[1] / 2, part.size[2] / 2, part.size[3] / 2
		if part.shape == "Ball" then
			hy, hz = hx, hx
		end
		-- axis-aligned bounds of the oriented box: |R| * half-size
		local ex = math.abs(c[4]) * hx + math.abs(c[5]) * hy + math.abs(c[6]) * hz
		local ey = math.abs(c[7]) * hx + math.abs(c[8]) * hy + math.abs(c[9]) * hz
		local ez = math.abs(c[10]) * hx + math.abs(c[11]) * hy + math.abs(c[12]) * hz
		minY = math.min(minY, c[2] - ey)
		maxY = math.max(maxY, c[2] + ey)
		wide = math.max(wide, math.abs(c[1]) + ex, math.abs(c[3]) + ez)
		wideX = math.max(wideX, math.abs(c[1]) + ex)
	end
	return minY, maxY, wide * 2, wideX * 2
end

-- Every part of a recipe at the given scale (the rarity's modelScale), in model space.
function CreatureRecipe.compile(look: CreatureLook, scale: number?): Compiled
	local S = look.size * (scale or 1)
	local ctx: Ctx = { parts = {} }
	local plan = PLANS[look.plan] or PLANS.blob
	local rig = plan(ctx, look, S)
	local features: { LookFeature } = look.features
	local toppings: { LookTopping } = look.toppings
	for _, feature in features do
		if PRE_FACE[feature.kind] then
			FEATURES[feature.kind](ctx, rig, feature)
		end
	end
	buildFace(ctx, rig, look.face)
	for _, feature in features do
		if not PRE_FACE[feature.kind] then
			local fn = FEATURES[feature.kind]
			if fn then
				fn(ctx, rig, feature)
			end
		end
	end
	for _, topping in toppings do
		local key = topping.on or (if rig.head then "head" else "body")
		local hull = rig.hulls[key] or rig.face
		local fn = TOPPINGS[topping.kind]
		if fn then
			fn(ctx, rig, topping, hull, key)
		end
	end
	-- Nothing goes below the feet: a tail tip, tentacle or drip that dips under y = 0 is raised onto the ground.
	for _, part in ctx.parts do
		local bottom = part.cf[2] - halfHeight(part)
		if bottom < 0 then
			part.cf[2] -= bottom
		end
	end
	local minY, maxY, footprint, width = extents(ctx.parts)
	return {
		parts = ctx.parts,
		minY = minY,
		maxY = maxY,
		width = width,
		footprint = footprint,
		base = math.max(rig.body.a, rig.body.c) * 2,
	}
end

-- Parts in the built model: the recipe's parts, the Root, and the aura ring Mythic and up get (CreatureVisuals).
function CreatureRecipe.partCount(look: CreatureLook, rarityOrder: number): number
	return #CreatureRecipe.compile(look, 1).parts + 1 + (if rarityOrder >= 6 then 1 else 0)
end

-- Problems with a recipe (an empty list means valid). `materials`: the Enum.Material names allowed.
function CreatureRecipe.validate(look: CreatureLook, materials: { string }): { string }
	local problems: { string } = {}
	local function problem(message: string)
		table.insert(problems, message)
	end
	local function color(label: string, value: string?)
		if value ~= nil and string.match(value, HEX_PATTERN) == nil then
			problem(`{label} colour {value} must be #RRGGBB`)
		end
	end
	local function material(label: string, value: string?)
		if value ~= nil and table.find(materials, value) == nil then
			problem(`{label} material {value} is not a known material`)
		end
	end
	local function positive(label: string, value: number?, max: number)
		if value ~= nil and not (value > 0 and value <= max) then
			problem(`{label} must be in (0, {max}]`)
		end
	end

	if PLANS[look.plan] == nil then
		problem(`unknown plan {look.plan}`)
	end
	positive("size", look.size, 10)
	positive("legs", look.legs, 2)
	positive("neck", look.neck, 2)
	color("limbs", look.limbs)
	local volumes: { [string]: LookVolume } = { body = look.body }
	if look.head then
		if look.plan ~= "biped" and look.plan ~= "quadruped" then
			problem(`plan {look.plan} has no separate head`)
		end
		volumes.head = look.head
	end
	for label, vol in volumes do
		if SKINS[vol.skin] == nil then
			problem(`{label}: unknown skin {vol.skin}`)
		end
		color(label, vol.color)
		color(label, vol.color2)
		color(label, vol.color3)
		material(label, vol.material)
		positive(`{label}.w`, vol.w, 3)
		positive(`{label}.h`, vol.h, 3)
		positive(`{label}.d`, vol.d, 3)
	end
	local face = look.face
	color("face.cheeks", face.cheeks)
	color("face.brows", face.brows)
	color("face.nose", face.nose)
	color("face.pupil", face.pupil)
	local eyes = { round = true, big = true, dot = true, happy = true, sleepy = true, stalk = true }
	if face.eyes and not eyes[face.eyes] then
		problem(`unknown eyes {face.eyes}`)
	end
	local mouths =
		{ smile = true, open = true, tongue = true, fang = true, o = true, cat = true, grin = true, none = true }
	if face.mouth and not mouths[face.mouth] then
		problem(`unknown mouth {face.mouth}`)
	end
	local features: { LookFeature } = look.features
	for i, feature in features do
		if FEATURES[feature.kind] == nil then
			problem(`feature {i}: unknown kind {feature.kind}`)
		end
		color(`feature {i}`, feature.color)
		color(`feature {i}`, feature.color2)
		color(`feature {i}`, feature.color3)
		material(`feature {i}`, feature.material)
		positive(`feature {i} scale`, feature.scale, 4)
	end
	local toppings: { LookTopping } = look.toppings
	for i, topping in toppings do
		if TOPPINGS[topping.kind] == nil then
			problem(`topping {i}: unknown kind {topping.kind}`)
		end
		if #topping.colors == 0 then
			problem(`topping {i} needs at least one colour`)
		end
		for _, value in topping.colors do
			color(`topping {i}`, value)
		end
		material(`topping {i}`, topping.material)
		positive(`topping {i} scale`, topping.scale, 4)
		if topping.on and topping.on ~= "body" and topping.on ~= "head" and topping.on ~= "shell" then
			problem(`topping {i}: unknown target {topping.on}`)
		end
	end
	return problems
end

-- Kinds a recipe may use (for docs and tests).
function CreatureRecipe.kinds(): { plans: { string }, skins: { string }, features: { string }, toppings: { string } }
	local function keys(t: { [string]: any }): { string }
		local list: { string } = {}
		for key in t do
			table.insert(list, key)
		end
		table.sort(list)
		return list
	end
	return { plans = keys(PLANS), skins = keys(SKINS), features = keys(FEATURES), toppings = keys(TOPPINGS) }
end

return CreatureRecipe
