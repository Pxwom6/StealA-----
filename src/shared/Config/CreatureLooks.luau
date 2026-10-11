--!strict
--[[
	How every Snackling looks: one model recipe per creature id (Config/Creatures). Plain data only.
	Logic/CreatureRecipe turns a recipe into parts (its header lists every plan, skin, face, feature and topping) and
	CreatureVisuals builds them in 3D; ReplicatedStorage.CreatureModels/<modelName> replaces a recipe with custom art.

	size      overall size in studs (the rarity's modelScale multiplies it: Commons ~2.6, Secrets ~4.4)
	plan      blob | biped | quadruped | swimmer | tentacled: how body, head, legs and face are arranged
	body      the food the body is made of: a skin + colours, optional w / h / d in units of `size`
	head      biped / quadruped head (default: a round head in the limb colour)
	face      eyes, mouth, cheeks, brows, nose...
	limbs     legs / feet / arms / tentacles colour
	features  what animal it is (ears, tail, wings, snout, horns...)
	toppings  what snack it is (sprinkles, drips, a cherry...)

	Faces look at -Z. CI (tests/CreatureRecipe.spec.luau) checks every creature has a valid recipe that stays inside its
	rarity's part budget (30 for Common / Uncommon, 40 for Rare / Epic, 50 for Legendary and up, Root included).
	Preview them all in Studio with the /gallery command.
]]

local Types = require("../Types")

export type CreatureLook = Types.CreatureLook

local CHEEKS = "#FF8FA8"
local SPRINKLES = { "#FF5FA2", "#5FC8FF", "#FFE45F", "#7CE05C", "#FFFFFF", "#B57BFF" }
local NOSE = "#3A2A2E"
local WHITE = "#FFFFFF"

local CreatureLooks: { [string]: CreatureLook } = {
	-- Common ------------------------------------------------------------------------------------------------------
	pizza_pup = {
		size = 3.3,
		plan = "quadruped",
		body = { skin = "slice", color = "#FFD34E", color3 = "#D98A3A", w = 0.82, h = 0.26, d = 1 },
		head = { skin = "round", color = "#F4BE7A" },
		face = { eyes = "round", mouth = "smile" },
		limbs = "#F4BE7A",
		features = {
			{ kind = "snout", style = "dog", color = "#FFE6C2", color2 = NOSE },
			{ kind = "ears", style = "floppy", color = "#C9782E" },
			{ kind = "tail", style = "thin", color = "#F4BE7A", color2 = "#C9782E" },
		},
		toppings = {
			{ kind = "discs", on = "body", colors = { "#D64933" }, n = 3, spread = 0.45 },
			{ kind = "drips", on = "body", colors = { "#FFD34E" }, n = 2, at = 0.3 },
		},
	},
	cookie_crab = {
		size = 3.3,
		plan = "blob",
		body = { skin = "round", color = "#E2A85C", w = 1, h = 0.44, d = 0.86 },
		face = { eyes = "round", mouth = "smile", height = 0.55, scale = 1.45, spacing = 0.3 },
		features = {
			{ kind = "claws", color = "#C98A45", color2 = "#E9B872" },
			{ kind = "legs", n = 2, color = "#B8783A" },
		},
		toppings = {
			{ kind = "chips", on = "body", colors = { "#4A2A16" }, n = 4, spread = 0.75 },
		},
	},
	marshmallow_mouse = {
		size = 2.5,
		plan = "blob",
		feet = true,
		body = { skin = "can", color = "#FFF8F0", w = 0.84, h = 0.82, d = 0.84 },
		face = { eyes = "round", mouth = "cat", cheeks = "#FF9FB8", nose = "#FF7FA0" },
		limbs = "#FFC2D1",
		features = {
			{ kind = "ears", style = "mouse", color = "#FFF8F0", color2 = "#FFC2D1" },
			{ kind = "whiskers", color = "#D8C0C0" },
			{ kind = "tail", style = "thin", color = "#FFC2D1" },
		},
		toppings = {
			{ kind = "cap", colors = { "#F2C48A" } },
		},
	},
	pretzel_pal = {
		size = 2.2,
		plan = "biped",
		body = { skin = "ring", style = "pretzel", color = "#A0602A", color3 = "#5E3414", w = 0.84, h = 0.66, d = 0.44 },
		head = { skin = "round", color = "#B8732E", w = 0.8, h = 0.66 },
		face = { eyes = "round", mouth = "grin", cheeks = "#FF9F7A" },
		limbs = "#A0602A",
		features = {},
		toppings = {
			{ kind = "crumbs", on = "head", colors = { WHITE }, n = 6, scale = 1.1 },
			{ kind = "crumbs", on = "body", style = "front", colors = { WHITE }, n = 4, scale = 1.1 },
		},
	},
	chip_chick = {
		size = 2.1,
		plan = "biped",
		arms = false,
		body = { skin = "round", color = "#FFD45C", w = 0.74, h = 0.56 },
		head = { skin = "round", color = "#FFDE6A", w = 0.8, h = 0.68 },
		face = { eyes = "round", mouth = "none", cheeks = "#FF9F7A" },
		limbs = "#FF9F2E",
		features = {
			{ kind = "snout", style = "beak", color = "#FF9F2E", color2 = "#E8782A" },
			{ kind = "wings", style = "tiny", color = "#F2B33D" },
			{ kind = "crest", n = 2, color = "#FFD45C", color2 = "#F2B33D" },
			{ kind = "spots", n = 4, color = "#E0A030" },
		},
		toppings = {
			{ kind = "crumbs", on = "head", colors = { WHITE }, n = 4 },
		},
	},
	cracker_quacker = {
		size = 2.5,
		plan = "biped",
		arms = false,
		body = { skin = "block", color = "#E8B25E", w = 0.8, h = 0.58, d = 0.52 },
		head = { skin = "round", color = "#FFE07A", w = 0.76, h = 0.64 },
		face = { eyes = "round", mouth = "none", cheeks = CHEEKS },
		limbs = "#FF9F2E",
		features = {
			{ kind = "snout", style = "bill", color = "#FF9F2E", color2 = "#E8782A" },
			{ kind = "wings", style = "tiny", color = "#E8B25E" },
			{ kind = "tail", style = "stub", color = "#E8B25E" },
		},
		toppings = {
			{ kind = "chips", on = "body", style = "front", colors = { "#C88A3C" }, n = 5, scale = 0.7, spread = 0.8 },
			{ kind = "crumbs", on = "body", colors = { WHITE }, n = 4 },
		},
	},
	gummy_grub = {
		size = 2.7,
		plan = "blob",
		feet = true,
		body = { skin = "round", color = "#7CDB4C", w = 0.78, h = 0.74, d = 0.7 },
		face = { eyes = "big", mouth = "smile", cheeks = "#FF7FAF" },
		limbs = "#5FC23A",
		features = {
			{ kind = "antennae", color = "#7CDB4C", color2 = "#FF5FA2" },
			{ kind = "segments", n = 3, color = "#FFE14D", color2 = "#FF9F2E", color3 = "#FF5A5A" },
		},
		toppings = {
			{ kind = "crumbs", on = "body", colors = { WHITE }, n = 5, spread = 0.8 },
		},
	},
	jellybean_jellyfish = {
		size = 3.05,
		plan = "tentacled",
		tentacles = 5,
		body = { skin = "round", color = "#FF6FAE", color2 = "#FFC2DE", w = 0.96, h = 0.72, d = 0.86 },
		face = { eyes = "big", mouth = "smile", cheeks = "#FF3F8F" },
		limbs = "#FF8FC2",
		features = {},
		toppings = {
			{ kind = "seeds", on = "body", colors = { WHITE, "#FFE45F" }, n = 6, spread = 0.75 },
		},
	},
	cheese_puff_puffer = {
		size = 2.45,
		plan = "swimmer",
		body = { skin = "lumpy", color = "#FF9A2E", color2 = "#FFB347", n = 5, w = 0.86, h = 0.8, d = 0.92 },
		face = { eyes = "big", mouth = "o", cheeks = "#FF6A6A" },
		limbs = "#FF9A2E",
		features = {
			{ kind = "fins", style = "dorsal", color = "#FFB347" },
			{ kind = "tail", style = "fin", color = "#FFB347" },
		},
		toppings = {
			{ kind = "spikes", on = "body", colors = { "#FFD07A" }, n = 4 },
			{ kind = "crumbs", on = "body", colors = { "#FFD07A" }, n = 3 },
		},
	},
	toast_toad = {
		size = 2.75,
		plan = "blob",
		feet = true,
		arms = true,
		body = { skin = "block", style = "toast", color = "#F7DFA8", color2 = "#C07A32", w = 1, h = 0.92, d = 0.42 },
		face = { eyes = "round", mouth = "smile", cheeks = "#FF9F8A", height = 0.6, scale = 1.25 },
		limbs = "#7CC35A",
		features = {},
		toppings = {
			{ kind = "pat", on = "body", colors = { "#FFE680" } },
			{ kind = "drips", on = "body", colors = { "#FFE680" }, n = 2, at = 0.7, scale = 0.8 },
		},
	},

	-- Uncommon ----------------------------------------------------------------------------------------------------
	sushi_slug = {
		size = 2.6,
		plan = "blob",
		body = { skin = "roll", color = "#FBF7EF", w = 0.72, h = 0.72, d = 1.25 },
		face = { eyes = "stalk", mouth = "smile", cheeks = CHEEKS },
		features = {},
		toppings = {
			{ kind = "cap", colors = { "#FF8A5B" } },
			{ kind = "band", colors = { "#22302A" }, at = 0.1, scale = 0.7 },
			{ kind = "seeds", colors = { WHITE }, n = 4, spread = 0.5 },
		},
	},
	fry_fox = {
		size = 2.55,
		plan = "quadruped",
		legs = 0.2,
		body = { skin = "block", color = "#E8403A", w = 0.66, h = 0.5, d = 0.84 },
		head = { skin = "round", color = "#F28A3C", w = 0.7, h = 0.6, d = 0.6 },
		face = { eyes = "round", mouth = "cat" },
		limbs = "#7A4A32",
		features = {
			{ kind = "snout", style = "dog", color = "#FFF1E0", color2 = NOSE },
			{ kind = "ears", style = "pointy", color = "#F28A3C" },
			{ kind = "tail", style = "fluffy", color = "#F28A3C", color2 = "#FFF1E0" },
		},
		toppings = {
			{ kind = "sticks", on = "body", colors = { "#FFD25A", "#FFC83D" }, n = 6, spread = 0.6 },
		},
	},
	pudding_pug = {
		size = 3.25,
		plan = "blob",
		feet = true,
		body = { skin = "flan", color = "#FFD27A", color2 = "#9A521C", w = 0.96, h = 0.88, d = 0.96 },
		face = { eyes = "big", mouth = "tongue", cheeks = CHEEKS, height = 0.3 },
		limbs = "#E8B860",
		features = {
			{ kind = "snout", style = "dog", color = "#6B4428", color2 = "#2A1A14", scale = 0.9 },
			{ kind = "ears", style = "floppy", color = "#6B4428", scale = 0.75 },
			{ kind = "tail", style = "curly", color = "#E8B860" },
		},
		toppings = {
			{ kind = "drips", on = "body", colors = { "#9A521C" }, n = 4, at = 0.8 },
		},
	},
	nacho_newt = {
		size = 2.7,
		plan = "quadruped",
		legs = 0.14,
		body = { skin = "slice", style = "chip", color = "#F2C14E", w = 0.86, h = 0.22, d = 1.05 },
		head = { skin = "round", color = "#FF9F45", w = 0.64, h = 0.52, d = 0.58 },
		face = { eyes = "big", mouth = "smile", cheeks = CHEEKS },
		limbs = "#FF9F45",
		features = {
			{ kind = "tail", style = "long", color = "#FF9F45", color2 = "#F2C14E" },
		},
		toppings = {
			{ kind = "drips", on = "body", colors = { "#FFB627" }, n = 3, at = 0.3 },
			{ kind = "discs", on = "body", colors = { "#5BBF3A" }, n = 2, spread = 0.4, scale = 0.8 },
		},
	},
	bao_bunny = {
		size = 2.25,
		plan = "blob",
		feet = true,
		body = { skin = "round", color = "#FFF6EA", w = 0.94, h = 0.84, d = 0.88 },
		face = { eyes = "happy", mouth = "o", cheeks = "#FF9FB8", nose = "#FF8FAF" },
		limbs = "#FFF0DC",
		features = {
			{ kind = "ears", style = "long", color = "#FFF6EA", color2 = "#FFC2D1" },
			{ kind = "tail", style = "puff", color = WHITE },
			{ kind = "bow", color = "#FF7FAF" },
		},
		toppings = {
			{ kind = "swirl", colors = { "#FFFDF8" }, n = 2, scale = 0.4 },
		},
	},
	pickle_piglet = {
		size = 2.55,
		plan = "quadruped",
		legs = 0.18,
		body = { skin = "lumpy", color = "#6FB536", color2 = "#8FD14F", n = 4, w = 0.76, h = 0.6, d = 0.96 },
		head = { skin = "round", color = "#7CC340" },
		face = { eyes = "round", mouth = "smile", cheeks = CHEEKS },
		limbs = "#5FA02E",
		features = {
			{ kind = "snout", style = "pig", color = "#A8E06A", color2 = "#3F7A1E" },
			{ kind = "ears", style = "pointy", color = "#7CC340", scale = 0.6 },
			{ kind = "tail", style = "curly", color = "#7CC340" },
		},
		toppings = {},
	},
	mochi_moth = {
		size = 2.45,
		plan = "blob",
		feet = true,
		body = { skin = "round", color = "#FFD6E8", w = 0.9, h = 0.84, d = 0.84 },
		face = { eyes = "big", mouth = "smile", cheeks = "#FF8FB8" },
		limbs = "#F8C0D8",
		features = {
			{ kind = "wings", style = "moth", color = "#C8F0D8", color2 = "#FF9FC8" },
			{ kind = "antennae", color = "#8A6A5A", color2 = WHITE },
		},
		toppings = {
			{ kind = "crumbs", on = "body", colors = { WHITE }, n = 4 },
		},
	},
	hotdog_dachshund = {
		size = 3.5,
		plan = "quadruped",
		legs = 0.1,
		body = { skin = "roll", style = "rounded", color = "#C8553D", w = 0.5, h = 0.5, d = 1.3 },
		head = { skin = "round", color = "#B5653A", w = 0.62, h = 0.54, d = 0.6 },
		face = { eyes = "round", mouth = "smile" },
		limbs = "#8A4A2A",
		features = {
			{ kind = "sides", color = "#F2C27A" },
			{ kind = "snout", style = "dog", color = "#D9945F", color2 = NOSE },
			{ kind = "ears", style = "floppy", color = "#7A3A1E" },
			{ kind = "tail", style = "stub", color = "#B5653A" },
		},
		toppings = {
			{ kind = "zigzag", on = "body", colors = { "#FFD23F" }, n = 3 },
		},
	},
	muffin_moose = {
		size = 1.95,
		plan = "quadruped",
		legs = 0.28,
		body = { skin = "cup", color = "#C98A4B", color2 = "#7FB8E8", w = 0.78, h = 0.68, d = 0.9 },
		head = { skin = "round", color = "#8A5A3C", w = 0.66, h = 0.56, d = 0.7 },
		face = { eyes = "round", mouth = "smile" },
		limbs = "#6B4428",
		features = {
			{ kind = "snout", style = "dog", color = "#C08A62", color2 = NOSE, scale = 1.15 },
			{ kind = "horns", style = "antlers", color = "#E8C28A" },
		},
		toppings = {
			{ kind = "balls", on = "body", colors = { "#3A3A8F", "#4A4AA8" }, n = 3 },
		},
	},
	waffle_wombat = {
		size = 2.8,
		plan = "quadruped",
		legs = 0.12,
		body = { skin = "block", style = "grid", color = "#E3A857", color2 = "#C98A3C", w = 0.82, h = 0.6, d = 0.96 },
		head = { skin = "round", color = "#9A7A62", w = 0.7, h = 0.58, d = 0.62 },
		face = { eyes = "round", mouth = "smile" },
		limbs = "#7A5A42",
		features = {
			{ kind = "snout", style = "bear", color = "#C8A890", color2 = NOSE },
			{ kind = "ears", style = "round", color = "#9A7A62", scale = 0.7 },
		},
		toppings = {
			{ kind = "pat", on = "body", colors = { "#FFE680" } },
			{ kind = "drips", on = "body", colors = { "#8A4A1A" }, n = 3, at = 0.5 },
		},
	},

	-- Rare --------------------------------------------------------------------------------------------------------
	taco_turtle = {
		size = 3.8,
		plan = "quadruped",
		legs = 0.16,
		body = { skin = "round", color = "#8FD16A", w = 0.82, h = 0.42, d = 0.96 },
		head = { skin = "round", color = "#8FD16A", w = 0.58, h = 0.52, d = 0.56 },
		face = { eyes = "round", mouth = "smile", cheeks = CHEEKS },
		features = {
			{ kind = "shell", style = "taco", color = "#F5C451", color2 = "#E0A43A" },
			{ kind = "spots", on = "shell", color = "#E0A43A", n = 5 },
			{ kind = "tail", style = "stub", color = "#8FD16A" },
		},
		toppings = {
			{ kind = "bits", on = "shell", style = "ridge", colors = { "#5BBF3A", "#E8433A", "#FFE066" }, n = 8 },
		},
	},
	cinnamon_snail = {
		size = 3.65,
		plan = "blob",
		body = { skin = "round", color = "#F3DDB8", w = 0.62, h = 0.48, d = 1.25 },
		face = { eyes = "stalk", mouth = "smile", cheeks = CHEEKS },
		features = {
			{ kind = "shell", style = "spiral", color = "#D9A15B", color2 = "#8A4A1E" },
		},
		toppings = {
			{ kind = "drips", on = "shell", colors = { "#FFF8EE" }, n = 4, at = 0.55, scale = 0.6 },
		},
	},
	macaron_macaw = {
		size = 2.3,
		plan = "biped",
		arms = false,
		body = { skin = "round", color = "#3A8DFF", w = 0.72, h = 0.56 },
		head = { skin = "macaron", color = "#FF7FAF", color2 = "#FFF4E0", w = 0.88, h = 0.74, d = 0.76 },
		face = { eyes = "round", mouth = "none" },
		limbs = "#5A5A6A",
		features = {
			{ kind = "snout", style = "beak", color = "#FFE07A", color2 = "#3A3A40", scale = 1.3 },
			{ kind = "crest", n = 3, color = "#FF4B4B", color2 = "#FFD23F" },
			{ kind = "wings", style = "feather", color = "#FF4B4B", color2 = "#FFD23F" },
			{ kind = "fan", n = 3, color = "#FF4B4B", color3 = "#3A8DFF", scale = 0.55 },
		},
		toppings = {
			{ kind = "sprinkles", on = "head", colors = SPRINKLES, n = 5 },
		},
	},
	bubblegum_bulldog = {
		size = 3.1,
		plan = "quadruped",
		legs = 0.14,
		body = { skin = "round", color = "#FF8FC8", w = 0.86, h = 0.62, d = 0.92 },
		head = { skin = "round", color = "#FFA3D2", w = 0.82, h = 0.64, d = 0.66 },
		face = { eyes = "round", mouth = "smile", brows = "#D84A92", cheeks = "#FF5FA2" },
		limbs = "#FF7FBF",
		features = {
			{ kind = "snout", style = "dog", color = "#FFD1E8", color2 = "#C8306A", scale = 1.2 },
			{ kind = "ears", style = "floppy", color = "#E06AAA", scale = 0.6 },
			{ kind = "teeth" },
			{ kind = "bubble", color = "#FF6FC0", scale = 0.85 },
			{ kind = "tail", style = "stub", color = "#FF8FC8" },
			{ kind = "spots", n = 4, color = "#FFC2E2" },
		},
		toppings = {},
	},
	burrito_bear = {
		size = 2.4,
		plan = "biped",
		body = { skin = "can", color = "#F3E1B6", color2 = "#FFF6E0", w = 0.8, h = 0.62, d = 0.8 },
		head = { skin = "round", color = "#8C5A2B" },
		face = { eyes = "round", mouth = "smile", cheeks = CHEEKS },
		limbs = "#7A4A22",
		features = {
			{ kind = "ears", style = "round", color = "#8C5A2B", color2 = "#C8955F" },
			{ kind = "snout", style = "bear", color = "#C8955F", color2 = NOSE },
			{ kind = "spots", n = 3, color = "#E0BE86" },
		},
		toppings = {
			{
				kind = "bits",
				on = "body",
				style = "rim",
				at = 0.95,
				colors = { "#5BBF3A", "#E8433A", "#6B3A1E", "#FFD23F" },
				n = 6,
			},
		},
	},
	boba_beluga = {
		size = 2.25,
		plan = "swimmer",
		body = { skin = "round", color = "#F4F7FB", w = 0.86, h = 0.72, d = 1.15 },
		face = { eyes = "big", mouth = "smile", cheeks = CHEEKS },
		limbs = "#E2E8F0",
		features = {
			{ kind = "belly", color = "#D9B48F" },
			{ kind = "straw", color = "#FF7FA8", color2 = WHITE },
			{ kind = "fins", style = "side", color = "#E2E8F0" },
			{ kind = "tail", style = "fluke", color = "#E2E8F0" },
		},
		toppings = {
			{ kind = "balls", on = "body", colors = { "#3B2418" }, n = 5, spread = 0.55 },
		},
	},
	gingersnap_gecko = {
		size = 2.6,
		plan = "quadruped",
		legs = 0.12,
		body = { skin = "round", color = "#B9733A", w = 0.62, h = 0.36, d = 1 },
		head = { skin = "round", color = "#C27E42", w = 0.6, h = 0.44, d = 0.6 },
		face = { eyes = "big", mouth = "smile", mouthColor = WHITE, brows = WHITE, cheeks = "#FF9F7A" },
		limbs = "#B9733A",
		features = {
			{ kind = "stripes", n = 2, color = WHITE },
			{ kind = "tail", style = "long", color = "#B9733A", color2 = "#C27E42" },
		},
		toppings = {
			{ kind = "balls", on = "body", colors = { "#E8433A", "#5BBF3A", "#FFD23F" }, n = 3, spread = 0.5 },
		},
	},
	brownie_beaver = {
		size = 3.25,
		plan = "quadruped",
		legs = 0.14,
		body = { skin = "block", color = "#5C3A21", color2 = "#3E2414", w = 0.78, h = 0.56, d = 0.9 },
		head = { skin = "round", color = "#8A5A3A", w = 0.68, h = 0.58 },
		face = { eyes = "round", mouth = "smile", cheeks = CHEEKS },
		limbs = "#6B4428",
		features = {
			{ kind = "snout", style = "bear", color = "#C89A6A", color2 = NOSE },
			{ kind = "teeth" },
			{ kind = "ears", style = "round", color = "#8A5A3A", scale = 0.6 },
			{ kind = "tail", style = "flat", color = "#4A2A16" },
		},
		toppings = {
			{ kind = "crumbs", on = "body", colors = { "#D9B48A", "#F2E2C8" }, n = 5, scale = 1.3 },
		},
	},
	sundae_sheep = {
		size = 2.75,
		plan = "quadruped",
		legs = 0.2,
		body = { skin = "lumpy", color = "#FFFDF6", color2 = "#FFF8EC", n = 6, w = 0.86, h = 0.66, d = 0.96 },
		head = { skin = "round", color = "#7A4A32", w = 0.6, h = 0.54, d = 0.56 },
		face = { eyes = "round", mouth = "smile", cheeks = CHEEKS },
		limbs = "#6B3E28",
		features = {
			{ kind = "ears", style = "floppy", color = "#6B3E28", scale = 0.7 },
		},
		toppings = {
			{ kind = "drips", on = "body", colors = { "#5A3A2A" }, n = 4, at = 0.5 },
			{ kind = "sprinkles", on = "body", colors = SPRINKLES, n = 5 },
			{ kind = "cherry", on = "body", colors = { "#E8233A" } },
		},
	},
	cupcake_cub = {
		size = 2.05,
		plan = "biped",
		body = { skin = "cup", color = "#8B5A3C", color2 = "#7FD8F0" },
		head = { skin = "round", color = "#FF9FCF" },
		face = { eyes = "big", mouth = "smile", cheeks = "#FF6FAF" },
		limbs = "#FF9FCF",
		features = {
			{ kind = "ears", style = "round", color = "#FF9FCF", color2 = "#FFD6EA" },
			{ kind = "snout", style = "bear", color = "#FFE3F1", color2 = "#C8306A" },
		},
		toppings = {
			{ kind = "sprinkles", on = "head", colors = SPRINKLES, n = 9, spread = 0.75 },
			{ kind = "cherry", on = "head", colors = { "#E8233A" } },
		},
	},

	-- Epic --------------------------------------------------------------------------------------------------------
	ramen_raccoon = {
		size = 2.4,
		plan = "biped",
		body = { skin = "bowl", color = "#E8433A", color2 = "#F2C46D", color3 = WHITE, w = 0.86, h = 0.6, d = 0.86 },
		head = { skin = "round", color = "#9A9AA8", w = 0.82, h = 0.66 },
		face = { eyes = "round", mouth = "smile" },
		limbs = "#7A7A88",
		features = {
			{ kind = "mask", color = "#4A4A55" },
			{ kind = "ears", style = "pointy", color = "#9A9AA8" },
			{ kind = "snout", style = "dog", color = "#F2F2F2", color2 = "#2A2A30", scale = 0.85 },
			{ kind = "tail", style = "ringed", color = "#9A9AA8", color2 = "#4A4A55" },
		},
		toppings = {
			{ kind = "strands", on = "body", colors = { "#FFE9A0" }, n = 4, at = 0.85 },
			{ kind = "egg", on = "body", colors = { WHITE, "#FFB72B" } },
			{ kind = "swirlmark", on = "body", colors = { WHITE, "#FF7AA8" } },
		},
	},
	popcorn_penguin = {
		size = 2.55,
		plan = "biped",
		arms = false,
		body = { skin = "round", color = "#2E3A59", w = 0.78, h = 0.6 },
		head = { skin = "round", color = "#2E3A59", w = 0.8, h = 0.66 },
		face = { eyes = "round", mouth = "none", cheeks = CHEEKS },
		limbs = "#FF9F2E",
		features = {
			{ kind = "belly", color = WHITE },
			{ kind = "mask", color = WHITE },
			{ kind = "snout", style = "beak", color = "#FF9F2E" },
			{ kind = "wings", style = "tiny", color = "#2E3A59", scale = 1.2 },
		},
		toppings = {
			{ kind = "balls", on = "head", colors = { "#FFF6D5", "#FFE9A0", WHITE }, n = 7, spread = 0.7, scale = 1.3 },
			{ kind = "crumbs", on = "head", colors = { "#FFD25A" }, n = 3 },
		},
	},
	bagel_badger = {
		size = 3.7,
		plan = "quadruped",
		legs = 0.16,
		body = { skin = "ring", style = "flat", color = "#D9A15B", color3 = "#FFF8E8", w = 0.8, h = 0.46, d = 0.98 },
		head = { skin = "round", color = "#8A8A92", w = 0.66, h = 0.56, d = 0.6 },
		face = { eyes = "round", mouth = "smile", cheeks = CHEEKS },
		limbs = "#3A3A40",
		features = {
			{ kind = "stripes", style = "back", on = "head", color = WHITE },
			{ kind = "snout", style = "dog", color = WHITE, color2 = "#2A2A30", scale = 0.85 },
			{ kind = "ears", style = "round", color = "#3A3A40", scale = 0.6 },
			{ kind = "tail", style = "stub", color = "#8A8A92" },
		},
		toppings = {
			{ kind = "seeds", on = "body", colors = { WHITE, "#2A2A2A", "#E8C88A" }, n = 9, spread = 0.9 },
		},
	},
	omelet_owl = {
		size = 2.5,
		plan = "biped",
		arms = false,
		body = { skin = "round", color = "#FFD45C", w = 0.82, h = 0.62 },
		head = { skin = "round", color = "#FFD45C", w = 0.84, h = 0.7 },
		face = { eyes = "big", mouth = "none", brows = "#E8A93B", cheeks = CHEEKS },
		limbs = "#E8A93B",
		features = {
			{ kind = "belly", color = "#FFE89A" },
			{ kind = "snout", style = "beak", color = "#FF9F2E", scale = 0.7 },
			{ kind = "ears", style = "pointy", color = "#F5C04A", scale = 0.6 },
			{ kind = "wings", style = "feather", color = "#F5C04A", color2 = "#E8A93B" },
			{ kind = "spots", n = 3, color = "#E8A93B" },
		},
		toppings = {
			{
				kind = "bits",
				on = "body",
				style = "rim",
				at = 0.3,
				colors = { "#5BBF3A", "#E8433A", "#FF8FA0" },
				n = 5,
			},
		},
	},
	smore_skunk = {
		size = 2.85,
		plan = "quadruped",
		legs = 0.18,
		body = {
			skin = "block",
			style = "layers",
			n = 4,
			color = "#D9A15B",
			color2 = "#4A2A16",
			color3 = "#FFF8EE",
			w = 0.74,
			h = 0.64,
			d = 0.92,
		},
		head = { skin = "round", color = "#4A3A3A", w = 0.66, h = 0.58, d = 0.62 },
		face = { eyes = "round", mouth = "tongue", cheeks = CHEEKS },
		limbs = "#3A2A2A",
		features = {
			{ kind = "stripes", style = "back", on = "head", color = "#FFF8EE" },
			{ kind = "stripes", style = "back", color = "#FFF8EE" },
			{ kind = "ears", style = "round", color = "#3A2A2A", scale = 0.6 },
			{ kind = "tail", style = "fluffy", color = "#3A2A2A", color2 = "#FFF8EE", scale = 1.2 },
		},
		toppings = {
			{ kind = "crumbs", on = "body", colors = { "#C88A3C" }, n = 4 },
		},
	},
	tempura_tiger = {
		size = 3,
		plan = "quadruped",
		legs = 0.22,
		body = { skin = "lumpy", color = "#F5C45A", color2 = "#FFD97A", n = 5, w = 0.74, h = 0.58, d = 1 },
		head = { skin = "round", color = "#FF9A3C", w = 0.7, h = 0.6 },
		face = { eyes = "round", mouth = "cat" },
		limbs = "#FF9A3C",
		features = {
			{ kind = "stripes", n = 3, color = "#B8571E" },
			{ kind = "ears", style = "round", color = "#FF9A3C", scale = 0.7 },
			{ kind = "snout", style = "cat", color = "#FFF1DE", color2 = "#3A2A2E" },
			{ kind = "whiskers", color = "#3A2A2E" },
			{ kind = "tail", style = "fluke", color = "#FF5A3C", color2 = "#FF7A4A" },
		},
		toppings = {},
	},
	nugget_narwhal = {
		size = 3.15,
		plan = "swimmer",
		body = { skin = "lumpy", color = "#E8A93B", color2 = "#F5C45A", n = 5, w = 0.82, h = 0.68, d = 1.1 },
		face = { eyes = "round", mouth = "smile", cheeks = CHEEKS },
		limbs = "#E8A93B",
		features = {
			{ kind = "horns", style = "tusk", color = "#FFD25A", color2 = "#FFE07A", scale = 1.4 },
			{ kind = "fins", style = "side", color = "#E8A93B" },
			{ kind = "tail", style = "fluke", color = "#E8A93B" },
		},
		toppings = {
			{ kind = "crumbs", on = "body", colors = { "#C9782E" }, n = 4 },
		},
	},
	hamburger_hamster = {
		size = 3.2,
		plan = "blob",
		feet = true,
		arms = true,
		body = { skin = "bun", color = "#E8A24A", color2 = "#6B3A1E", color3 = "#FFC83D", w = 1, h = 0.96, d = 0.94 },
		face = {
			eyes = "round",
			mouth = "cat",
			cheeks = "#FF8FA8",
			nose = "#FF7FA0",
			height = 0.55,
			mouthAt = 0.26,
			scale = 0.9,
		},
		limbs = "#F2C27A",
		features = {
			{ kind = "ears", style = "round", color = "#E8A24A", color2 = "#FFB8C8", scale = 0.7 },
		},
		toppings = {
			{ kind = "seeds", colors = { "#FFF6E0" }, n = 7, spread = 0.65 },
		},
	},
	spaghetti_yeti = {
		size = 2.3,
		plan = "biped",
		body = { skin = "round", color = "#F5D98A", w = 0.92, h = 0.66 },
		head = { skin = "round", color = "#F5D98A", w = 0.86, h = 0.7 },
		face = { eyes = "round", mouth = "grin", brows = "#E8C060" },
		limbs = "#F0D080",
		features = {
			{ kind = "snout", style = "dog", color = "#D63A2A", color2 = "#7A3A1E", scale = 0.9 },
		},
		toppings = {
			{ kind = "cap", on = "head", colors = { "#D63A2A" } },
			{ kind = "balls", on = "head", colors = { "#7A3A1E" }, n = 2, scale = 1.6, spread = 0.4 },
			{ kind = "strands", on = "head", colors = { "#F5D98A" }, n = 5, at = 0.35 },
			{ kind = "crumbs", on = "head", colors = { "#FFFDF0" }, n = 4 },
		},
	},

	-- Legendary ---------------------------------------------------------------------------------------------------
	donut_dragon = {
		size = 2.35,
		plan = "biped",
		body = { skin = "ring", color = "#E9B26B", color2 = "#FF77B7", w = 0.9, h = 0.82, d = 0.5 },
		head = { skin = "round", color = "#A68BFF", w = 0.8, h = 0.66, d = 0.72 },
		face = { eyes = "big", mouth = "fang", cheeks = "#FF8FC7" },
		limbs = "#A68BFF",
		features = {
			{ kind = "snout", style = "bear", color = "#C9B8FF", color2 = "#5A3A8A" },
			{ kind = "horns", style = "nub", color = "#FFE6A8" },
			{ kind = "wings", style = "dragon", color = "#C2ADFF", color2 = "#8E5CFF", color3 = "#7A4FE0" },
			{ kind = "tail", style = "long", color = "#A68BFF", color2 = "#8E5CFF" },
			{ kind = "spikes", on = "head", color = "#FF77B7", n = 3, scale = 0.7 },
		},
		toppings = {
			{ kind = "sprinkles", on = "body", style = "front", colors = SPRINKLES, n = 10, spread = 0.85 },
		},
	},
	onigiri_orca = {
		size = 2.85,
		plan = "swimmer",
		body = { skin = "pear", color = "#FBF7EF", w = 0.92, h = 0.84, d = 1.1 },
		face = { eyes = "round", mouth = "smile", cheeks = CHEEKS },
		limbs = "#22302A",
		features = {
			{ kind = "fins", color = "#22302A", scale = 1.1 },
			{ kind = "tail", style = "fluke", color = "#22302A" },
			{ kind = "spots", n = 6, color = WHITE, scale = 0.5 },
		},
		toppings = {
			{ kind = "band", colors = { "#22302A" }, at = -0.72, scale = 0.6 },
			{ kind = "seeds", colors = { "#2A2A2A" }, n = 5, spread = 0.6 },
			{ kind = "balls", colors = { "#E8335A" }, n = 1, spread = 0, scale = 1.4 },
		},
	},
	taffy_toucan = {
		size = 2.9,
		plan = "biped",
		arms = false,
		body = { skin = "round", color = "#2A2A35", w = 0.76, h = 0.6 },
		head = { skin = "round", color = "#2A2A35", w = 0.8, h = 0.68 },
		face = { eyes = "round", mouth = "none", patches = "#5FA8FF" },
		limbs = "#5FA8FF",
		features = {
			{ kind = "belly", color = "#FFE45F" },
			{ kind = "snout", style = "toucan", color = "#FF8A2E", color2 = "#FF4B4B", color3 = "#FFE45F" },
			{ kind = "wings", style = "feather", color = "#2A2A35", color2 = "#FF5FA2" },
			{ kind = "bow", color = WHITE, color2 = "#FF5FA2" },
			{ kind = "fan", n = 3, color = "#2A2A35", color3 = "#FF4B4B", scale = 0.5 },
		},
		toppings = {},
	},
	pancake_panda = {
		size = 2.6,
		plan = "biped",
		body = { skin = "stack", n = 4, color = "#F4C27A", color2 = "#E8A85A", w = 0.84, h = 0.64, d = 0.84 },
		head = { skin = "round", color = WHITE, w = 0.86, h = 0.72 },
		face = { eyes = "round", mouth = "smile", patches = "#2A2A30", cheeks = CHEEKS },
		limbs = "#2A2A30",
		features = {
			{ kind = "ears", style = "round", color = "#2A2A30" },
			{ kind = "snout", style = "bear", color = WHITE, color2 = "#2A2A30", scale = 0.8 },
		},
		toppings = {
			{ kind = "drips", on = "body", colors = { "#A0581E" }, n = 5, at = 0.85, scale = 0.8 },
			{ kind = "pat", on = "head", colors = { "#FFE680" } },
		},
	},
	cotton_candy_koala = {
		size = 2.55,
		plan = "biped",
		body = { skin = "lumpy", color = "#FFB3D9", color2 = "#A8D8FF", n = 5, w = 0.86, h = 0.62 },
		head = { skin = "lumpy", color = "#FFC8E4", color2 = "#BFE3FF", n = 4 },
		face = { eyes = "round", mouth = "smile", cheeks = "#FF7FB8" },
		limbs = "#FFB3D9",
		features = {
			{ kind = "ears", style = "mouse", color = "#A8D8FF", color2 = "#FFC8E4", scale = 0.9 },
			{ kind = "snout", style = "dog", color = "#FFC8E4", color2 = "#4A4A5A" },
		},
		toppings = {
			{ kind = "balls", on = "head", colors = { WHITE }, n = 5, scale = 0.5 },
		},
	},
	pavlova_peacock = {
		size = 2.55,
		plan = "biped",
		arms = false,
		body = { skin = "lumpy", color = "#FFF8F0", color2 = "#FFFDF8", n = 3, w = 0.8, h = 0.62 },
		head = { skin = "round", color = "#2F8FD8", w = 0.7, h = 0.62 },
		face = { eyes = "round", mouth = "none", cheeks = CHEEKS },
		limbs = "#8A8A9A",
		features = {
			{ kind = "snout", style = "beak", color = "#E8C88A" },
			{ kind = "crest", n = 3, color = "#2FB59C", color2 = "#2F8FD8" },
			{ kind = "fan", n = 7, color = "#2FB59C", color2 = "#E8335A", color3 = "#5BBF3A" },
		},
		toppings = {
			{ kind = "discs", on = "body", colors = { "#7BC043" }, n = 3, spread = 0.55 },
			{ kind = "balls", on = "body", colors = { "#E8335A", "#5A4AE0" }, n = 4, spread = 0.7 },
		},
	},
	milkshake_mammoth = {
		size = 2.1,
		plan = "quadruped",
		legs = 0.26,
		body = { skin = "round", color = "#FF9FC0", w = 0.9, h = 0.7, d = 1 },
		head = { skin = "round", color = "#FFB0CC", w = 0.7, h = 0.62 },
		face = { eyes = "round", mouth = "none", cheeks = "#FF5F8F" },
		limbs = "#FF8FB4",
		features = {
			{ kind = "snout", style = "trunk", color = "#FFB0CC" },
			{ kind = "tusks", color = "#FFE8B8" },
			{ kind = "ears", style = "floppy", color = "#FF8FB4", scale = 1.3 },
			{ kind = "straw", color = "#FF5F8F", color2 = WHITE },
		},
		toppings = {
			{ kind = "drips", on = "body", colors = { "#FFFDF6" }, n = 4, at = 0.5 },
			{ kind = "swirl", on = "body", colors = { "#FFFDF6" }, n = 3 },
			{ kind = "cherry", on = "body", colors = { "#E8233A" } },
			{ kind = "sprinkles", on = "body", colors = SPRINKLES, n = 6, spread = 0.8 },
		},
	},
	churro_cheetah = {
		size = 3.4,
		plan = "quadruped",
		legs = 0.3,
		body = { skin = "roll", style = "rounded", color = "#D98E3F", w = 0.5, h = 0.5, d = 1.12 },
		head = { skin = "round", color = "#E8A04A", w = 0.62, h = 0.54, d = 0.58 },
		face = { eyes = "round", mouth = "cat", cheeks = CHEEKS },
		limbs = "#D98E3F",
		features = {
			{ kind = "stripes", n = 4, color = "#B8702E" },
			{ kind = "spots", n = 5, color = "#6B3A12" },
			{ kind = "ears", style = "round", color = "#E8A04A", scale = 0.6 },
			{ kind = "snout", style = "cat", color = "#FFF1DE", color2 = "#3A2A2E" },
			{ kind = "whiskers", color = "#3A2A2E" },
			{ kind = "tail", style = "thin", color = "#D98E3F", color2 = "#6B3A12" },
		},
		toppings = {
			{ kind = "crumbs", on = "body", colors = { WHITE }, n = 6 },
		},
	},

	-- Mythic ------------------------------------------------------------------------------------------------------
	lasagna_lion = {
		size = 2.8,
		plan = "quadruped",
		legs = 0.22,
		body = {
			skin = "block",
			style = "layers",
			n = 5,
			color = "#F5C45A",
			color2 = "#D63A2A",
			color3 = "#FFF2C0",
			w = 0.8,
			h = 0.66,
			d = 1,
		},
		head = { skin = "round", color = "#F5C45A", w = 0.7, h = 0.62 },
		face = { eyes = "round", mouth = "smile", brows = "#B8571E" },
		limbs = "#F5C45A",
		features = {
			{ kind = "mane", n = 10, color = "#F5C45A", color2 = "#D63A2A" },
			{ kind = "snout", style = "bear", color = "#FFF2C0", color2 = "#8A3A1E" },
			{ kind = "ears", style = "round", color = "#F5C45A", scale = 0.6 },
			{ kind = "tail", style = "lion", color = "#F5C45A", color2 = "#D63A2A" },
		},
		toppings = {
			{ kind = "cap", on = "body", colors = { "#FFF2C0" } },
			{ kind = "drips", on = "body", colors = { "#FFF2C0" }, n = 4, at = 0.6 },
			{ kind = "leaf", on = "head", colors = { "#3FA34D", "#2E7A3A" } },
		},
	},
	souffle_sphinx = {
		size = 2.6,
		plan = "biped",
		arms = false,
		body = { skin = "cup", color = "#F2C45A", color2 = WHITE, w = 0.86, h = 0.72 },
		head = { skin = "round", color = "#F2C45A", w = 0.8, h = 0.66 },
		face = { eyes = "sleepy", mouth = "cat", brows = "#2A2A35" },
		limbs = "#F2C45A",
		features = {
			{ kind = "ears", style = "floppy", color = "#3A6FD8", scale = 1.2 },
			{ kind = "snout", style = "cat", color = "#FFE9B0", color2 = "#3A2A2E" },
			{ kind = "whiskers", color = "#3A2A2E" },
			{ kind = "crest", n = 1, color = "#FFD23F" },
			{ kind = "tail", style = "thin", color = "#F2C45A" },
		},
		toppings = {
			{ kind = "band", on = "head", colors = { "#FFD23F" }, at = 0.45, scale = 0.4 },
			{ kind = "crumbs", on = "body", colors = { WHITE }, n = 5 },
		},
	},
	gingerbread_golem = {
		size = 2.9,
		plan = "biped",
		body = { skin = "block", color = "#B9733A", w = 0.92, h = 0.72, d = 0.56 },
		head = { skin = "block", color = "#C27E42", w = 0.78, h = 0.64, d = 0.56 },
		face = { eyes = "dot", mouth = "smile", mouthColor = WHITE, brows = WHITE, cheeks = "#FF7F7F" },
		limbs = "#B9733A",
		features = {
			{ kind = "stripes", style = "bands", n = 2, color = WHITE },
		},
		toppings = {
			{
				kind = "balls",
				on = "body",
				style = "front",
				colors = { "#E8433A", "#5BBF3A", "#FFD23F" },
				n = 3,
				spread = 0.6,
				scale = 1.3,
			},
			{ kind = "drips", on = "head", colors = { WHITE }, n = 4, at = 0.8 },
			{ kind = "crumbs", on = "head", colors = { WHITE }, n = 4 },
		},
	},
	parfait_pegasus = {
		size = 2.6,
		plan = "quadruped",
		legs = 0.32,
		neck = 0.22,
		body = { skin = "round", color = "#FFF6E8", w = 0.76, h = 0.6, d = 1 },
		head = { skin = "round", color = "#FFF6E8", w = 0.56, h = 0.54, d = 0.7 },
		face = { eyes = "big", mouth = "smile", cheeks = "#FF8FB8" },
		limbs = "#FFF6E8",
		features = {
			{ kind = "stripes", style = "bands", n = 2, color = "#E8335A" },
			{ kind = "snout", style = "dog", color = "#FFE4EC", color2 = "#C8507A", scale = 1.1 },
			{ kind = "ears", style = "pointy", color = "#FFF6E8", scale = 0.6 },
			{ kind = "crest", n = 4, color = "#FF8FB8", color2 = "#B57BFF" },
			{ kind = "wings", style = "angel", color = WHITE, color2 = "#FFD1E8", color3 = "#D8C8FF" },
			{ kind = "tail", style = "fluffy", color = "#FF8FB8", color2 = "#B57BFF" },
		},
		toppings = {
			{ kind = "swirl", on = "body", colors = { WHITE }, n = 2 },
			{ kind = "balls", on = "body", colors = { "#E8335A", "#5A4AE0" }, n = 3, spread = 0.7 },
			{ kind = "leaf", on = "body", colors = { "#5BBF3A", "#3A8A2A" } },
		},
	},
	hotpot_hydra = {
		size = 2.6,
		plan = "biped",
		arms = false,
		neck = 0.2,
		body = {
			skin = "bowl",
			color = "#B8572E",
			color2 = "#E8433A",
			color3 = "#FFD23F",
			w = 0.92,
			h = 0.62,
			d = 0.92,
		},
		head = { skin = "round", color = "#5BBF7A", w = 0.7, h = 0.6 },
		face = { eyes = "round", mouth = "fang", cheeks = CHEEKS },
		limbs = "#4AA866",
		features = {
			{ kind = "heads", n = 2, color = "#5BBF7A", scale = 0.75 },
			{ kind = "horns", style = "nub", color = "#FFE6A8" },
			{ kind = "tail", style = "long", color = "#5BBF7A", color2 = "#4AA866", scale = 0.75 },
		},
		toppings = {
			{
				kind = "bits",
				on = "body",
				style = "rim",
				at = 0.9,
				colors = { WHITE, "#5BBF3A", "#8A5A3A", "#FF6A4A" },
				n = 6,
			},
		},
	},
	flambe_phoenix = {
		size = 2.2,
		plan = "biped",
		arms = false,
		body = { skin = "round", color = "#FF9A3C", w = 0.78, h = 0.6 },
		head = { skin = "round", color = "#FFB347", w = 0.74, h = 0.64 },
		face = { eyes = "round", mouth = "none", brows = "#C2410C", cheeks = CHEEKS },
		limbs = "#FFD23F",
		features = {
			{ kind = "belly", color = "#FFE05A" },
			{ kind = "snout", style = "beak", color = "#FFD23F", color2 = "#E8A12A" },
			{ kind = "wings", style = "angel", color = "#FF5A1F", color2 = "#FFB33C", color3 = "#FFE05A" },
			{ kind = "flame", n = 3 },
			{ kind = "fan", n = 5, color = "#FF5A1F", color3 = "#FFD23F", scale = 0.8 },
		},
		toppings = {
			{ kind = "crumbs", on = "body", colors = { "#FFF4D0" }, n = 4 },
		},
	},
	dumpling_dino = {
		size = 2.65,
		plan = "biped",
		body = { skin = "round", color = "#F5F0E1", w = 0.84, h = 0.62 },
		head = { skin = "round", color = "#F5F0E1", w = 0.8, h = 0.66 },
		face = { eyes = "round", mouth = "tongue", cheeks = "#FF9FB8" },
		limbs = "#EDE6D2",
		features = {
			{ kind = "belly", color = "#FFFDF4" },
			{ kind = "spikes", n = 4, color = "#6FCF97" },
			{ kind = "spikes", on = "head", n = 4, color = "#F5F0E1", scale = 0.55 },
			{ kind = "tail", style = "long", color = "#F5F0E1", color2 = "#6FCF97", scale = 0.8 },
		},
		toppings = {
			{ kind = "crumbs", on = "head", colors = { "#6FCF97" }, n = 4 },
		},
	},

	-- Secret ------------------------------------------------------------------------------------------------------
	gelato_griffin = {
		size = 2.55,
		plan = "quadruped",
		legs = 0.24,
		body = { skin = "lumpy", color = "#9BE7FF", color2 = "#FFB3D1", n = 4, w = 0.8, h = 0.62, d = 1 },
		head = { skin = "round", color = "#FFF4D6", w = 0.7, h = 0.62 },
		face = { eyes = "big", mouth = "none", cheeks = "#FF8FB8" },
		limbs = "#FFE0A8",
		features = {
			{ kind = "snout", style = "beak", color = "#D99A4E", color2 = "#C27E3A" },
			{ kind = "crest", n = 3, color = "#FFB3D1", color2 = "#9BE7FF" },
			{ kind = "wings", style = "angel", color = WHITE, color2 = "#FFD1F0", color3 = "#C8F0FF", scale = 0.85 },
			{ kind = "tail", style = "lion", color = "#FFE0A8", color2 = "#FFB3D1" },
		},
		toppings = {
			{ kind = "sprinkles", on = "body", colors = SPRINKLES, n = 6 },
			{ kind = "sticks", on = "body", colors = { "#E8B86A" }, n = 2, spread = 0.4 },
			{ kind = "cherry", on = "head", colors = { "#E8233A" } },
		},
	},
	matcha_manta = {
		size = 2.4,
		plan = "swimmer",
		body = { skin = "round", color = "#8FBF5A", w = 1, h = 0.36, d = 1 },
		face = { eyes = "round", mouth = "smile", cheeks = CHEEKS, height = 0.2 },
		limbs = "#7AAE48",
		features = {
			{ kind = "wings", style = "manta", color = "#8FBF5A" },
			{ kind = "tail", style = "long", color = "#6E9E3E", scale = 0.7 },
			{ kind = "horns", style = "nub", color = "#7AAE48" },
		},
		toppings = {
			{ kind = "swirl", colors = { WHITE }, n = 2, scale = 0.8 },
			{ kind = "balls", colors = { "#7A2A2A", WHITE }, n = 6, spread = 0.75 },
			{ kind = "crumbs", colors = { "#A8D27A" }, n = 4 },
		},
	},
	fortune_cookie_kitsune = {
		size = 2.5,
		plan = "quadruped",
		legs = 0.24,
		body = { skin = "round", color = "#F2C45A", w = 0.7, h = 0.56, d = 0.96 },
		head = { skin = "round", color = "#F5CF6A", w = 0.68, h = 0.6 },
		face = { eyes = "round", mouth = "cat", brows = "#E8433A", cheeks = CHEEKS },
		limbs = "#E8B04A",
		features = {
			{ kind = "ears", style = "pointy", color = "#F5CF6A", color2 = "#E8433A" },
			{ kind = "snout", style = "dog", color = "#FFF1D0", color2 = NOSE, scale = 0.85 },
			{ kind = "tail", style = "fluffy", n = 5, color = "#F2C45A", color2 = WHITE },
			{ kind = "slip", color = WHITE, color2 = "#E8433A" },
			{ kind = "bow", color = "#E8433A", color2 = "#FFD23F" },
		},
		toppings = {},
	},
	bonbon_behemoth = {
		size = 2.6,
		plan = "quadruped",
		legs = 0.26,
		body = { skin = "round", color = "#4A2A16", w = 0.96, h = 0.76, d = 1 },
		head = { skin = "round", color = "#5A3420", w = 0.74, h = 0.62 },
		face = { eyes = "round", mouth = "grin", brows = "#2A140A", cheeks = CHEEKS },
		limbs = "#3A2010",
		features = {
			{ kind = "snout", style = "bear", color = "#8A5A3A", color2 = "#2A140A", scale = 0.9 },
			{ kind = "horns", style = "curved", color = "#FFD23F", color2 = "#FFE88A", material = "Foil", scale = 1.4 },
			{ kind = "tusks", color = "#FFF4E0", scale = 0.8 },
			{ kind = "ears", style = "round", color = "#4A2A16", scale = 0.6 },
			{ kind = "tail", style = "stub", color = "#4A2A16" },
		},
		toppings = {
			{ kind = "zigzag", on = "body", colors = { "#FFF4E0" }, n = 4 },
			{ kind = "discs", on = "body", colors = { "#FFD23F" }, n = 3, spread = 0.7, material = "Foil" },
			{ kind = "balls", on = "head", colors = { "#B8783A" }, n = 2, spread = 0.5 },
		},
	},
	wedding_cake_wyvern = {
		size = 2.35,
		plan = "biped",
		body = { skin = "stack", style = "tiers", n = 3, color = WHITE, color2 = "#FFD1E8", w = 0.9, h = 0.7, d = 0.9 },
		head = { skin = "round", color = "#E6DCFF", w = 0.78, h = 0.66 },
		face = { eyes = "big", mouth = "smile", cheeks = "#FF9FC8" },
		limbs = "#D8C8FF",
		features = {
			{ kind = "wings", style = "dragon", color = WHITE, color2 = "#FFD1E8", color3 = "#E6DCFF", scale = 0.8 },
			{ kind = "tail", style = "long", color = "#E6DCFF", color2 = "#FFD1E8", scale = 0.75 },
			{ kind = "horns", style = "curved", color = "#FFD23F", color2 = "#FFE88A" },
			{ kind = "spikes", on = "head", n = 3, color = "#FFD1E8" },
		},
		toppings = {
			{ kind = "drips", on = "body", colors = { WHITE }, n = 5, at = 0.7 },
			{ kind = "balls", on = "body", colors = { WHITE }, n = 5, spread = 0.9, scale = 0.7 },
		},
	},
	croissant_kraken = {
		size = 2.4,
		plan = "tentacled",
		tentacles = 8,
		body = { skin = "round", color = "#E0A84E", color2 = "#C98A3C", w = 1, h = 0.86, d = 0.94 },
		face = { eyes = "big", mouth = "o", brows = "#8A5A2A", cheeks = "#FF9F7A" },
		limbs = "#E8B45A",
		features = {
			{ kind = "stripes", style = "bands", n = 3, color = "#C98A3C" },
		},
		toppings = {
			{ kind = "crumbs", on = "body", colors = { "#F5D08A" }, n = 6 },
			{ kind = "pat", on = "body", colors = { "#FFE680" } },
		},
	},

	-- Event: Halloween 2026 ---------------------------------------------------------------------------------------
	candy_corn_cat = {
		size = 2.6,
		plan = "quadruped",
		legs = 0.2,
		body = { skin = "round", color = "#FF9F1C", w = 0.72, h = 0.56, d = 0.96 },
		head = { skin = "round", color = "#FF9F1C" },
		face = { eyes = "round", mouth = "cat", cheeks = CHEEKS },
		limbs = "#FFD23F",
		features = {
			{ kind = "ears", style = "pointy", color = "#FF9F1C", color2 = "#FFF4DC" },
			{ kind = "snout", style = "cat", color = "#FFF4DC", color2 = "#FF5FA2" },
			{ kind = "whiskers", color = "#5A3A2A" },
			{ kind = "tail", style = "thin", color = "#FF9F1C", color2 = "#FFF4DC" },
		},
		toppings = {
			{ kind = "band", on = "body", colors = { "#FFD23F" }, at = -0.55 },
			{ kind = "cap", on = "body", colors = { "#FFF4DC" } },
		},
	},
	pumpkin_pie_bat = {
		size = 2.85,
		plan = "blob",
		feet = true,
		body = { skin = "round", color = "#E07A2E", w = 0.94, h = 0.84, d = 0.86 },
		face = { eyes = "big", mouth = "fang", cheeks = "#FF7F7F" },
		limbs = "#3B2A4A",
		features = {
			{ kind = "wings", style = "bat", color = "#3B2A4A", color2 = "#5A3F6E" },
			{ kind = "ears", style = "pointy", color = "#3B2A4A" },
		},
		toppings = {
			{ kind = "band", colors = { "#D9A15B" }, at = -0.55, scale = 0.9 },
			{ kind = "swirl", colors = { "#FFF8EE" }, n = 2, scale = 0.6 },
			{ kind = "crumbs", colors = { "#8A4A1E" }, n = 4, spread = 0.9 },
		},
	},
	caramel_apple_ghoul = {
		size = 2.15,
		plan = "tentacled",
		tentacles = 5,
		body = { skin = "round", color = "#E23B4A", color2 = "#F2F0FF", w = 0.96, h = 0.86, d = 0.9 },
		face = { eyes = "big", mouth = "grin", brows = "#5A1A2A", pupil = "#2E8A4A", cheeks = CHEEKS },
		limbs = "#EDE8FF",
		features = {},
		toppings = {
			{ kind = "cap", colors = { "#C7792E" } },
			{ kind = "drips", colors = { "#C7792E" }, n = 5, at = 0.25 },
			{ kind = "sticks", colors = { "#E8D2A8" }, n = 1, spread = 0, scale = 1.3 },
			{ kind = "crumbs", colors = { "#F5D9A4" }, n = 5 },
		},
	},
	jack_o_lantern_latte = {
		size = 2.5,
		plan = "blob",
		feet = true,
		body = { skin = "can", color = "#F28C28", color2 = "#FFF4DC", w = 0.86, h = 0.86, d = 0.86 },
		face = { eyes = "dot", mouth = "grin", cheeks = "#FF6A3A", pupil = "#4A2210" },
		limbs = "#C8601A",
		features = {
			{ kind = "handle", color = "#F28C28" },
		},
		toppings = {
			{ kind = "drips", colors = { "#FFF4DC" }, n = 4, at = 0.8 },
			{ kind = "swirl", colors = { "#FFF4DC" }, n = 3 },
			{ kind = "crumbs", colors = { "#8A4A1E" }, n = 4 },
			{ kind = "leaf", colors = { "#5BBF3A", "#4A7A2A" } },
		},
	},
}

return CreatureLooks
