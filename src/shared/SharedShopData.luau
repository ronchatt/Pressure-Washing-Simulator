--!strict

-- Display and validation metadata. The server validates ownership, cash, and
-- tier order before it writes any of these upgrades into a player profile.

local SharedProgressionData = require(script.Parent:WaitForChild("SharedProgressionData"))

export type Washer = {
	Name: string,
	Tier: number,
	UnlockLevel: number,
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

-- Dense, continuous driveway grime needs a much steeper progression curve
-- than small prop dirt. These values are total power relative to the starter:
-- Basic 1x, Heavy 4x, Professional 8x, Industrial 14x. Piecewise interpolation
-- also keeps future in-between washer tiers predictable.
local function getDrivewayPowerScale(cleanSpeed: number): number
	local rawScale = math.max(1, cleanSpeed / 0.5)
	if rawScale <= 1.5 then
		return 1 + (rawScale - 1) / 0.5 * 3
	elseif rawScale <= 2.3 then
		return 4 + (rawScale - 1.5) / 0.8 * 4
	end
	return 8 + math.clamp((rawScale - 2.3) / 1.7, 0, 1) * 6
end

local SharedShopData = {
	GetDrivewayPowerScale = getDrivewayPowerScale,
	Washers = SharedProgressionData.Washers :: {[string]: Washer},
	WasherOrder = SharedProgressionData.WasherOrder,
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
