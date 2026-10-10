--!strict
--[[
	The Snackling catalogue. Plain data only.

	price       cash cost on the conveyor (the server always uses THIS value, never a client-sent one)
	income      base cash per second while on a podium (before rebirth / pass / event multipliers)
	beltWeight  relative chance within its rarity tier
	modelName   name of a Model in ReplicatedStorage.CreatureModels to use instead of the code-built model
	eventId     optional: only spawns while the LiveOps event with this id is active (limited-time creatures)

	How each one looks (its 3D model recipe) lives in Config/CreatureLooks, keyed by id.
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
	},

	-- Event: Halloween 2026 ------------------------------------------------------------------------------
	-- Only spawn while LiveOps event "Halloween2026" runs (they share their tier's odds with the regular
	-- Snacklings, see BALANCE.md "Halloween"). Owned ones keep earning forever after the event ends.
	-- Keep these after every regular creature: appending keeps the regular belt rolls identical outside events.
	{
		id = "candy_corn_cat",
		displayName = "Candy Corn Cat",
		rarity = "Rare",
		price = 10000,
		income = 135,
		beltWeight = 30,
		modelName = "CandyCornCat",
		flavor = "Nine lives, three stripes, zero chill.",
		eventId = "Halloween2026",
	},
	{
		id = "pumpkin_pie_bat",
		displayName = "Pumpkin Pie Bat",
		rarity = "Epic",
		price = 120000,
		income = 780,
		beltWeight = 30,
		modelName = "PumpkinPieBat",
		flavor = "Hangs upside down. Never drops a crumb.",
		eventId = "Halloween2026",
	},
	{
		id = "caramel_apple_ghoul",
		displayName = "Caramel Apple Ghoul",
		rarity = "Legendary",
		price = 2800000,
		income = 5500,
		beltWeight = 30,
		modelName = "CaramelAppleGhoul",
		flavor = "Sticky fingers. Stickier grin.",
		eventId = "Halloween2026",
	},
	{
		id = "jack_o_lantern_latte",
		displayName = "Jack-o'-Lantern Latte",
		rarity = "Mythic",
		price = 70000000,
		income = 47000,
		beltWeight = 40,
		modelName = "JackOLanternLatte",
		flavor = "Extra foam, extra boo.",
		eventId = "Halloween2026",
	},
}

return Creatures
