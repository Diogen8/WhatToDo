-- Farm spots from Yield's history, split by category (mobs, mining, herbalism, fishing, skinning). Yield stores per dataset (each saved session and the live one):
--   ds.time[mapID][subzone] = tracked seconds
--   ds.sources[key] = { kind = "mob"|"mining"|"herbalism"|"chest"|"container"|"fishing"|...,
--                       locations[mapID][subzone].solo|group = { kills, money, skins, items = {id = n}, skinItems = {id = n} } }
-- Every character's sessions are summed per spot (zone + subzone) and the loot is valued at today's prices,
-- through Yield's own ItemPrice when Yield is loaded (same AH cut, stale and exclusion rules as its window).
local _, ns = ...
local T = function(s) return ns.T(s) end

local SKIP_KINDS = { purchase = true, quest = true, mail = true, trade = true, vendor = true }
local GATHER = { mining = true, herbalism = true, fishing = true }
local MAX_LEVEL_ABOVE = 2 -- mob farming spots whose mobs are more than this above the character are left out
local MIN_GATHERS = 3 -- fewer gathers at a spot than this is a stray node, not a route
local GATHER_LABEL = { mining = "Жил", herbalism = "Трав", fishing = "Закидів", skinning = "Шкур" }
local RATE_UNIT = { mining = "жил", herbalism = "трав", fishing = "закидів", skinning = "шкур" }
local CAT_NAME = { farm = "моби", mining = "майнінг", herbalism = "трави", fishing = "риболовля", skinning = "скінінг" }

local function yieldDB()
	if type(YieldForeverDB) == "table" then return YieldForeverDB end
	if type(YieldDB) == "table" then return YieldDB end
end

local function yieldAddon()
	local AceAddon = LibStub and LibStub("AceAddon-3.0", true)
	if not AceAddon then return nil end
	return AceAddon:GetAddon("YieldForever", true) or AceAddon:GetAddon("Yield", true)
end

function ns.HasYield() return yieldDB() ~= nil end
function ns.YieldData() return yieldDB() end

-- Copper one looted unit is worth now.
local function valueOf(itemID, yield, cache)
	local v = cache[itemID]
	if v then return v end
	v = nil
	if yield and yield.ItemPrice then
		local ok, price = pcall(yield.ItemPrice, yield, itemID)
		if ok and type(price) == "number" then v = price end
	end
	if not v then
		v = ns.SellNet(itemID)
		if not v then
			local info = { (C_Item and C_Item.GetItemInfo or GetItemInfo)(itemID) }
			v = info[11] or 0
		end
	end
	cache[itemID] = v
	return v
end

---------------------------------------------------------------------------
-- Mob levels: the built-in table (MobLevels.lua, extracted once from QuestieDB data; no runtime dependency), widened
-- by what WhatToDo saw on targets, mouseover and nameplates (WhatToDoDB.mobLevels[npcID] = { lo, hi }), which also
-- covers mobs the table lacks. A skull (level -1) counts as 99.
---------------------------------------------------------------------------

local builtin
local function builtinLevels(npcID)
	if not builtin then
		builtin = {}
		for id, lo, hi in (ns.MOB_LEVEL_DATA or ""):gmatch("(%d+),(%d+),?(%d*)") do
			lo = tonumber(lo)
			builtin[tonumber(id)] = { lo, tonumber(hi) or lo }
		end
		ns.MOB_LEVEL_DATA = nil -- the parsed table replaces the string
	end
	local t = builtin[npcID]
	if t then return t[1], t[2] end
end

function ns.MobLevels(npcID)
	local lo, hi = builtinLevels(npcID)
	local seen = WhatToDoDB and WhatToDoDB.mobLevels and WhatToDoDB.mobLevels[npcID]
	if seen then
		if lo then return math.min(lo, seen[1]), math.max(hi, seen[2]) end
		return seen[1], seen[2]
	end
	return lo, hi
end

local function rememberLevel(unit)
	if not (WhatToDoDB and UnitExists and UnitExists(unit)) or UnitIsPlayer(unit) then return end
	local guid = UnitGUID(unit)
	local id = type(guid) == "string" and tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)"))
	local level = UnitLevel(unit)
	if not id or type(level) ~= "number" then return end
	if level <= 0 then level = 99 end
	WhatToDoDB.mobLevels = WhatToDoDB.mobLevels or {}
	local t = WhatToDoDB.mobLevels[id]
	if t then
		t[1], t[2] = math.min(t[1], level), math.max(t[2], level)
	else
		WhatToDoDB.mobLevels[id] = { level, level }
	end
