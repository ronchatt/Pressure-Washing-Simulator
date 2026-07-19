--!strict

-- Staged map content. These models become Phone jobs only after the map
-- designer positions them and changes ReadyForPlacement/PhoneJobEnabled.

local SharedMapVariantData = {
	Houses = {
		{ ModelName = "House_Blue", FutureJobID = "SingleStoryHouse_01", Color = Color3.fromRGB(94, 165, 190) },
		{ ModelName = "House_Red", FutureJobID = "SingleStoryHouse_02", Color = Color3.fromRGB(184, 96, 87) },
		{ ModelName = "House_Yellow", FutureJobID = "SingleStoryHouse_03", Color = Color3.fromRGB(207, 172, 91) },
		{ ModelName = "House_Green", FutureJobID = "SingleStoryHouse_04", Color = Color3.fromRGB(105, 163, 119) },
		{ ModelName = "House_Lavender", FutureJobID = "SingleStoryHouse_05", Color = Color3.fromRGB(153, 125, 184) },
	},
	Cars = {
		{ ModelName = "Car_Red", FutureJobID = "Car_01", Color = Color3.fromRGB(190, 55, 48) },
		{ ModelName = "Car_Blue", FutureJobID = "Car_02", Color = Color3.fromRGB(48, 104, 184) },
		{ ModelName = "Car_Green", FutureJobID = "Car_03", Color = Color3.fromRGB(66, 139, 91) },
		{ ModelName = "Car_Black", FutureJobID = "Car_04", Color = Color3.fromRGB(35, 37, 42) },
		{ ModelName = "Car_White", FutureJobID = "Car_05", Color = Color3.fromRGB(220, 222, 218) },
	},
}

return SharedMapVariantData
