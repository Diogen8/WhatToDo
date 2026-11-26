-- Farm spots from Yield's history, split by category (mobs, mining, herbalism, fishing, skinning). Yield stores per dataset (each saved session and the live one):
--   ds.time[mapID][subzone] = tracked seconds
--   ds.sources[key] = { kind = "mob"|"mining"|"herbalism"|"chest"|"container"|"fishing"|...,
--                       locations[mapID][subzone].solo|group = { kills, money, skins, items = {id = n}, skinItems = {id = n} } }
-- Every character's sessions are summed per spot (zone + subzone) and the loot is valued at today's prices,
-- through Yield's own ItemPrice when Yield is loaded (same AH cut, stale and exclusion rules as its window).
local _, ns = ...

local SKIP_KINDS = { purchase = true, quest = true, mail = true, trade = true, vendor = true }
local GATHER = { mining = true, herbalism = true, fishing = true }
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
			local hours = s.seconds / 3600
			local zone = zoneName(db, s.mapID)
			local title = (s.subzone ~= "" and s.subzone ~= zone) and (zone .. ": " .. s.subzone) or zone
			local chars = {}
			for name in pairs(s.chars) do chars[#chars + 1] = name end
			table.sort(chars)

			-- value every category first: the spot's total is needed for each one's share
			local valued, spotTotal = {}, 0
			for cat, c in pairs(s.cats) do
				local itemValue, expectedItems, lines = 0, 0, {}
				for itemID, count in pairs(c.items) do
					local base = valueOf(itemID, yield, cache) * count
					local factor = ns.SellFactor(itemID)
					local v = base * factor
					itemValue, expectedItems = itemValue + v, expectedItems + base
					lines[#lines + 1] = { itemID = itemID, count = count, value = v, factor = factor }
				end
				table.sort(lines, function(a, b) return a.value > b.value end)
				local v = { cat = cat, c = c, value = c.money + itemValue, expected = c.money + expectedItems, itemValue = itemValue, lines = lines }
				valued[#valued + 1] = v
				spotTotal = spotTotal + v.value
			end

			for _, v in ipairs(valued) do
				local c, cat = v.c, v.cat
				local gather = cat ~= "farm"
				if v.value > 0 and (not gather or c.count >= MIN_GATHERS) then
					local sources = {}
					for key, n in pairs(c.sources) do sources[#sources + 1] = { key = key, n = n } end
					table.sort(sources, function(a, b) return a.n > b.n end)

					local tip = {
						{ "Відстежено на місці", string.format("%.1f год", hours) },
					}
					if c.money > 0 then tip[#tip + 1] = { "Монети", ns.Coin(c.money * 3600 / s.seconds) .. "/год" } end
					tip[#tip + 1] = { "Предмети", ns.Coin(v.itemValue * 3600 / s.seconds) .. "/год" }
					if c.count > 0 then
						tip[#tip + 1] = { gather and (GATHER_LABEL[cat] or "Збирань") or "Вбивств", string.format("%d (%.0f/год)", c.count, c.count / hours) }
						if gather then tip[#tip + 1] = { "За одне " .. (cat == "fishing" and "закидання" or "збирання"), ns.Coin(v.value / c.count) } end
					end
					tip[#tip + 1] = { " ", " " }
					tip[#tip + 1] = { "Найцінніше:", "" }
					for i = 1, math.min(6, #v.lines) do
						local l = v.lines[i]
						local fText = ns.FactorText(l.factor)
						tip[#tip + 1] = { string.format("  %s x%d", ns.ItemName(l.itemID), l.count), ns.Coin(l.value * 3600 / s.seconds) .. "/год" .. (fText and (" (факт " .. fText .. ")") or "") }
					end
					if not gather and #sources > 0 then
						tip[#tip + 1] = { " ", " " }
						tip[#tip + 1] = { "Джерела:", "" }
						for i = 1, math.min(4, #sources) do
							tip[#tip + 1] = { "  " .. sourceName(db, sources[i].key), tostring(sources[i].n) }
						end
					end
					tip[#tip + 1] = { " ", " " }
					if spotTotal > v.value then
						tip[#tip + 1] = { "Частка доходу місця", string.format("%.0f%%", v.value / spotTotal * 100) }
						tip[#tip + 1] = { "Місце разом (усе)", ns.Coin(spotTotal * 3600 / s.seconds) .. "/год" }
						for _, other in ipairs(valued) do
							if other ~= v and other.value > 0 then
								tip[#tip + 1] = { "  + " .. (CAT_NAME[other.cat] or other.cat), ns.Coin(other.value * 3600 / s.seconds) .. "/год" }
							end
						end
					end
					tip[#tip + 1] = { "Персонажі", table.concat(chars, ", ") }
					if math.abs(v.value - v.expected) >= 1 then
						tip[#tip + 1] = { "Без поправок було б", ns.Coin(v.expected * 3600 / s.seconds) .. "/год" }
					end

					local detail = string.format("%.1f год даних", hours)
					if c.count > 0 then
						detail = detail .. string.format(", %.0f %s/год", c.count / hours, gather and (RATE_UNIT[cat] or "збирань") or "вбивств")
					end
					if gather then
						if v.lines[1] then detail = detail .. ", " .. ns.ItemName(v.lines[1].itemID) end
					elseif sources[1] then
						detail = detail .. ", " .. sourceName(db, sources[1].key)
					end
					if spotTotal > v.value * 1.05 then
						detail = detail .. string.format(", разом на місці %s/год", ns.Coin(spotTotal * 3600 / s.seconds))
					end

					out[#out + 1] = {
						kind = cat,
						title = title,
						perHour = v.value * 3600 / s.seconds,
						expectedPerHour = v.expected * 3600 / s.seconds,
						corrected = math.abs(v.value - v.expected) >= 1,
						detail = detail,
						tooltip = tip,
						confidence = math.min(1, s.seconds / 3600), -- an hour of data counts as solid
					}
				end
			end
		end
	end
	return out
end