end

local levelWatch = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED" }) do
	pcall(levelWatch.RegisterEvent, levelWatch, event)
end
levelWatch:SetScript("OnEvent", function(_, event, unit)
	-- unit values can be restricted in some places on newer clients: never let that break anything
	pcall(rememberLevel, event == "PLAYER_TARGET_CHANGED" and "target" or event == "UPDATE_MOUSEOVER_UNIT" and "mouseover" or unit)
end)

---------------------------------------------------------------------------
-- Where on the map a spot is. Yield keeps only zone + subzone, so WhatToDo notes the player's position
-- whenever loot opens (kills, nodes, herbs, skins, fish) and keeps a running centre per zone map + subzone:
--   WhatToDoDB.spotPos[mapID][subzone] = { x, y, n }   (x, y in 0..1 on the zone map, the same map Yield keys by)
---------------------------------------------------------------------------

-- Yield's spot map: the zone above any cave or building micro map.
local function zoneMap(mapID)
	local micro = Enum and Enum.UIMapType and Enum.UIMapType.Micro
	local info = mapID and C_Map.GetMapInfo(mapID)
	while info and info.mapType == micro and info.parentMapID and info.parentMapID ~= 0 do
		mapID = info.parentMapID
		info = C_Map.GetMapInfo(mapID)
	end
	return mapID
end

local function rememberPosition()
	if not WhatToDoDB or IsInInstance() or not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return end
	local mapID = zoneMap(C_Map.GetBestMapForUnit("player"))
	local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	if not pos then return end
	local x, y = pos:GetXY()
	if not x or (x == 0 and y == 0) then return end
	local sub = GetSubZoneText() or ""
	WhatToDoDB.spotPos = WhatToDoDB.spotPos or {}
	local zone = WhatToDoDB.spotPos[mapID] or {}
	WhatToDoDB.spotPos[mapID] = zone
	local p = zone[sub]
	if not p then zone[sub] = { x = x, y = y, n = 1 } return end
	local n = math.min(p.n + 1, 100) -- a running mean that keeps following where the farming now happens
	p.x, p.y, p.n = p.x + (x - p.x) / n, p.y + (y - p.y) / n, n
end

local posWatch = CreateFrame("Frame")
pcall(posWatch.RegisterEvent, posWatch, "LOOT_OPENED")
posWatch:SetScript("OnEvent", function() pcall(rememberPosition) end)

-- Click on a farming or gathering row: open the world map on its zone and pin the spot's centre.
function ns.ShowSpotOnMap(a)
	local mapID, sub = a.mapID, a.subzone or ""
	if not mapID or mapID < 0 then
		ns.Out(T("Це підземелля - на мапі світу його не показати."))
		return
	end
	local zone = WhatToDoDB and WhatToDoDB.spotPos and WhatToDoDB.spotPos[mapID]
	local p = zone and zone[sub]
	if OpenWorldMap then
		OpenWorldMap(mapID)
	elseif WorldMapFrame then
		if not WorldMapFrame:IsShown() then ToggleWorldMap() end
		WorldMapFrame:SetMapID(mapID)
	end
	if p and C_Map.SetUserWaypoint and UiMapPoint then
		pcall(function()
			C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, p.x, p.y))
			if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
		end)
		ns.Out(string.format(T("%s: позначено на мапі (%.0f, %.0f)."), a.title, p.x * 100, p.y * 100))
	elseif p then
		ns.Out(string.format(T("%s: координати %.0f, %.0f."), a.title, p.x * 100, p.y * 100))
	else
		ns.Out(string.format(T("%s: точку ще не знаю - вона з'явиться після першого лута там. Підзона: %s."), a.title, sub ~= "" and sub or "-"))
	end
end

