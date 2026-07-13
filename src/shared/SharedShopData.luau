--!strict

-- Display and validation metadata. The server validates ownership, cash, and
-- tier order before it writes any of these upgrades into a player profile.

export type Washer = { Name: string, Cost: number, CleanSpeed: number }
export type Truck = { Name: string, Cost: number }
export type TankTier = { Name: string, Cost: number, RequiredMaxWater: number, NewMaxWater: number }

local SharedShopData = {
	Washers = {
		["Basic Backpack"] = { Name = "Basic Backpack", Cost = 0, CleanSpeed = 0.5 },
		["Heavy Duty Washer"] = { Name = "Heavy Duty Washer", Cost = 500, CleanSpeed = 1.0 },
	} :: {[string]: Washer},
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
