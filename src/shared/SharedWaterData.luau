--!strict

-- Display metadata only. WaterEconomyManager owns the authoritative costs,
-- distance checks, cash deductions, and active-job reward modifier.

local SharedWaterData = {
	RefillTypes = {
		Base = {
			Name = "Base Water Station",
			Description = "Cheapest full-tank refill",
			CashCost = 5,
			CustomerPayCut = 0,
		},
		Hydrant = {
			Name = "City Fire Hydrant",
			Description = "Convenient full-tank refill",
			CashCost = 20,
			CustomerPayCut = 0,
		},
		Customer = {
			Name = "Customer Water",
			Description = "Free water for a reduced job payout",
			CashCost = 0,
			CustomerPayCut = 0.15,
		},
	},
	MaxInteractionDistance = 14,
}

return SharedWaterData
