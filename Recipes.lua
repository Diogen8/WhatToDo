-- Recipes: what each character can craft, read from the trade skill window whenever it's open, and kept
-- in WhatToDoDB.recipes[char][profession][recipeName]. Every character's recipes count, in professions it
-- still has; the built-in catalog (Catalog.lua) fills in what their ranks reach and what they could learn.
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

-- One recipe into the character's list for its profession. Returns true when it's new.
local function store(profession, name, product, made, reagents, castMs, onCooldown)
	local char = WhatToDoDB.recipes[ns.CharKey()] or {}
	WhatToDoDB.recipes[ns.CharKey()] = char
	local known = char[profession] or {}
	char[profession] = known
	local old = known[name]
	known[name] = {
		product = product,
		made = made,
		reagents = reagents,
		castMs = castMs,
		-- sticky: a recipe seen on cooldown once (transmutes, Mooncloth) has one
		cooldown = (old and old.cooldown) or onCooldown or nil,
	}
	return old == nil
end

-- The old trade skill API (Classic Era): GetTradeSkillLine, GetNumTradeSkills, GetTradeSkillInfo, ...
local function scanLegacy()
	if not (GetTradeSkillLine and GetNumTradeSkills and GetTradeSkillInfo) then return nil end
	local profession = GetTradeSkillLine()
	if not profession or profession == "UNKNOWN" then return nil end
	local n = GetNumTradeSkills() or 0
	if n == 0 then return nil end
	local added, seen = 0, 0
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
				seen = seen + 1
				local minMade, maxMade = GetTradeSkillNumMade(i)
				minMade = minMade or 1
				local spellID
				local recipeLink = GetTradeSkillRecipeLink and GetTradeSkillRecipeLink(i)
				if recipeLink then spellID = tonumber(recipeLink:match("enchant:(%d+)") or recipeLink:match("spell:(%d+)")) end
				local cooldown = GetTradeSkillCooldown and GetTradeSkillCooldown(i)
				if store(profession, name, product, (minMade + (maxMade or minMade)) / 2, reagents, castMsOf(spellID), cooldown and cooldown > 0) then
					added = added + 1
				end
			end
		end
	end
	return profession, added, seen
end

-- The modern trade skill API (WoW Forever uses it): C_TradeSkillUI recipe IDs and schematics.
local function call(f, ...)
	if not f then return nil end
	local ok, a = pcall(f, ...)
	if ok then return a end
end

local function modernProfession()
	local T = C_TradeSkillUI
	for _, getter in ipairs({ "GetBaseProfessionInfo", "GetChildProfessionInfo" }) do
		local info = call(T[getter])
		local name = type(info) == "table" and (info.parentProfessionName or info.professionName)
		if name and name ~= "" then return name end
	end
	local name = call(GetTradeSkillLine)
	if name and name ~= "" and name ~= "UNKNOWN" then return name end
end

