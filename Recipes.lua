-- Recipes: what each character can craft, read from the trade skill window whenever it's open, and kept
-- in WhatToDoDB.recipes[char][profession][recipeName]. Only the logged-in character's recipes, in
-- professions it still has, are offered (ns.AllRecipes).
-- Recipes under a collapsed header aren't listed by the game, so only expanded ones are recorded; known
-- ones are never dropped by a later, partial scan.
-- Enchanting (the Craft window) makes no items and isn't read.
local _, ns = ...

-- Combining essences needs no profession: right-click 3 lesser for 1 greater, or 1 greater for 3 lesser.
local ESSENCES = {
	{ 10938, 10939, "Magic" },
	{ 10998, 11082, "Astral" },
	{ 11134, 11135, "Mystic" },
	{ 11174, 11175, "Nether" },
	{ 16202, 16203, "Eternal" },
}

ns.CONVERSIONS = {}
for _, e in ipairs(ESSENCES) do
	local lesser, greater = e[1], e[2]
	table.insert(ns.CONVERSIONS, { product = greater, made = 1, reagents = { { lesser, 3 } }, castMs = 0, profession = "Essences" })
	table.insert(ns.CONVERSIONS, { product = lesser, made = 3, reagents = { { greater, 1 } }, castMs = 0, profession = "Essences" })
end

local function idFromLink(link)
	return link and tonumber(link:match("item:(%d+)"))
end

local function castMsOf(spellID)
	if not spellID then return nil end
	if C_Spell and C_Spell.GetSpellInfo then
		local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
		if ok and type(info) == "table" then return info.castTime end
	end
	if GetSpellInfo then
		local ok, _, _, _, castTime = pcall(GetSpellInfo, spellID)
		if ok then return castTime end
	end
end

local function scan()
	if not (GetTradeSkillLine and GetNumTradeSkills and WhatToDoDB) then return end
	local profession = GetTradeSkillLine()
	if not profession or profession == "UNKNOWN" then return end
	local n = GetNumTradeSkills() or 0
	if n == 0 then return end

	local char = WhatToDoDB.recipes[ns.CharKey()] or {}
	WhatToDoDB.recipes[ns.CharKey()] = char
	local known = char[profession] or {}
	char[profession] = known

	local added = 0
	for i = 1, n do
		local name, kind = GetTradeSkillInfo(i)
		if name and kind ~= "header" and kind ~= "subheader" then
			local product = idFromLink(GetTradeSkillItemLink(i))
			local reagents, complete = {}, true
			for j = 1, (GetTradeSkillNumReagents(i) or 0) do
				local _, _, count = GetTradeSkillReagentInfo(i, j)
				local reagent = idFromLink(GetTradeSkillReagentItemLink(i, j))
				if not reagent or not count then complete = false break end
				reagents[#reagents + 1] = { reagent, count }
			end
			if product and complete and #reagents > 0 then
				local minMade, maxMade = GetTradeSkillNumMade(i)
				minMade = minMade or 1
				local spellID
				local recipeLink = GetTradeSkillRecipeLink and GetTradeSkillRecipeLink(i)
				if recipeLink then spellID = tonumber(recipeLink:match("enchant:(%d+)") or recipeLink:match("spell:(%d+)")) end
				local cooldown = GetTradeSkillCooldown and GetTradeSkillCooldown(i)
				local old = known[name]
				if not old then added = added + 1 end
				known[name] = {
					product = product,
					made = (minMade + (maxMade or minMade)) / 2,
					reagents = reagents,
					castMs = castMsOf(spellID),
					-- sticky: a recipe seen on cooldown once (transmutes, Mooncloth) has one
					cooldown = (old and old.cooldown) or (cooldown and cooldown > 0) or nil,
				}
			end
		end
	end
	char._scanned = time()
	if added > 0 then
		ns.Out(string.format("%s: +%d recipes recorded.", profession, added))
		if ns.Refresh then ns.Refresh() end
	end
end

local scheduled = false
local function scheduleScan()
	if scheduled then return end
	scheduled = true
	C_Timer.After(0.5, function()
		scheduled = false
		scan()
	end)
end

local f = CreateFrame("Frame")
f:RegisterEvent("TRADE_SKILL_SHOW")
f:RegisterEvent("TRADE_SKILL_UPDATE")
f:SetScript("OnEvent", scheduleScan)

-- The trade skill window's name for a profession, when it isn't the skill's own (Mining opens "Smelting").
local WINDOW_TO_SKILL = { Smelting = "Mining" }

-- The current character's professions from the skill list, or nil when the list can't say for sure
-- (no API, or a collapsed header hiding some lines - then nothing is filtered rather than everything).
function ns.CurrentProfessions()
	if not (GetNumSkillLines and GetSkillLineInfo) then return nil end
	local set, seen = {}, 0
	for i = 1, GetNumSkillLines() or 0 do
		local name, isHeader, isExpanded = GetSkillLineInfo(i)
		if isHeader and not isExpanded then return nil end
		if name and not isHeader then set[name] = true; seen = seen + 1 end
	end
	return seen > 0 and set or nil
end

local function hasProfession(current, profession)
	if not current then return true end
	return current[profession] or current[WINDOW_TO_SKILL[profession] or profession] or false
end

-- The recipes the current character can craft now: its recorded professions that it still has,
-- plus the profession-free essence conversions (setting "essences"). { recipe, who = { name } } each.
function ns.AllRecipes()
	local out = {}
	if ns.Setting("essences") == 1 then
		for _, r in ipairs(ns.CONVERSIONS) do out[#out + 1] = { recipe = r, who = {} } end
	end
	local charKey = ns.CharKey()
	local professions = (WhatToDoDB and WhatToDoDB.recipes and WhatToDoDB.recipes[charKey]) or {}
	local current = ns.CurrentProfessions()
	local charName = charKey:match("^([^-]+)") or charKey
	for profession, recipes in pairs(professions) do
		if type(recipes) == "table" and hasProfession(current, profession) then
			for name, r in pairs(recipes) do
				r.name, r.profession = name, profession
				out[#out + 1] = { recipe = r, who = { profession } }
			end
		end
	end
	return out
end

-- Recipes counted for the status line: the current character's, in professions it still has.
function ns.RecipeCount()
	local count, professions = 0, 0
	local current = ns.CurrentProfessions()
	local mine = (WhatToDoDB and WhatToDoDB.recipes and WhatToDoDB.recipes[ns.CharKey()]) or {}
	for profession, list in pairs(mine) do
		if type(list) == "table" and hasProfession(current, profession) then
			professions = professions + 1
			for _ in pairs(list) do count = count + 1 end
		end
	end
	return count, professions
end
