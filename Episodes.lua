-- Episodes: closed outcomes the trust model learns from (stage 1 of the prediction model). Kept in
-- WhatToDoDB.episodes, shared by all characters on the account.
--
-- Recraft BATCH (one open per product): opens at the first craft of a product, then collects
--   cost:    reagents taken from purchase lots first-in-first-out at what you paid; reagents you didn't buy
--            (farmed, already owned) at what they'd sell for now (what you gave up by crafting them);
--   active:  your time with the auction house, mail and profession windows open, split between the batches (and
--            purchased reagents) handled in each visit. Travel isn't counted;
--   posts (Auctionator's posting history), sales, returns, and the hours from first post to each sale.
-- It closes when every crafted unit has sold, or 2 days after the first post (after the last craft if never posted):
-- what's unsold then counts at the vendor price. Success = profit > 0.
--
-- FARM: each stored Yield session is checked against the sessions before it at the same spot and category
-- (mobs, mining, ...): forecast = their gold per hour, actual = this session's, both at today's prices.
-- Success = actual >= half the forecast. Sessions recorded before this existed are checked too, in order.
local _, ns = ...
local T = function(s) return ns.T(s) end

local CLOSE_AFTER = 2 * 86400
local KEEP_CLOSED, KEEP_FARM = 300, 500
local KEEP_LOTS = 40
local REAGENT_TIME_TTL = 2 * 3600   -- purchase-visit time waits this long for a batch to use the reagents
local VISIT_CLAIM = 3600            -- an AH visit with no posts is credited to purchases mailed within this time
local MIN_FARM_SECONDS = 600
local FARM_SUCCESS = 0.5

local function db()
	if not WhatToDoDB then return nil end
	local e = WhatToDoDB.episodes
	if not e then
		e = { lots = {}, open = {}, closed = {}, farm = {}, farmSeen = {}, reagentTime = {}, nextId = 1 }
		WhatToDoDB.episodes = e
	end
	return e
end
ns.EpisodeData = db

---------------------------------------------------------------------------
-- Active time: windows open, and what was handled while they were
---------------------------------------------------------------------------

local windows = {}       -- kind -> { since = GetTime(), touched = { key = true } }
local pendingVisit       -- { seconds, t } an AH visit that touched nothing yet (purchases arrive by mail)

local function touch(key)
	for _, w in pairs(windows) do w.touched[key] = true end
end

local function addReagentTime(e, itemID, seconds)
	local r = e.reagentTime[itemID]
	if r and time() - r.t > REAGENT_TIME_TTL then r = nil end
	e.reagentTime[itemID] = { s = (r and r.s or 0) + seconds, t = time() }
end

local function closeWindow(kind)
	local w = windows[kind]
	windows[kind] = nil
	local e = db()
	if not (w and e) then return end
	local seconds = math.max(0, GetTime() - w.since)
	local keys = {}
	for key in pairs(w.touched) do keys[#keys + 1] = key end
	if #keys == 0 then
		if kind == "ah" and seconds > 5 then pendingVisit = { seconds = seconds, t = time() } end
		return
	end
	local share = seconds / #keys
	for _, key in ipairs(keys) do
		local kindOf, id = key:match("^(%a):(%d+)$")
		id = tonumber(id)
		if kindOf == "b" then
			for _, b in pairs(e.open) do
				if b.id == id then b.active = b.active + share end
			end
		elseif kindOf == "r" then
			addReagentTime(e, id, share)
		end
	end
end

---------------------------------------------------------------------------
-- Purchases: lots that crafts take reagents from
---------------------------------------------------------------------------

function ns.EpisodeBuy(itemID, units, paid)
	local e = db()
	if not (e and itemID and units and units > 0 and paid and paid > 0) then return end
	local lots = e.lots[itemID] or {}
	e.lots[itemID] = lots
	lots[#lots + 1] = { n = units, cost = paid / units, t = time() }
	while #lots > KEEP_LOTS do table.remove(lots, 1) end
	touch("r:" .. itemID)
	if pendingVisit and time() - pendingVisit.t <= VISIT_CLAIM then
		addReagentTime(e, itemID, pendingVisit.seconds)
		pendingVisit = nil
	end
end

-- Takes `need` units first-in-first-out from purchase lots. Returns the cost of what was taken and the units
-- still missing.
local function takeLots(e, itemID, need)
	local lots, cost = e.lots[itemID], 0
	while lots and need > 0 and lots[1] do
		local lot = lots[1]
		local take = math.min(need, lot.n)
		cost, need, lot.n = cost + take * lot.cost, need - take, lot.n - take
		if lot.n <= 0 then table.remove(lots, 1) end
	end
	if lots and not lots[1] then e.lots[itemID] = nil end
	return cost, need
end

-- What an owned reagent would sell for now: AH after the cut, else the vendor.
local function ownedValue(itemID)
	local net = ns.SellNet and ns.SellNet(itemID)
	if net then return net end
	local info = { (C_Item and C_Item.GetItemInfo or GetItemInfo)(itemID) }
	return info[11] or 0
end

local function vendorValue(itemID)
	local info = { (C_Item and C_Item.GetItemInfo or GetItemInfo)(itemID) }
	return info[11] or 0
end

---------------------------------------------------------------------------
-- Batches
---------------------------------------------------------------------------

local function recipeFor(product)
	for _, entry in ipairs(ns.AllRecipes()) do
		if entry.section == "craft" and entry.recipe.product == product then return entry.recipe end
	end
	for _, entry in ipairs(ns.AllRecipes()) do
		if entry.recipe.product == product then return entry.recipe end
	end
end

-- The suggestion as it stood when the batch opened: what the model will later be checked against.
local function forecastFor(product)
	for _, a in ipairs(ns.Rank("craft")) do
		if a.product == product then
			return { perHour = a.perHour, profit = a.profit, crafts = a.crafts, trust = a.trust, p1 = a.p1,
				priceTrust = a.priceTrust, priceHours = a.trustHours ~= math.huge and a.trustHours or nil }
		end
	end
end

local function openBatch(e, product, recipe)
	local b = {
		id = e.nextId, product = product, char = ns.CharKey(), opened = time(), last = time(),
		crafts = 0, crafted = 0, cost = 0, ownMats = 0, sold = 0, revenue = 0, returned = 0, posted = 0,
		saleHours = 0, active = 0, forecast = forecastFor(product),
	}
	-- crafted though WhatToDo didn't suggest it (not listed, or less than nothing most likely): levelling
	-- the profession, most likely. Its outcome is kept but doesn't teach the models about recraft.
	b.levelling = not (b.forecast and (b.forecast.perHour or 0) > 0) or nil
	e.nextId = e.nextId + 1
	-- time spent buying its reagents shortly before
	for _, rg in ipairs(recipe.reagents) do
		local r = e.reagentTime[rg[1]]
		if r then
			if time() - r.t <= REAGENT_TIME_TTL then b.active = b.active + r.s end
			e.reagentTime[rg[1]] = nil
		end
	end
	e.open[product] = b
	return b
end

local function closeBatch(e, b, now)
	local unsold = math.max(0, b.crafted - b.sold)
	local revenue = b.revenue + unsold * vendorValue(b.product)
	local profit = revenue - b.cost
	local outcome = {
		id = b.id, product = b.product, char = b.char, opened = b.opened, closed = now,
		crafts = b.crafts, crafted = b.crafted, sold = b.sold, returned = b.returned, posted = b.posted, unsold = unsold,
		cost = b.cost, ownMats = b.ownMats, revenue = revenue, profit = profit, active = b.active,
		waitHours = b.sold > 0 and b.saleHours / b.sold or nil,
		perActiveHour = b.active >= 60 and profit * 3600 / b.active or nil,
		forecast = b.forecast,
		levelling = b.levelling, untrusted = b.untrusted,
		success = profit > 0,
	}
	e.closed[#e.closed + 1] = outcome
	while #e.closed > KEEP_CLOSED do table.remove(e.closed, 1) end
	e.open[b.product] = nil
end

local function checkClose(e, b, now)
	if b.crafted > 0 and b.sold >= b.crafted then return closeBatch(e, b, now) end
	if now - (b.firstPost or b.last) >= CLOSE_AFTER then return closeBatch(e, b, now) end
end

function ns.EpisodeCraft(product, units)
	local e = db()
	if not e then return end
	local recipe = recipeFor(product)
	if not recipe then return end
	local b = e.open[product] or openBatch(e, product, recipe)
	b.crafts, b.crafted, b.last = b.crafts + 1, b.crafted + (units or 1), time()
	for _, rg in ipairs(recipe.reagents) do
		local id, count = rg[1], rg[2]
		local cost, missing = takeLots(e, id, count)
		b.cost = b.cost + cost + missing * ownedValue(id)
		b.ownMats = b.ownMats + missing
	end
	touch("b:" .. b.id)
end

function ns.EpisodeSale(itemID, units, net)
	local e = db()
	local b = e and e.open[itemID]
	if not b then return end
	local now = time()
	local take = math.min(units or 1, b.crafted - b.sold)
	if take <= 0 then return end
	b.sold = b.sold + take
	b.revenue = b.revenue + net * take / (units or 1)
	b.saleHours = b.saleHours + (now - (b.firstPost or b.opened)) / 3600 * take
	touch("b:" .. b.id)
	checkClose(e, b, now)
end

function ns.EpisodeReturn(itemID, units)
	local e = db()
	local b = e and e.open[itemID]
	if not b then return end
	b.returned = b.returned + (units or 1)
	touch("b:" .. b.id)
end

-- Posts (Ledger.lua's own posting record): units of an open batch put on the AH, and when first.
function ns.EpisodePost(itemID, quantity)
	local e = db()
	local b = e and e.open[itemID]
	if not b then return end
	b.posted = b.posted + (quantity or 1)
	if not b.firstPost then b.firstPost = time() end
	touch("b:" .. b.id)
end

---------------------------------------------------------------------------
-- Farm sessions: each one against the earlier sessions at the same spot
---------------------------------------------------------------------------

local function backtestSession(e, char, ds, cache)
	local start = ds.startTime or 0
	local session = ns.CollectSpots(false, function(d) return d == ds end)
	local before = ns.CollectSpots(false, function(d, c) return d ~= ds and d ~= c.live and (d.startTime or 0) < start end)
	for key, s in pairs(session) do
		local h = before[key]
		if s.seconds >= MIN_FARM_SECONDS and h and h.seconds >= MIN_FARM_SECONDS then
			for cat, c in pairs(s.cats) do
				local hc = h.cats[cat]
				if hc then
					local forecast = ns.CategoryValue(hc, cache) * 3600 / h.seconds
					local actual = ns.CategoryValue(c, cache) * 3600 / s.seconds
					if forecast > 0 then
						e.farm[#e.farm + 1] = {
							t = ds.endTime or ds.lastActive or start, char = char.name, m = s.mapID, z = s.subzone,
							cat = cat, seconds = s.seconds, historySeconds = h.seconds,
							forecast = forecast, actual = actual, success = actual >= FARM_SUCCESS * forecast,
						}
					end
				end
			end
		end
	end
	while #e.farm > KEEP_FARM do table.remove(e.farm, 1) end
end

local function backtestFarm()
	local e, ydb = db(), ns.YieldData and ns.YieldData()
	if not (e and ydb and type(ydb.characters) == "table") then return end
	local cache = {}
	for guid, char in pairs(ydb.characters) do
		local seen = e.farmSeen[guid] or 0
		local fresh = {}
		for _, ds in ipairs(char.sessions or {}) do
			if (ds.id or 0) > seen then fresh[#fresh + 1] = ds end
		end
		table.sort(fresh, function(a, b) return (a.id or 0) < (b.id or 0) end)
		for _, ds in ipairs(fresh) do
			backtestSession(e, char, ds, cache)
			e.farmSeen[guid] = math.max(e.farmSeen[guid] or 0, ds.id or 0)
		end
	end
end

---------------------------------------------------------------------------
-- Events and the periodic check
---------------------------------------------------------------------------

local WINDOW_EVENTS = {
	AUCTION_HOUSE_SHOW = { "ah", true }, AUCTION_HOUSE_CLOSED = { "ah", false },
	MAIL_SHOW = { "mail", true }, MAIL_CLOSED = { "mail", false },
	TRADE_SKILL_SHOW = { "craft", true }, TRADE_SKILL_CLOSE = { "craft", false },
}

local f = CreateFrame("Frame")
for event in pairs(WINDOW_EVENTS) do pcall(f.RegisterEvent, f, event) end
pcall(f.RegisterEvent, f, "PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event)
	local e = db()
	if not e then return end
	if event == "PLAYER_LOGIN" then
		C_Timer.After(15, backtestFarm)
		return
	end
	local w = WINDOW_EVENTS[event]
	if not w then return end
	if w[2] then
		if not windows[w[1]] then windows[w[1]] = { since = GetTime(), touched = {} } end
	else
		closeWindow(w[1])
	end
end)

local function tick()
	local e = db()
	if e then
		local now = time()
		for _, b in pairs(e.open) do checkClose(e, b, now) end
		backtestFarm()
	end
	C_Timer.After(300, tick)
end
C_Timer.After(60, tick)

---------------------------------------------------------------------------
-- Reading the results
---------------------------------------------------------------------------

-- Closed batches of a product: count and how many ended in profit.
function ns.BatchStats(product)
	local e = db()
	local n, ok = 0, 0
	for _, o in ipairs((e and e.closed) or {}) do
		if o.product == product then
			n = n + 1
			if o.success then ok = ok + 1 end
		end
	end
	return n, ok, e and e.open[product]
end

local CAT_LABEL = { farm = "моби", mining = "майнінг", herbalism = "трави", fishing = "риболовля", skinning = "скінінг" }

function ns.ResultsReport()
	local e = db()
	if not e then return end
	local ok = 0
	for _, o in ipairs(e.closed) do if o.success then ok = ok + 1 end end
	local open = 0
	for _ in pairs(e.open) do open = open + 1 end
	ns.Out(string.format(T("рекрафт: закрито партій %d, у плюс %d; відкрито %d"), #e.closed, ok, open))
	for i = #e.closed, math.max(1, #e.closed - 7), -1 do
		local o = e.closed[i]
		print(string.format(T("  %s: %d крафтів, продано %d з %d, прибуток %s, %s - %s"),
			ns.ItemName(o.product), o.crafts, o.sold, o.crafted, ns.Coin(o.profit),
			o.perActiveHour and (ns.Coin(o.perActiveHour) .. T("/год активного часу")) or T("мало активного часу"),
			(o.success and T("|cff66ff66у плюс|r") or T("|cffff6666у мінус|r")) .. (o.levelling and T(" (прокачка)") or "")))
	end
	for product, b in pairs(e.open) do
		print(string.format(T("  відкрита: %s, скрафчено %d, продано %d, витрачено %s"), ns.ItemName(product), b.crafted, b.sold, ns.Coin(b.cost)) .. (b.levelling and T(" (прокачка)") or ""))
	end
	local fok = 0
	for _, r in ipairs(e.farm) do if r.success then fok = fok + 1 end end
	ns.Out(string.format(T("фарм: перевірено сесій %d, справдилось (не менше половини прогнозу) %d"), #e.farm, fok))
	for i = #e.farm, math.max(1, #e.farm - 7), -1 do
		local r = e.farm[i]
		local zone = (r.z ~= "" and r.z) or ("#" .. r.m)
		print(string.format(T("  %s (%s): факт %s/год, прогноз %s/год - %s"), zone, T(CAT_LABEL[r.cat] or r.cat),
			ns.Coin(r.actual), ns.Coin(r.forecast), r.success and T("|cff66ff66справдилось|r") or T("|cffff6666ні|r")))
	end
	if ns.CalibrationReport then ns.CalibrationReport() end
end
