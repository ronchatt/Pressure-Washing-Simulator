--!strict

-- Display and validation metadata. The server validates ownership, cash, and
-- tier order before it writes any of these upgrades into a player profile.

export type Washer = {
	Name: string,
	Tier: number,
	Cost: number,
	CleanSpeed: number,
	SprayWidth: number,
	WaterEfficiency: number,
	EffectiveRange: number,
	AccentColor: Color3,
	Description: string,
	RequiredWasher: string?,
}
export type Truck = { Name: string, Cost: number }
export type TankTier = { Name: string, Cost: number, RequiredMaxWater: number, NewMaxWater: number }

local SharedShopData = {
	Washers = {
		["Basic Backpack"] = {
			Name = "Basic Backpack",
			Tier = 1,
			Cost = 0,
			CleanSpeed = 0.5,
			SprayWidth = 1,
			WaterEfficiency = 1,
			EffectiveRange = 1,
			AccentColor = Color3.fromRGB(45, 128, 190),
			Description = "Reliable starter washer",
		},
		["Heavy Duty Washer"] = {
			Name = "Heavy Duty Washer",
			Tier = 2,
			Cost = 500,
			CleanSpeed = 0.75,
			SprayWidth = 1.2,
			WaterEfficiency = 1.15,
			EffectiveRange = 1.15,
			AccentColor = Color3.fromRGB(235, 151, 49),
			Description = "Wider and more efficient",
			RequiredWasher = "Basic Backpack",
		},
		["Professional Washer"] = {
			Name = "Professional Washer",
			Tier = 3,
			Cost = 2_000,
			CleanSpeed = 1.15,
			SprayWidth = 1.5,
			WaterEfficiency = 1.35,
			EffectiveRange = 1.3,
			AccentColor = Color3.fromRGB(59, 201, 122),
			Description = "Professional cleaning coverage",
			RequiredWasher = "Heavy Duty Washer",
		},
		["Industrial Washer"] = {
			Name = "Industrial Washer",
			Tier = 4,
			Cost = 7_500,
			CleanSpeed = 2,
			SprayWidth = 1.9,
			WaterEfficiency = 1.7,
			EffectiveRange = 1.5,
			AccentColor = Color3.fromRGB(172, 91, 235),
			Description = "Maximum commercial pressure",
			RequiredWasher = "Professional Washer",
		},
	} :: {[string]: Washer},
	WasherOrder = { "Basic Backpack", "Heavy Duty Washer", "Professional Washer", "Industrial Washer" },
	Trucks = {
		["Basic Pickup"] = { Name = "Basic Pickup", Cost = 0 },
		["Flatbed Truck"] = { Name = "Flatbed Truck", Cost = 1000 },
	} :: {[string]: Truck},
	Tanks = {
		Level2Tank = { Name = "Level 2 Tank", Cost = 250, RequiredMaxWater = 100, NewMaxWater = 150 },
		Level3Tank = { Name = "Level 3 Tank", Cost = 500, RequiredMaxWater = 150, NewMaxWater = 250 },
	} :: {[string]: TankTier},
	TankOrder = { "Level2Tank", "Level3Tank" },
}

return SharedShopData
