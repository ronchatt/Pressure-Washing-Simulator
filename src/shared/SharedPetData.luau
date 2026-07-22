--!strict

export type PetDefinition = {
	Name: string,
	Rarity: string,
	Weight: number,
	CashMult: number,
	SpeedMult: number,
	Color: Color3,
	RarityColor: Color3,
}

export type OwnedPet = {
	UID: string,
	PetID: string,
}

local SharedPetData = {
	EggCost = 500,
	Pets = {
		Dog = {
			Name = "Dog", Rarity = "Common", Weight = 70, CashMult = 1.1, SpeedMult = 1.1,
			Color = Color3.fromRGB(174, 116, 68), RarityColor = Color3.fromRGB(76, 196, 235),
		},
		Cat = {
			Name = "Cat", Rarity = "Rare", Weight = 25, CashMult = 1.5, SpeedMult = 1.2,
			Color = Color3.fromRGB(119, 101, 151), RarityColor = Color3.fromRGB(176, 105, 239),
		},
		Dragon = {
			Name = "Dragon", Rarity = "Legendary", Weight = 5, CashMult = 2.5, SpeedMult = 1.5,
			Color = Color3.fromRGB(67, 175, 111), RarityColor = Color3.fromRGB(255, 196, 74),
		},
	} :: {[string]: PetDefinition},
	PetOrder = { "Dog", "Cat", "Dragon" },
}

return SharedPetData
