-- Built-in catalog of simple trainer recrafts (low-grade material -> refined material), Classic 1.x data.
-- Used for characters whose professions are known from their skill list (Recipes.lua): a recipe counts as
-- craftable when the character's rank in the profession reaches `skill`, even if its trade skill window was
-- never opened; and for characters with a free primary profession slot it's shown as "learn this".
-- Scanned recipes (from the trade skill window) always win where both exist.
-- Each: profession (the skill line's name), skill (required rank), product, made, reagents { {itemID, count} }.
local _, ns = ...

local function r(profession, skill, product, made, reagents)
	return { profession = profession, skill = skill, product = product, made = made, reagents = reagents, catalog = true }
end

ns.CATALOG = {
	-- Mining: smelting
	r("Mining", 1, 2840, 1, { { 2770, 1 } }),                  -- Copper Bar <- Copper Ore
	r("Mining", 65, 3576, 1, { { 2771, 1 } }),                 -- Tin Bar <- Tin Ore
	r("Mining", 65, 2841, 2, { { 2840, 1 }, { 3576, 1 } }),    -- 2 Bronze Bar <- Copper Bar + Tin Bar
	r("Mining", 75, 2842, 1, { { 2775, 1 } }),                 -- Silver Bar <- Silver Ore
	r("Mining", 125, 3575, 1, { { 2772, 1 } }),                -- Iron Bar <- Iron Ore
	r("Mining", 155, 3577, 1, { { 2776, 1 } }),                -- Gold Bar <- Gold Ore
	r("Mining", 165, 3859, 1, { { 3575, 1 }, { 3857, 1 } }),   -- Steel Bar <- Iron Bar + Coal
	r("Mining", 175, 3860, 1, { { 3858, 1 } }),                -- Mithril Bar <- Mithril Ore
	r("Mining", 230, 6037, 1, { { 7911, 1 } }),                -- Truesilver Bar <- Truesilver Ore
	r("Mining", 250, 12359, 1, { { 10620, 1 } }),              -- Thorium Bar <- Thorium Ore

	-- Tailoring: bolts
	r("Tailoring", 1, 2996, 1, { { 2589, 2 } }),               -- Bolt of Linen Cloth
	r("Tailoring", 75, 2997, 1, { { 2592, 3 } }),              -- Bolt of Woolen Cloth
	r("Tailoring", 125, 4305, 1, { { 4306, 4 } }),             -- Bolt of Silk Cloth
	r("Tailoring", 175, 4339, 1, { { 4338, 5 } }),             -- Bolt of Mageweave
	r("Tailoring", 250, 14048, 1, { { 14047, 5 } }),           -- Bolt of Runecloth

	-- Leatherworking: leather upgrades
	r("Leatherworking", 1, 2318, 1, { { 2934, 3 } }),          -- Light Leather <- Ruined Leather Scraps
	r("Leatherworking", 100, 2319, 1, { { 2318, 4 } }),        -- Medium Leather <- Light Leather
	r("Leatherworking", 150, 4234, 1, { { 2319, 5 } }),        -- Heavy Leather <- Medium Leather
	r("Leatherworking", 250, 8170, 1, { { 4304, 5 } }),        -- Rugged Leather <- Thick Leather

	-- Blacksmithing: stones
	r("Blacksmithing", 1, 2862, 1, { { 2835, 1 } }),           -- Rough Sharpening Stone
	r("Blacksmithing", 25, 3470, 1, { { 2835, 2 } }),          -- Rough Grinding Stone
	r("Blacksmithing", 65, 2863, 1, { { 2836, 1 } }),          -- Coarse Sharpening Stone
	r("Blacksmithing", 75, 3478, 1, { { 2836, 2 } }),          -- Coarse Grinding Stone
	r("Blacksmithing", 125, 2871, 1, { { 2838, 1 } }),         -- Heavy Sharpening Stone
	r("Blacksmithing", 125, 3486, 1, { { 2838, 3 } }),         -- Heavy Grinding Stone
	r("Blacksmithing", 200, 7964, 1, { { 7912, 1 } }),         -- Solid Sharpening Stone
	r("Blacksmithing", 200, 7966, 1, { { 7912, 4 } }),         -- Solid Grinding Stone
	r("Blacksmithing", 250, 12404, 1, { { 12365, 1 } }),       -- Dense Sharpening Stone
	r("Blacksmithing", 250, 12644, 1, { { 12365, 4 } }),       -- Dense Grinding Stone

	-- Engineering: blasting powders
	r("Engineering", 1, 4357, 1, { { 2835, 1 } }),             -- Rough Blasting Powder
	r("Engineering", 75, 4364, 1, { { 2836, 1 } }),            -- Coarse Blasting Powder
	r("Engineering", 125, 4377, 1, { { 2838, 1 } }),           -- Heavy Blasting Powder
	r("Engineering", 175, 10505, 1, { { 7912, 2 } }),          -- Solid Blasting Powder
	r("Engineering", 250, 15992, 1, { { 12365, 2 } }),         -- Dense Blasting Powder
}

ns.PRIMARY = {
	Alchemy = true, Blacksmithing = true, Enchanting = true, Engineering = true, Herbalism = true,
	Leatherworking = true, Mining = true, Skinning = true, Tailoring = true,
}
ns.SECONDARY = { Cooking = true, ["First Aid"] = true, Fishing = true }
