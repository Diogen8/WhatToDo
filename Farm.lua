-- Farm spots from Yield's history. Yield stores per dataset (each saved session and the live one):
--   ds.time[mapID][subzone] = tracked seconds
--   ds.sources[key] = { kind = "mob"|"mining"|"herbalism"|"chest"|"container"|"fishing"|...,
--                       locations[mapID][subzone].solo|group = { kills, money, skins, items = {id = n}, skinItems = {id = n} } }
-- Every character's sessions are summed per spot (zone + subzone) and the loot is valued at today's prices,
-- through Yield's own ItemPrice when Yield is loaded (same AH cut, stale and exclusion rules as its window).
local _, ns = ...

local SKIP_KINDS = { purchase = true, quest = true, mail = true, trade = true, vendor = true }

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

function ns.FarmActivities()
	local db = yieldDB()
	if not db or type(db.characters) ~= "table" then return {} end

	local spots = {}
	local function spot(mapID, subzone)
		local key = mapID .. "\t" .. subzone
		local s = spots[key]
		if not s then
			s = { mapID = mapID, subzone = subzone, seconds = 0, money = 0, items = {}, kills = 0, gathers = 0, chars = {}, sources = {} }
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
				for mapID, zone in pairs(source.locations or {}) do
					for subzone, modes in pairs(zone) do
						local s = spot(mapID, subzone)
						for _, b in pairs(modes) do
							s.money = s.money + (b.money or 0)
							if source.kind == "mob" then s.kills = s.kills + (b.kills or 0)
							else s.gathers = s.gathers + (b.kills or 0) end
							s.gathers = s.gathers + (b.skins or 0)
							addItems(s.items, b.items)
							addItems(s.items, b.skinItems)
							s.sources[key] = (s.sources[key] or 0) + (b.kills or 0)
						end
					end
				end
			end
		end
	end
	for _, char in pairs(db.characters) do
		local name = char.name or "?"
		for _, ds in ipairs(char.sessions or {}) do addDataset(ds, name) end
		if char.live then addDataset(char.live, name) end
	end

	local yield, cache = yieldAddon(), {}
	local minSeconds = ns.Setting("minFarmMinutes") * 60
	local out = {}
	for _, s in pairs(spots) do
		if s.seconds >= minSeconds then
			local itemValue, lines = 0, {}
			for itemID, count in pairs(s.items) do
				local v = valueOf(itemID, yield, cache) * count
				itemValue = itemValue + v
				lines[#lines + 1] = { itemID = itemID, count = count, value = v }
			end
			local value = s.money + itemValue
			if value > 0 then
				table.sort(lines, function(a, b) return a.value > b.value end)
				local mobs = {}
				for key, n in pairs(s.sources) do mobs[#mobs + 1] = { key = key, n = n } end
				table.sort(mobs, function(a, b) return a.n > b.n end)
				local chars = {}
				for name in pairs(s.chars) do chars[#chars + 1] = name end
				table.sort(chars)

				local zone = zoneName(db, s.mapID)
				local title = (s.subzone ~= "" and s.subzone ~= zone) and (zone .. ": " .. s.subzone) or zone
				local hours = s.seconds / 3600
				local tip = {
					{ "Відстежено", string.format("%.1f год", hours) },
					{ "Монети", ns.Coin(s.money * 3600 / s.seconds) .. "/год" },
					{ "Предмети", ns.Coin(itemValue * 3600 / s.seconds) .. "/год" },
				}
				if s.kills > 0 then tip[#tip + 1] = { "Вбивств", string.format("%d (%.0f/год)", s.kills, s.kills / hours) } end
				if s.gathers > 0 then tip[#tip + 1] = { "Збирання", string.format("%d (%.0f/год)", s.gathers, s.gathers / hours) } end
				tip[#tip + 1] = { " ", " " }
				tip[#tip + 1] = { "Найцінніше:", "" }
				for i = 1, math.min(6, #lines) do
					local l = lines[i]
					tip[#tip + 1] = { string.format("  %s x%d", ns.ItemName(l.itemID), l.count), ns.Coin(l.value * 3600 / s.seconds) .. "/год" }
				end
				if #mobs > 0 then
					tip[#tip + 1] = { " ", " " }
					tip[#tip + 1] = { "Джерела:", "" }
					for i = 1, math.min(4, #mobs) do
						tip[#tip + 1] = { "  " .. sourceName(db, mobs[i].key), tostring(mobs[i].n) }
					end
				end
				tip[#tip + 1] = { " ", " " }
				tip[#tip + 1] = { "Персонажі", table.concat(chars, ", ") }

				local detail = string.format("%.1f год даних", hours)
				if s.kills > 0 then detail = detail .. string.format(" · %.0f вбивств/год", s.kills / hours) end
				if s.gathers > 0 then detail = detail .. string.format(" · %.0f збирань/год", s.gathers / hours) end
				if #mobs > 0 then detail = detail .. " · " .. sourceName(db, mobs[1].key) end

				out[#out + 1] = {
					kind = "farm",
					title = title,
					perHour = value * 3600 / s.seconds,
					detail = detail,
					tooltip = tip,
					confidence = math.min(1, s.seconds / 3600), -- an hour of data counts as solid
				}
			end
		end
	end
	return out
end
