--!strict

export type PetDefinition = {
	Name: string,
	Rarity: string,
	Weight: number,
	CashMult: number,
	SpeedMult: number,
}

local SharedPetData = {
	-- Development override. Restore a production price before release.
	EggCost = 0,
	Pets = {
		Dog = { Name = "Dog", Rarity = "Common", Weight = 70, CashMult = 1.1, SpeedMult = 1.1 },
		Cat = { Name = "Cat", Rarity = "Rare", Weight = 25, CashMult = 1.5, SpeedMult = 1.2 },
		Dragon = { Name = "Dragon", Rarity = "Legendary", Weight = 5, CashMult = 2.5, SpeedMult = 1.5 },
	} :: {[string]: PetDefinition},
	PetOrder = { "Dog", "Cat", "Dragon" },
}

return SharedPetData
