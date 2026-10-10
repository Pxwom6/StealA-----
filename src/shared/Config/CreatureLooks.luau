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