local function scanModern()
	local T = C_TradeSkillUI
	if not (T and T.GetAllRecipeIDs and T.GetRecipeSchematic) then return nil end
	local ids = call(T.GetAllRecipeIDs)
	if type(ids) ~= "table" or #ids == 0 then return nil end
	local profession = modernProfession()
	if not profession then return nil end
	local added, seen = 0, 0
	for _, recipeID in ipairs(ids) do
		local info = T.GetRecipeInfo and call(T.GetRecipeInfo, recipeID)
		if not (type(info) == "table" and info.learned == false) then
			local schematic = call(T.GetRecipeSchematic, recipeID, false)
			local product = type(schematic) == "table" and schematic.outputItemID
			if product then
				local reagents, complete = {}, true
				for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
					-- basic reagents only (type 1); optional / finishing slots don't block a craft
					local basic = slot.reagentType == nil or slot.reagentType == 1
					if basic and slot.required ~= false then
						local first = slot.reagents and slot.reagents[1]
						local reagent = first and first.itemID
						if not reagent or not slot.quantityRequired then complete = false break end
						reagents[#reagents + 1] = { reagent, slot.quantityRequired }
					end
				end
				if complete and #reagents > 0 then
					seen = seen + 1
					local minMade = schematic.quantityMin or 1
					local maxMade = schematic.quantityMax or minMade
					local cooldown = T.GetRecipeCooldown and call(T.GetRecipeCooldown, recipeID)
					local name = schematic.name or (type(info) == "table" and info.name) or ("recipe " .. recipeID)
					if store(profession, name, product, (minMade + maxMade) / 2, reagents, castMsOf(recipeID), type(cooldown) == "number" and cooldown > 0) then
						added = added + 1
					end
				end
			end
		end
	end
	return profession, added, seen
end

ns.lastScan = nil -- what the last scan found, for /wtd debug

local function scan()
	if not WhatToDoDB then return end
	local profession, added, seen = scanModern()
	local api = "C_TradeSkillUI"
	if not profession then
		profession, added, seen = scanLegacy()
		api = "legacy"
	end
	if not profession then
		ns.lastScan = { time = time(), result = "nothing read" }
		return
	end
	local char = WhatToDoDB.recipes[ns.CharKey()]
	if char then char._scanned = time() end
	ns.lastScan = { time = time(), api = api, profession = profession, seen = seen, added = added }
	if added > 0 then
		ns.Out(string.format("%s: +%d рецептів записано.", profession, added))
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

-- Events differ between clients; an unknown event name errors, so each is tried on its own.
local function register(frame, events)
	for _, event in ipairs(events) do pcall(frame.RegisterEvent, frame, event) end
end

local f = CreateFrame("Frame")
register(f, { "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED" })
f:SetScript("OnEvent", scheduleScan)

-- The trade skill window's name for a profession, when it isn't the skill's own (Mining opens "Smelting").
local WINDOW_TO_SKILL = { Smelting = "Mining" }

---------------------------------------------------------------------------
-- Characters' professions: read from the skill list on login and whenever it changes, kept in
-- WhatToDoDB.chars[charKey] = { name, professions = { [skillName] = rank }, updated } so alts count while
-- logged out. A collapsed header hides lines: then what's seen is merged in and nothing is dropped.
---------------------------------------------------------------------------

-- The skill list as { name, isHeader, collapsed, rank } rows: C_SkillInfo on WoW Forever (it replaced the
-- global skill line API), the old globals elsewhere. nil when neither exists.
local function skillLines()
	local rows = {}
	if C_SkillInfo and C_SkillInfo.GetNumSkillLines and C_SkillInfo.GetSkillLineInfo then
		for i = 1, call(C_SkillInfo.GetNumSkillLines) or 0 do
			local line = call(C_SkillInfo.GetSkillLineInfo, i)
			if type(line) == "table" then
				rows[#rows + 1] = { name = line.name, isHeader = line.isHeader, collapsed = line.isHeader and line.isCollapsed, rank = line.rank }
			end
		end
		return rows, "C_SkillInfo"
	end
	if GetNumSkillLines and GetSkillLineInfo then
		for i = 1, GetNumSkillLines() or 0 do
			local name, isHeader, isExpanded, rank = GetSkillLineInfo(i)
			rows[#rows + 1] = { name = name, isHeader = isHeader, collapsed = isHeader and not isExpanded, rank = rank }
		end
		return rows, "legacy"
	end
end
ns.SkillLines = skillLines

local function recordSkills()
	if not WhatToDoDB then return end
	local rows = skillLines()
	if not rows then return end
	local seen, complete = {}, true
	for _, row in ipairs(rows) do
		if row.collapsed then complete = false end
		if row.name and not row.isHeader and (ns.PRIMARY[row.name] or ns.SECONDARY[row.name]) then seen[row.name] = row.rank or 0 end
	end
	WhatToDoDB.chars = WhatToDoDB.chars or {}
	local key = ns.CharKey()
	local c = WhatToDoDB.chars[key] or {}
	WhatToDoDB.chars[key] = c
	c.name = UnitName("player")
	if complete then
		c.professions = seen
	else
		c.professions = c.professions or {}
		for name, rank in pairs(seen) do c.professions[name] = rank end
	end
	c.updated = time()
	-- a profession dropped: its recorded recipes go too
	if complete and WhatToDoDB.recipes[key] then
		for profession, list in pairs(WhatToDoDB.recipes[key]) do
			if type(list) == "table" and not seen[WINDOW_TO_SKILL[profession] or profession] then
				WhatToDoDB.recipes[key][profession] = nil
			end
		end
	end
	if ns.Refresh then ns.Refresh() end
end
ns.RecordSkills = recordSkills

-- "Diogen (Blacksmithing 210, Mining 230), Trader (—)" for messages.
function ns.KnownCharsText()
	local parts = {}
	for _, c in pairs((WhatToDoDB and WhatToDoDB.chars) or {}) do
		local profs = {}
		for name, rank in pairs(c.professions or {}) do profs[#profs + 1] = string.format("%s %d", name, rank) end
		table.sort(profs)
		parts[#parts + 1] = string.format("%s (%s)", c.name or "?", #profs > 0 and table.concat(profs, ", ") or "—")
	end
	table.sort(parts)
	return #parts > 0 and table.concat(parts, "; ") or "ще жодного (зайдіть кожним персонажем)"
end

local skillsScheduled = false
local sk = CreateFrame("Frame")
register(sk, { "PLAYER_ENTERING_WORLD", "SKILL_LINES_CHANGED", "SKILL_LINE_SPECS_RANKS_CHANGED" })
sk:SetScript("OnEvent", function()
	if skillsScheduled then return end
	skillsScheduled = true
	C_Timer.After(1, function()
		skillsScheduled = false
		recordSkills()
	end)
end)

local function shortName(charKey)
	local c = WhatToDoDB.chars and WhatToDoDB.chars[charKey]
	return (c and c.name) or charKey:match("^([^-]+)") or charKey
end

local function primaryCount(professions)
	local n = 0
	for name in pairs(professions) do
		if ns.PRIMARY[name] then n = n + 1 end
	end
	return n
end

---------------------------------------------------------------------------
-- Every recrafting option, merged by what it uses and makes:
--   { recipe, section = "craft" | "learn", who = { "Name" or "Name (Profession)" , ... } }
-- craft: essence conversions; each character's scanned recipes in professions it still has; catalog recipes
--        its rank already reaches.
-- learn: catalog recipes in professions a character with a free primary slot doesn't have.
---------------------------------------------------------------------------

function ns.AllRecipes()
	local merged, order = {}, {}
	local function add(r, section, who)
		local parts = { section, r.product, string.format("%g", r.made or 1) }
		for _, rg in ipairs(r.reagents) do parts[#parts + 1] = rg[1] .. "x" .. rg[2] end
		local key = table.concat(parts, ":")
		local entry = merged[key]
		if not entry then
			entry = { recipe = r, section = section, who = {}, seen = {} }
			merged[key] = entry
			order[#order + 1] = entry
		elseif r.catalog == nil and entry.recipe.catalog then
			entry.recipe = r -- a scanned recipe knows its real cast time and yield
		end
		if who and not entry.seen[who] then
			entry.seen[who] = true
			entry.who[#entry.who + 1] = who
		end
	end

	if ns.Setting("essences") == 1 then
		for _, r in ipairs(ns.CONVERSIONS) do add(r, "craft", nil) end
	end
	if not WhatToDoDB then return order end
	local chars = WhatToDoDB.chars or {}

	-- scanned recipes (characters whose professions were never read keep all of theirs)
	for charKey, professions in pairs(WhatToDoDB.recipes or {}) do
		local known = chars[charKey] and chars[charKey].professions
		for profession, recipes in pairs(professions) do
			local skill = WINDOW_TO_SKILL[profession] or profession
			if type(recipes) == "table" and (not known or known[skill]) then
				for name, r in pairs(recipes) do
					r.name, r.profession = name, skill
					add(r, "craft", shortName(charKey))
				end
			end
		end
	end

	-- catalog: what each character's ranks reach, and what free slots could learn
	for charKey, c in pairs(chars) do
		local professions = c.professions or {}
		local free = primaryCount(professions) < 2
		for _, r in ipairs(ns.CATALOG) do
			local rank = professions[r.profession]
			if rank then
				if rank >= r.skill then add(r, "craft", shortName(charKey)) end
			elseif free then
				add(r, "learn", shortName(charKey))
			end
		end
	end
	return order
end

-- For the status line: scanned recipes and characters with known professions.
function ns.RecipeCount()
	local count, chars = 0, 0
	for _, professions in pairs((WhatToDoDB and WhatToDoDB.recipes) or {}) do
		for _, list in pairs(professions) do
			if type(list) == "table" then
				for _ in pairs(list) do count = count + 1 end
			end
		end
	end
	for _ in pairs((WhatToDoDB and WhatToDoDB.chars) or {}) do chars = chars + 1 end
	return count, chars
end
