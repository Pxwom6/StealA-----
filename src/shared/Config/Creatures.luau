--!strict
--[[
	The Snackling catalogue. Plain data only.

	price       cash cost on the conveyor (the server always uses THIS value, never a client-sent one)
	income      base cash per second while on a podium (before rebirth / pass / event multipliers)
	beltWeight  relative chance within its rarity tier
	modelName   name of a Model in ReplicatedStorage.CreatureModels to use instead of the placeholder
	look        recipe for the code-built placeholder model (body shape + colours + one accent)
	eventId     optional: only spawns while the LiveOps event with this id is active (limited-time creatures)

	Balance notes live in BALANCE.md; `lune run tools/simulate.luau` re-runs the numbers after any change here.

	Never remove or rename an `id` once it has shipped: players own them (a save with an unknown id quarantines
	that creature until the id is back). To stop one spawning, give it an `eventId` that is never active.
	New ids must also be appended to RELEASED_CREATURE_IDS in tests/Config.spec.luau (CI fails until they are).
]]

local Types = require("../Types")

export type CreatureDef = Types.CreatureDef

local Creatures: { CreatureDef } = {
	-- Common ---------------------------------------------------------------------------------------------
	{
		id = "pizza_pup",
		displayName = "Pizza Pup",
		rarity = "Common",
		price = 25,
		income = 1,
		beltWeight = 40,
		modelName = "PizzaPup",
		flavor = "Extra cheesy. Fetches crusts.",
		look = { body = "Wedge", bodyColor = "#F6C445", accent = "Spots", accentColor = "#D64933", size = 2.6 },
	},
	{
		id = "pretzel_pal",
		displayName = "Pretzel Pal",
		rarity = "Common",
		price = 60,
		income = 2,
		beltWeight = 30,
		modelName = "PretzelPal",
		flavor = "Gets itself in knots.",
		look = { body = "Ball", bodyColor = "#A0612B", accent = "Sprinkles", accentColor = "#FFFFFF", size = 2.6 },
	},
	{
		id = "gummy_grub",
		displayName = "Gummy Grub",
		rarity = "Common",
		price = 120,
		income = 4,
		beltWeight = 20,
		modelName = "GummyGrub",
		flavor = "Wobbles when happy. Always happy.",
		look = { body = "Cylinder", bodyColor = "#7CDB4C", accent = "Ears", accentColor = "#FF5FA2", size = 2.6 },
	},
	{
		id = "toast_toad",
		displayName = "Toast Toad",
		rarity = "Common",
		price = 200,
		income = 6,
		beltWeight = 10,
		modelName = "ToastToad",
		flavor = "Pops up when you least expect it.",
		look = { body = "Block", bodyColor = "#E3A857", accent = "Shell", accentColor = "#8B4A1C", size = 2.7 },
	},

	-- Uncommon -------------------------------------------------------------------------------------------
	{
		id = "sushi_slug",
		displayName = "Sushi Slug",
		rarity = "Uncommon",
		price = 500,
		income = 12,
		beltWeight = 40,
		modelName = "SushiSlug",
		flavor = "Rolls everywhere. Literally.",
		look = { body = "Cylinder", bodyColor = "#F7F3EE", accent = "Shell", accentColor = "#FF7F50", size = 2.8 },
	},
	{
		id = "nacho_newt",
		displayName = "Nacho Newt",
		rarity = "Uncommon",
		price = 900,
		income = 20,
		beltWeight = 35,
		modelName = "NachoNewt",
		flavor = "Cheese-powered and proud.",
		look = { body = "Wedge", bodyColor = "#FFB627", accent = "Spots", accentColor = "#FFF2A8", size = 2.8 },
	},
	{
		id = "waffle_wombat",
		displayName = "Waffle Wombat",
		rarity = "Uncommon",
		price = 1500,
		income = 30,
		beltWeight = 25,
		modelName = "WaffleWombat",
		flavor = "Has a pocket for syrup.",
		look = { body = "Block", bodyColor = "#D9A35B", accent = "Ears", accentColor = "#7B4A1E", size = 2.9 },
	},

	-- Rare -----------------------------------------------------------------------------------------------
	{
		id = "taco_turtle",
		displayName = "Taco Turtle",
		rarity = "Rare",
		price = 4500,
		income = 65,
		beltWeight = 40,
		modelName = "TacoTurtle",
		flavor = "Slow, crunchy, unstoppable.",
		look = { body = "Ball", bodyColor = "#F2C14E", accent = "Shell", accentColor = "#5BBF3A", size = 3 },
	},
	{
		id = "burrito_bear",
		displayName = "Burrito Bear",
		rarity = "Rare",
		price = 8000,
		income = 110,
		beltWeight = 35,
		modelName = "BurritoBear",
		flavor = "Wrapped up and ready for a hug.",
		look = { body = "Cylinder", bodyColor = "#F3E1B6", accent = "Ears", accentColor = "#8C5A2B", size = 3.1 },
	},
	{
		id = "cupcake_cub",
		displayName = "Cupcake Cub",
		rarity = "Rare",
		price = 12500,
		income = 160,
		beltWeight = 25,
		modelName = "CupcakeCub",
		flavor = "Frosting first, questions later.",
		look = { body = "Cylinder", bodyColor = "#FF8FC7", accent = "Sprinkles", accentColor = "#FFFFFF", size = 3.1 },
	},

	-- Epic -----------------------------------------------------------------------------------------------
	{
		id = "ramen_raccoon",
		displayName = "Ramen Raccoon",
		rarity = "Epic",
		price = 60000,
		income = 400,
		beltWeight = 40,
		modelName = "RamenRaccoon",
		flavor = "Slurps louder than you'd think.",
		look = { body = "Ball", bodyColor = "#FFDD99", accent = "Ears", accentColor = "#5A5A66", size = 3.2 },
	},
	{
		id = "popcorn_penguin",
		displayName = "Popcorn Penguin",
		rarity = "Epic",
		price = 100000,
		income = 650,
		beltWeight = 35,
		modelName = "PopcornPenguin",
		flavor = "Pops when excited. Pops a lot.",
		look = { body = "Ball", bodyColor = "#FFF6D5", accent = "Wings", accentColor = "#2E3A59", size = 3.2 },
	},
	{
		id = "bagel_badger",
		displayName = "Bagel Badger",
		rarity = "Epic",
		price = 150000,
		income = 950,
		beltWeight = 25,
		modelName = "BagelBadger",
		flavor = "Everything bagel. Everything attitude.",
		look = { body = "Cylinder", bodyColor = "#C98A4B", accent = "Horns", accentColor = "#FFFFFF", size = 3.3 },
	},

	-- Legendary ------------------------------------------------------------------------------------------
	{
		id = "donut_dragon",
		displayName = "Donut Dragon",
		rarity = "Legendary",
		price = 1400000,
		income = 2800,
		beltWeight = 40,
		modelName = "DonutDragon",
		flavor = "Breathes powdered sugar.",
		look = { body = "Ball", bodyColor = "#FF77B7", accent = "Wings", accentColor = "#8E5CFF", size = 3.5 },
	},
	{
		id = "pancake_panda",
		displayName = "Pancake Panda",
		rarity = "Legendary",
		price = 2300000,
		income = 4500,
		beltWeight = 35,
		modelName = "PancakePanda",
		flavor = "A tall stack of chill.",
		look = { body = "Cylinder", bodyColor = "#F4C27A", accent = "Ears", accentColor = "#222222", size = 3.5 },
	},
	{
		id = "churro_cheetah",
		displayName = "Churro Cheetah",
		rarity = "Legendary",
		price = 3400000,
		income = 6500,
		beltWeight = 25,
		modelName = "ChurroCheetah",
		flavor = "Cinnamon-fast. Sugar-spotted.",
		look = { body = "Block", bodyColor = "#D98E3F", accent = "Spots", accentColor = "#6B3A12", size = 3.6 },
	},

	-- Mythic ---------------------------------------------------------------------------------------------
	{
		id = "lasagna_lion",
		displayName = "Lasagna Lion",
		rarity = "Mythic",
		price = 50000000,
		income = 35000,
		beltWeight = 60,
		modelName = "LasagnaLion",
		flavor = "King of the layers.",
		look = { body = "Block", bodyColor = "#E8743B", accent = "Crown", accentColor = "#FFD700", size = 3.9 },
	},
	{
		id = "dumpling_dino",
		displayName = "Dumpling Dino",
		rarity = "Mythic",
		price = 85000000,
		income = 56000,
		beltWeight = 40,
		modelName = "DumplingDino",
		flavor = "Steamed. Ancient. Adorable.",
		look = { body = "Ball", bodyColor = "#F5F0E1", accent = "Horns", accentColor = "#6FCF97", size = 4 },
	},

	-- Secret ---------------------------------------------------------------------------------------------
	{
		id = "gelato_griffin",
		displayName = "Gelato Griffin",
		rarity = "Secret",
		price = 1800000000,
		income = 360000,
		beltWeight = 60,
		modelName = "GelatoGriffin",
		flavor = "Never melts. Never forgets.",
		look = { body = "Ball", bodyColor = "#9BE7FF", accent = "Wings", accentColor = "#FFD1F0", size = 4.3 },
	},
	{
		id = "croissant_kraken",
		displayName = "Croissant Kraken",
		rarity = "Secret",
		price = 3200000000,
		income = 620000,
		beltWeight = 40,
		modelName = "CroissantKraken",
		flavor = "Flaky on the outside. Legendary on the inside.",
		look = { body = "Wedge", bodyColor = "#E0A84E", accent = "Crown", accentColor = "#B266FF", size = 4.4 },
	},
}

return Creatures