-- A spot's mob level: the kill-weighted median of its mobs' lowest levels, and the range of the mobs that make up
-- at least a tenth of the kills. nil when no level is known.
local function spotMobLevel(c)
	local list, total = {}, 0
	for key, n in pairs(c.sources or {}) do
		local id = tonumber(key:match("^c:(%d+)$"))
		local lo, hi
		if id then lo, hi = ns.MobLevels(id) end
		if lo and n > 0 then
			list[#list + 1] = { lo = lo, hi = hi, n = n }
			total = total + n
		end
	end
	if total == 0 then return nil end
	table.sort(list, function(a, b) return a.lo < b.lo end)
	local acc, median = 0, list[#list].lo
	for _, e in ipairs(list) do
		acc = acc + e.n
		if acc >= total / 2 then median = e.lo break end
	end
	local lo, hi
	for _, e in ipairs(list) do
		if e.n >= total * 0.1 then
			lo, hi = math.min(lo or e.lo, e.lo), math.max(hi or e.hi, e.hi)
		end
	end
	return median, lo or median, hi or median
end

-- Today's value of one spot category ({ money, items }): coin plus loot at today's prices, corrected by real sales.
function ns.CategoryValue(c, cache)
	local yield = yieldAddon()
	local value = c.money or 0
	for itemID, count in pairs(c.items or {}) do
		value = value + valueOf(itemID, yield, cache) * count * ns.SellFactor(itemID)
	end
	return value
end

local function zoneName(db, mapID)
	local names = db.names and db.names.zones
	if names and names[mapID] then return names[mapID] end
	if mapID > 0 and C_Map and C_Map.GetMapInfo then
		local info = C_Map.GetMapInfo(mapID)
		if info and info.name then return info.name end
	end
	return (mapID < 0 and "Instance " or "Map ") .. math.abs(mapID)
end

local function sourceName(db, key)
	local kind, id = key:match("^(%a):(%d+)$")
	id = tonumber(id)
	local names = db.names or {}
	if kind == "c" then return (names.creatures or {})[id] or ("NPC " .. id) end
	if kind == "o" then return (names.objects or {})[id] or ("Object " .. id) end
	if kind == "i" then return ns.ItemName(id) end
	return key
end

-- Every spot from Yield (all characters) and, when includeShared, from data friends shared (Share.lua):
-- spots[mapID .. "\t" .. subzone] = { mapID, subzone, seconds, chars = { name = seconds }, cats = { cat = {
--   money, count, items = { id = n }, sources = { key = n } } }, zoneName (shared spots) }.
-- keep(ds, char): optional filter over Yield datasets (Episodes.lua backtests one session against earlier ones).
function ns.CollectSpots(includeShared, keep)
	local db = yieldDB()

	-- Each spot's income split by where it came from (its category):
	--   farm: mob loot and coin, chests and containers; mining, herbalism, fishing: those gathers;
	--   skinning: what skinned corpses gave (Yield keeps it apart from the mob's loot).
	local spots = {}
	local function category(s, cat)
		local c = s.cats[cat]
		if not c then
			c = { money = 0, items = {}, count = 0, sources = {} }
			s.cats[cat] = c
		end
		return c
	end
	local function spot(mapID, subzone)
		local key = mapID .. "\t" .. subzone
		local s = spots[key]
		if not s then
			s = { mapID = mapID, subzone = subzone, seconds = 0, chars = {}, cats = {} }
			spots[key] = s
		end
		return s
	end
	local function addItems(into, items)
		for itemID, count in pairs(items or {}) do into[itemID] = (into[itemID] or 0) + count end
	end
	local function addDataset(ds, charName)
		for mapID, subzones in pairs(ds.time or {}) do
			for subzone, seconds in pairs(subzones) do
				if type(seconds) == "number" then
					local s = spot(mapID, subzone)
					s.seconds = s.seconds + seconds
					s.chars[charName] = (s.chars[charName] or 0) + seconds
				end
			end
		end
		for key, source in pairs(ds.sources or {}) do
			if not SKIP_KINDS[source.kind] then
				local cat = GATHER[source.kind] and source.kind or "farm"
				for mapID, zone in pairs(source.locations or {}) do
					for subzone, modes in pairs(zone) do
						local s = spot(mapID, subzone)
						for _, b in pairs(modes) do
							local c = category(s, cat)
							c.money = c.money + (b.money or 0)
							c.count = c.count + (b.kills or 0)
							addItems(c.items, b.items)
							c.sources[key] = (c.sources[key] or 0) + (b.kills or 0)
							if (b.skins or 0) > 0 or next(b.skinItems or {}) then
								local sk = category(s, "skinning")
								sk.count = sk.count + (b.skins or 0)
								addItems(sk.items, b.skinItems)
								sk.sources[key] = (sk.sources[key] or 0) + (b.skins or 0)
							end
						end
					end
				end
			end
		end
	end
	if db and type(db.characters) == "table" then
		for _, char in pairs(db.characters) do
			local name = char.name or "?"
			for _, ds in ipairs(char.sessions or {}) do
				if not keep or keep(ds, char) then addDataset(ds, name) end
			end
			if char.live and (not keep or keep(char.live, char)) then addDataset(char.live, name) end
		end
	end

	-- friends' spots: { m = mapID, z = subzone, zn = zone name, s = seconds, c = { cat = { mo, n, i = { id = n } } } }
	if includeShared then
		for sender, data in pairs((WhatToDoDB and WhatToDoDB.shared) or {}) do
			for _, sp in ipairs(data.spots or {}) do
				local s = spot(sp.m, sp.z)
				s.seconds = s.seconds + sp.s
				s.zoneName = s.zoneName or sp.zn
				local who = sender .. "*"
				s.chars[who] = (s.chars[who] or 0) + sp.s
				for cat, c in pairs(sp.c or {}) do
					local into = category(s, cat)
					into.money = into.money + (c.mo or 0)
					into.count = into.count + (c.n or 0)
					addItems(into.items, c.i)
				end
			end
		end
	end
	return spots, db
end

-- A spot's display name: Yield's or the game's zone name, the shared one, else the map ID.
function ns.SpotZoneName(db, s)
	if db then
		local names = db.names and db.names.zones
		if names and names[s.mapID] then return names[s.mapID] end
	end
	if s.zoneName then return s.zoneName end
	return zoneName(db or {}, s.mapID)
end

function ns.FarmActivities()
	local spots, db = ns.CollectSpots(true)
	if not next(spots) then return {} end
	db = db or { names = {} }

	local yield, cache = yieldAddon(), {}
	local minSeconds = ns.Setting("minFarmMinutes") * 60
	local out = {}

	-- Every category pooled over all spots, for small samples (under an hour on a spot):
	--   the typical rate (value per second) a spot's own rate is pulled towards, and
	--   each item's drops per gather/kill, so a lucky rare drop (a gem from a node) counts at its usual chance.
	local pool = {}
	for _, s in pairs(spots) do
		for cat, c in pairs(s.cats) do
			local p = pool[cat] or { seconds = 0, value = 0, count = 0, items = {} }
			pool[cat] = p
			p.seconds = p.seconds + s.seconds
			p.value = p.value + ns.CategoryValue(c, cache)
			p.count = p.count + (c.count or 0)
			for itemID, n in pairs(c.items) do p.items[itemID] = (p.items[itemID] or 0) + n end
		end
	end

	for _, s in pairs(spots) do
		if s.seconds >= minSeconds then
			local hours = s.seconds / 3600
			local zone = ns.SpotZoneName(db, s)
			local title = (s.subzone ~= "" and s.subzone ~= zone) and (zone .. ": " .. s.subzone) or zone
			local chars = {}
			for name in pairs(s.chars) do chars[#chars + 1] = name end
			table.sort(chars)

			-- value every category first: the spot's total is needed for each one's share
			local valued, spotTotal = {}, 0
			for cat, c in pairs(s.cats) do
				local itemValue, expectedItems, lines = 0, 0, {}
				local p = pool[cat]
				local short = s.seconds < 3600 and c.count > 0 and p and p.count > c.count
				for itemID, seen in pairs(c.items) do
					local count = seen
					if short and seen <= 2 then -- a rare drop on a short sample: its usual chance, never more than seen
						count = math.min(seen, (p.items[itemID] or 0) / p.count * c.count)
					end
					local base = valueOf(itemID, yield, cache) * count
					local factor = ns.SellFactor(itemID)
					local v = base * factor
					itemValue, expectedItems = itemValue + v, expectedItems + base
					lines[#lines + 1] = { itemID = itemID, count = seen, value = v, factor = factor }
				end
				table.sort(lines, function(a, b) return a.value > b.value end)
				-- trust: each AH-priced item's price freshness, weighted by its share of the value; coin and
				-- vendor-priced items count as fully trusted
				local total = c.money + itemValue
				local trusted, stalestHours, stalestItem = c.money, 0, nil
				local ahValue, ahHours, gearValue = 0, 0, 0 -- for model 1: AH-priced share, its age, gear share
				for _, l in ipairs(lines) do
					local hours = ns.AuctionPrice(l.itemID) and ns.PriceHours(l.itemID)
					local t = hours and ns.TrustOfHours(hours) or 1
					trusted = trusted + l.value * t
					if hours then
						ahValue = ahValue + l.value
						ahHours = ahHours + l.value * math.min(hours, 72)
					end
					if ns.ItemGroup and ns.ItemGroup(l.itemID) == "gear" then gearValue = gearValue + l.value end
					if hours and total > 0 and l.value / total >= 0.05 and hours > stalestHours then
						stalestHours, stalestItem = hours, l.itemID
					end
				end
				local priceTrust = total > 0 and trusted / total or 1
				-- evidence: the share of the value that was real gold (coin, items sold at least once),
				-- times how much time backs it (an hour -> half)
				local realized = c.money
				for _, l in ipairs(lines) do
					if ns.SalesCount(l.itemID) > 0 then realized = realized + l.value end
				end
				local realizedShare = total > 0 and realized / total or 0
				local evidence = realizedShare * (s.seconds / (s.seconds + 3600))
				local v = { cat = cat, c = c, value = total, expected = c.money + expectedItems, itemValue = itemValue, lines = lines,
					trust = ns.CombineTrust(priceTrust, evidence), priceTrust = priceTrust, evidence = evidence, realizedShare = realizedShare,
					stalestHours = stalestItem and stalestHours or nil, stalestItem = stalestItem }
				-- under an hour: the forecast leans on the typical rate of this kind of activity elsewhere
				-- (12 minutes of data: 20% own, 80% typical), reaching the spot's own rate at an hour
				local ownRate, rate = total * 3600 / s.seconds, total * 3600 / s.seconds
				local otherSeconds = p and (p.seconds - s.seconds) or 0
				if s.seconds < 3600 and otherSeconds >= 600 then
					local typical = (p.value - ns.CategoryValue(c, cache)) * 3600 / otherSeconds
					local w = s.seconds / 3600
					rate = w * ownRate + (1 - w) * math.max(typical, 0)
					v.ownRate, v.typicalRate, v.ownWeight = ownRate, typical, w
				end
				v.rate = rate
				if ns.FarmRange and total > 0 then
					v.range = ns.FarmRange(rate, s.seconds / 3600, ahValue > 0 and ahHours / ahValue or nil,
						ahValue / total, gearValue / total, cat ~= "farm")
				end
				valued[#valued + 1] = v
				spotTotal = spotTotal + v.value
			end

			for _, v in ipairs(valued) do
				local c, cat = v.c, v.cat
				local gather = cat ~= "farm"
				-- mob farming: not above the current character's level + 2
				local mobLevel, mobLo, mobHi
				if not gather then mobLevel, mobLo, mobHi = spotMobLevel(c) end
				local tooHigh = mobLevel and mobLevel > (UnitLevel("player") or 0) + MAX_LEVEL_ABOVE
				if v.value > 0 and (not gather or c.count >= MIN_GATHERS) and not tooHigh then
					local sources = {}
					for key, n in pairs(c.sources) do sources[#sources + 1] = { key = key, n = n } end
					table.sort(sources, function(a, b) return a.n > b.n end)

					local tip = {
						{ T("Відстежено на місці"), string.format(T("%.1f год"), hours) },
					}
					if c.money > 0 then tip[#tip + 1] = { T("Монети"), ns.Coin(c.money * 3600 / s.seconds) .. T("/год") } end
					tip[#tip + 1] = { T("Предмети"), ns.Coin(v.itemValue * 3600 / s.seconds) .. T("/год") }
					if c.count > 0 then
						tip[#tip + 1] = { gather and T(GATHER_LABEL[cat] or "Збирань") or T("Вбивств"), string.format(T("%d (%.0f/год)"), c.count, c.count / hours) }
						if gather then tip[#tip + 1] = { T("За одне ") .. (cat == "fishing" and T("закидання") or T("збирання")), ns.Coin(v.value / c.count) } end
					end
					tip[#tip + 1] = { " ", " " }
					tip[#tip + 1] = { T("Найцінніше:"), "" }
					for i = 1, math.min(6, #v.lines) do
						local l = v.lines[i]
						local fText = ns.FactorText(l.factor)
						tip[#tip + 1] = { string.format("  %s x%d", ns.ItemName(l.itemID), l.count), ns.Coin(l.value * 3600 / s.seconds) .. T("/год") .. (fText and (T(" (факт ") .. fText .. ")") or "") }
					end
					if not gather and #sources > 0 then
						tip[#tip + 1] = { " ", " " }
						tip[#tip + 1] = { T("Джерела:"), "" }
						for i = 1, math.min(4, #sources) do
							tip[#tip + 1] = { "  " .. sourceName(db, sources[i].key), tostring(sources[i].n) }
						end
					end
					tip[#tip + 1] = { " ", " " }
					if spotTotal > v.value then
						tip[#tip + 1] = { T("Частка доходу місця"), string.format("%.0f%%", v.value / spotTotal * 100) }
						tip[#tip + 1] = { T("Місце разом (усе)"), ns.Coin(spotTotal * 3600 / s.seconds) .. T("/год") }
						for _, other in ipairs(valued) do
							if other ~= v and other.value > 0 then
								tip[#tip + 1] = { "  + " .. T(CAT_NAME[other.cat] or other.cat), ns.Coin(other.value * 3600 / s.seconds) .. T("/год") }
							end
						end
					end
					if mobLevel then
						tip[#tip + 1] = { T("Рівень мобів"), mobLo == mobHi and tostring(mobLo) or (mobLo .. "-" .. mobHi) }
					end
					tip[#tip + 1] = { T("Персонажі"), table.concat(chars, ", ") }
					if v.range then
						tip[#tip + 1] = { " ", " " }
						tip[#tip + 1] = { T("Наступна сесія (8 з 10 випадків)"), ns.Coin(v.range.p10) .. " - " .. ns.Coin(v.range.p90) .. T("/год") }
						tip[#tip + 1] = { T("Не менше половини прогнозу"), string.format("%d%%", math.floor(v.range.success * 100 + 0.5)) }
						if v.ownWeight then
							tip[#tip + 1] = { T("Мала вибірка"), string.format(T("%d%% ваші дані тут, %d%% типове"), math.floor(v.ownWeight * 100 + 0.5), math.floor((1 - v.ownWeight) * 100 + 0.5)) }
							tip[#tip + 1] = { T("  тут за вашими даними"), ns.Coin(v.ownRate) .. T("/год") }
							tip[#tip + 1] = { string.format(T("  типово (%s в інших місцях)"), T(CAT_NAME[cat] or cat)), ns.Coin(v.typicalRate) .. T("/год") }
						end
						for i, d in ipairs(v.range.drivers) do tip[#tip + 1] = { i == 1 and T("Невизначеність") or " ", d } end
					end
					if v.stalestItem then tip[#tip + 1] = { T("Найстаріша ціна"), string.format(T("%s, %s тому"), ns.ItemName(v.stalestItem), ns.AgeText(v.stalestHours)) } end
					if math.abs(v.value - v.expected) >= 1 then
						tip[#tip + 1] = { T("Без поправок було б"), ns.Coin(v.expected * 3600 / s.seconds) .. T("/год") }
					end

					local detail = string.format(T("%.1f год даних"), hours)
					if c.count > 0 then
						detail = detail .. string.format(T(", %.0f %s/год"), c.count / hours, gather and T(RATE_UNIT[cat] or "збирань") or T("вбивств"))
					end
					if gather then
						if v.lines[1] then detail = detail .. ", " .. ns.ItemName(v.lines[1].itemID) end
					elseif sources[1] then
						detail = detail .. ", " .. sourceName(db, sources[1].key)
					end
					if spotTotal > v.value * 1.05 then
						detail = detail .. string.format(T(", разом на місці %s/год"), ns.Coin(spotTotal * 3600 / s.seconds))
					end

					out[#out + 1] = {
						kind = cat,
						title = title,
						mapID = s.mapID,
						subzone = s.subzone,
						zone = zone,
						perHour = v.range and v.range.p50 or v.rate,
						expectedPerHour = v.expected * 3600 / s.seconds,
						corrected = not v.range and math.abs(v.value - v.expected) >= 1,
						range = v.range and { v.range.p10, v.range.p50, v.range.p90 } or nil,
						detail = detail,
						tooltip = tip,
						confidence = math.min(1, s.seconds / 3600), -- an hour of data counts as solid
						trust = v.range and v.range.success or v.trust,
						priceTrust = v.priceTrust,
					}
				end
			end
		end
	end
	return out
end
