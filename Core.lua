-- WhatToDo: ranks activities by gold per hour.
--   Farm.lua  - farm spots from Yield's saved sessions (YieldForeverDB or YieldDB), loot revalued at today's prices.
--   Craft.lua - buy reagents on the AH, craft, sell: the player's scanned recipes (Recipes.lua) plus
--               profession-free conversions (enchanting essences).
--   Prices.lua - Auctionator's public API (prices, age, vendor prices) plus its listed-quantity history.
--   UI.lua    - the window and /wtd.
local ADDON_NAME, ns = ...
ns.name = ADDON_NAME
_G.WhatToDo = ns -- for /dump and other addons

ns.DEFAULTS = {
	craftSeconds = 3,      -- cast time when a recipe's own isn't known
	craftOverhead = 1,     -- seconds per craft beyond the cast (clicks, stacking)
	batchOverhead = 240,   -- seconds per craft batch: getting to the AH, buying, posting
	maxBatch = 20,         -- most crafts planned per batch (the market rarely absorbs more at that price)
	supplyShare = 0.5,     -- share of a reagent's listed quantity assumed buyable at the scanned price
	minFarmMinutes = 10,   -- spots with less tracked time are too noisy to rank
	maxPriceAgeDays = 3,   -- skip crafts whose product or AH reagents were last scanned longer ago
	minProfit = 100,       -- copper per craft below which a recipe isn't worth listing
	ahCut = 0.05,
	results = 15,          -- rows per section
	essences = 1,          -- 1: include combining/splitting enchanting essences (no profession needed)
}

local function copyDefaults(into, from)
	for k, v in pairs(from) do
		if into[k] == nil then into[k] = v end
	end
end

function ns.Setting(key)
	local s = WhatToDoDB and WhatToDoDB.settings
	if s and s[key] ~= nil then return s[key] end
	return ns.DEFAULTS[key]
end

function ns.CharKey()
	return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

function ns.Out(msg) print("|cff33ff99WhatToDo|r: " .. tostring(msg)) end

-- "12g 34s" without icons, for chat and compact text.
function ns.Coin(copper)
	copper = math.floor((copper or 0) + 0.5)
	local neg = copper < 0
	if neg then copper = -copper end
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	local text
	if g > 0 then text = string.format("%dg %02ds", g, s)
	elseif s > 0 then text = string.format("%ds %02dc", s, c)
	else text = string.format("%dc", c) end
	return neg and ("-" .. text) or text
end

function ns.ItemName(itemID)
	local name = C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(itemID)
	if not name and GetItemInfo then name = GetItemInfo(itemID) end
	if not name then
		if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
		ns.pendingNames = true
		return "item:" .. itemID
	end
	return name
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, name)
	if event == "ADDON_LOADED" and name == ADDON_NAME then
		WhatToDoDB = type(WhatToDoDB) == "table" and WhatToDoDB or {}
		WhatToDoDB.settings = WhatToDoDB.settings or {}
		WhatToDoDB.recipes = WhatToDoDB.recipes or {}
		WhatToDoDB.chars = WhatToDoDB.chars or {}
		WhatToDoDB.version = 1
		copyDefaults(WhatToDoDB.settings, {}) -- defaults stay in ns.DEFAULTS; only changed values are saved
		self:UnregisterEvent("ADDON_LOADED")
		if ns.OnLoad then ns.OnLoad() end
	end
end)

-- All activities of one kind ("farm", "craft" or "learn"), or of every kind (nil / "all"), best first.
function ns.Rank(filter)
	local list = {}
	local all = (filter == nil or filter == "all")
	if (all or filter == "farm") and ns.FarmActivities then
		for _, a in ipairs(ns.FarmActivities()) do list[#list + 1] = a end
	end
	if (all or filter == "craft" or filter == "learn") and ns.CraftActivities then
		for _, a in ipairs(ns.CraftActivities()) do
			if all or a.kind == filter then list[#list + 1] = a end
		end
	end
	table.sort(list, function(a, b) return a.perHour > b.perHour end)
	return list
end
