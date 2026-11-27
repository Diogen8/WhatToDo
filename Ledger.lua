-- Ledger: what actually happened, kept in WhatToDoDB.ledger (account-wide) to correct the estimates.
--   sales[itemName] = { units, events, net, expired, expiredEvents, expNet, expFor, last }
--       net: copper received for sold units (after the AH cut, without the returned deposit)
--       expNet / expFor: what Auctionator's price said those units would net, and the part of `net` it covers
--       expired: units that came back unsold
--   buys[itemName]  = { units, events, paid, expected, paidFor, last }  -- AH purchases vs Auctionator's price
--   crafts[itemID]  = { crafts, units, seconds, gaps }                   -- "You create" timings
--   log = { {t, kind, name, units, copper, expected}, ... } (newest last, capped)
-- Mail is read when it's taken (TakeInboxMoney / TakeInboxItem / AutoLootMailItem, so "Open All" and Postal
-- count too); a fingerprint keeps one mail from being booked twice.
local _, ns = ...
local T = function(s) return ns.T(s) end

local LOG_MAX = 400
local BLEND = 5          -- events before a correction counts fully (factor = 1 + (raw - 1) * n / (n + BLEND))
local CRAFT_GAP_MAX = 30 -- seconds; a longer pause between two creates isn't crafting time

local function ledger()
	if not WhatToDoDB then return nil end
	local l = WhatToDoDB.ledger
	if not l then
		l = { sales = {}, buys = {}, crafts = {}, log = {} }
		WhatToDoDB.ledger = l
	end
	return l
end
ns.Ledger = ledger

local function log(kind, name, units, copper, expected)
	local l = ledger()
	l.log[#l.log + 1] = { t = time(), kind = kind, name = name, units = units, copper = copper, expected = expected }
	while #l.log > LOG_MAX do table.remove(l.log, 1) end
end

-- "Auction successful: %s" -> "^Auction successful: (.+)$"
local function subjectPattern(fmt, fallback)
	fmt = type(fmt) == "string" and fmt or fallback
	local p = fmt:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
	p = p:gsub("%%s", "(.+)")
	return "^" .. p .. "$"
end
local SOLD = subjectPattern(AUCTION_SOLD_MAIL_SUBJECT, "Auction successful: %s")
local EXPIRED = subjectPattern(AUCTION_EXPIRED_MAIL_SUBJECT, "Auction expired: %s")

local function idByName(name)
	if not name then return nil end
	if ns.nameToID and ns.nameToID[name] then return ns.nameToID[name] end
	local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
	if f then
		local ok, id = pcall(f, name)
		if ok and type(id) == "number" then return id end
	end
end

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------

-- Units in a sale when the invoice doesn't say: from Auctionator's posting history (unit price and quantity
-- of what you posted). A post whose stack value equals the sale wins; else the latest post's unit price.
-- nil when there's no history - then the sale counts toward income but not the price comparison.
local function unitsFromPostings(itemID, gross)
	local history = itemID and WhatToDoDB and WhatToDoDB.posts and WhatToDoDB.posts[itemID]
	if type(history) ~= "table" or #history == 0 then
		history = type(AUCTIONATOR_POSTING_HISTORY) == "table" and itemID and AUCTIONATOR_POSTING_HISTORY[tostring(itemID)]
	end
	if type(history) ~= "table" or not gross or gross <= 0 then return nil end
	local latest
	for i = #history, 1, -1 do
		local p = history[i]
		if type(p) == "table" and type(p.price) == "number" and p.price > 0 then
			local qty = p.quantity or 1
			if math.abs(p.price * qty - gross) <= math.max(1, gross * 0.001) then return qty end
			latest = latest or p
		end
	end
	if latest then return math.max(1, math.floor(gross / latest.price + 0.5)) end
end

local function recordSale(name, net, gross, count)
	local l = ledger()
	if not (l and name and net and net > 0) then return end
	local id = idByName(name)
	local price = id and ns.AuctionPrice(id)
	local units = (count and count > 0) and count or unitsFromPostings(id, gross)
	local unitsKnown = units ~= nil
	units = units or 1
	local s = l.sales[name] or { units = 0, events = 0, net = 0, expired = 0, expiredEvents = 0, expNet = 0, expFor = 0 }
	l.sales[name] = s
	s.units, s.events, s.net, s.last = s.units + units, s.events + 1, s.net + net, time()
	local expected
	if price and unitsKnown then
		expected = price * units * (1 - ns.Setting("ahCut"))
		s.expNet, s.expFor = s.expNet + expected, s.expFor + net
	end
	log("sold", name, unitsKnown and units or nil, net, expected)
	if ns.EpisodeSale and id then ns.EpisodeSale(id, units, net) end
end

local function recordExpired(name, units, itemID)
	local l = ledger()
	if not (l and name) then return end
	local s = l.sales[name] or { units = 0, events = 0, net = 0, expired = 0, expiredEvents = 0, expNet = 0, expFor = 0 }
	l.sales[name] = s
	s.expired, s.expiredEvents, s.last = s.expired + (units or 1), s.expiredEvents + 1, time()
	log("expired", name, units or 1, 0, nil)
	itemID = itemID or idByName(name)
	if ns.EpisodeReturn and itemID then ns.EpisodeReturn(itemID, units or 1) end
end

local function recordBuy(name, itemID, units, paid)
	local l = ledger()
	if not (l and name and paid and paid > 0) then return end
	units = (units and units > 0) and units or 1
	itemID = itemID or idByName(name)
	local b = l.buys[name] or { units = 0, events = 0, paid = 0, expected = 0, paidFor = 0 }
	l.buys[name] = b
	b.units, b.events, b.paid, b.last = b.units + units, b.events + 1, b.paid + paid, time()
	local price = itemID and ns.AuctionPrice(itemID)
	local expected
	if price then
		expected = price * units
		b.expected, b.paidFor = b.expected + expected, b.paidFor + paid
	end
	log("bought", name, units, paid, expected)
	if ns.EpisodeBuy and itemID then ns.EpisodeBuy(itemID, units, paid) end
end

-- One purchase can arrive as several mails (a stack of 20, then single units), and every one of their
-- invoices carries the whole purchase's price. Mails with the same item and price within a minute are one
-- purchase: their units add up and the price counts once, booked a few seconds after the last of them.
local GROUP_WINDOW, GROUP_SETTLE = 60, 3
local pendingBuys = {} -- "name|paid" -> { name, itemID, units, paid, first, seen }

local function flushBuys(force)
	local now = GetTime()
	for key, g in pairs(pendingBuys) do
		if force or now - g.seen >= GROUP_SETTLE then
			pendingBuys[key] = nil
			recordBuy(g.name, g.itemID, g.units, g.paid)
		end
	end
end

local function groupBuy(name, itemID, units, paid)
	if not (name and paid and paid > 0) then return end
	units = (units and units > 0) and units or 1
	local key = name .. "|" .. paid
	local g = pendingBuys[key]
	local now = GetTime()
	if g and now - g.first <= GROUP_WINDOW then
		g.units, g.seen = g.units + units, now
	else
		if g then recordBuy(g.name, g.itemID, g.units, g.paid) end
		pendingBuys[key] = { name = name, itemID = itemID, units = units, paid = paid, first = now, seen = now }
	end
	C_Timer.After(GROUP_SETTLE + 0.1, function() flushBuys(false) end)
end

local mailClose = CreateFrame("Frame")
pcall(mailClose.RegisterEvent, mailClose, "MAIL_CLOSED")
pcall(mailClose.RegisterEvent, mailClose, "PLAYER_LOGOUT")
mailClose:SetScript("OnEvent", function() flushBuys(true) end)

local recent = {} -- fingerprint -> GetTime() when booked

local function processMail(index, what)
	if not (ledger() and GetInboxHeaderInfo) then return end
	local _, _, sender, subject, money, _, daysLeft, itemCount = GetInboxHeaderInfo(index)
	if not subject then return end
	local fp = table.concat({ tostring(sender), subject, tostring(money), string.format("%.4f", daysLeft or 0), tostring(itemCount) }, "|")
	local now = GetTime()
	if recent[fp] and now - recent[fp] < 300 then return end

	local invoiceType, itemName, _, bid, buyout, deposit, consignment, _, _, count
	if GetInboxInvoiceInfo then
		invoiceType, itemName, _, bid, buyout, deposit, consignment, _, _, count = GetInboxInvoiceInfo(index)
	end
	if invoiceType == "seller" and what ~= "item" and (money or 0) > 0 then
		recent[fp] = now
		local net = money - (deposit or 0)
		recordSale(itemName or subject:match(SOLD), net, net + (consignment or 0), count)
	elseif invoiceType == "buyer" and what ~= "money" then
		recent[fp] = now
		local name, itemID, _, n
		if GetInboxItem then name, itemID, _, n = GetInboxItem(index, 1) end
		local paid = (bid and bid > 0) and bid or buyout
		groupBuy(name or itemName, itemID, n, paid)
	elseif what ~= "money" and subject:match(EXPIRED) then
		recent[fp] = now
		local name, itemID, _, n
		if GetInboxItem then name, itemID, _, n = GetInboxItem(index, 1) end
		recordExpired(name or subject:match(EXPIRED), n, itemID)
	end
end

if hooksecurefunc then
	if TakeInboxMoney then hooksecurefunc("TakeInboxMoney", function(i) processMail(i, "money") end) end
	if TakeInboxItem then hooksecurefunc("TakeInboxItem", function(i) processMail(i, "item") end) end
	if AutoLootMailItem then hooksecurefunc("AutoLootMailItem", function(i) processMail(i, "all") end) end
end

-- Crafting time: "You create: [item]" lines; the gap to the previous create of the same item is crafting time.
local CREATE_PREFIX = ((type(LOOT_ITEM_CREATED_SELF) == "string" and LOOT_ITEM_CREATED_SELF) or "You create: %s."):match("^(.-)%%s")
local lastCreate = {}
local ev = CreateFrame("Frame")
ev:RegisterEvent("CHAT_MSG_LOOT")
ev:SetScript("OnEvent", function(_, _, msg)
	local l = ledger()
	if not (l and type(msg) == "string" and CREATE_PREFIX and msg:sub(1, #CREATE_PREFIX) == CREATE_PREFIX) then return end
	local id = tonumber(msg:match("|Hitem:(%d+)"))
	if not id then return end
	local units = tonumber(msg:match("|r[xX](%d+)")) or 1
	local c = l.crafts[id] or { crafts = 0, units = 0, seconds = 0, gaps = 0 }
	l.crafts[id] = c
	c.crafts, c.units = c.crafts + 1, c.units + units
	local now = GetTime()
	if lastCreate[id] and now - lastCreate[id] <= CRAFT_GAP_MAX then
		c.seconds, c.gaps = c.seconds + (now - lastCreate[id]), c.gaps + 1
	end
	lastCreate[id] = now
	if ns.EpisodeCraft then ns.EpisodeCraft(id, units) end
end)

---------------------------------------------------------------------------
-- Corrections
---------------------------------------------------------------------------

local function clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end
local function blend(raw, n) return 1 + (raw - 1) * n / (n + BLEND) end
local function enabled() return ns.Setting("corrections") == 1 end

-- Your record plus friends' shared ones (Share.lua) at half weight, field by field; nil when nobody has one.
-- kind: "sales" or "buys" (keyed by item name) or "crafts" (keyed by item ID).
local SHARED_WEIGHT = 0.5
local DEFAULTS = {
	sales = { units = 0, events = 0, net = 0, expired = 0, expiredEvents = 0, expNet = 0, expFor = 0 },
	buys = { units = 0, events = 0, paid = 0, expected = 0, paidFor = 0 },
	crafts = { crafts = 0, units = 0, seconds = 0, gaps = 0 },
}
local function combined(kind, key)
	local out
	local function add(r, weight)
		if type(r) ~= "table" then return end
		out = out or {}
		for field in pairs(DEFAULTS[kind]) do
			out[field] = (out[field] or 0) + (tonumber(r[field]) or 0) * weight
		end
	end
	local l = ledger()
	add(l and l[kind][key], 1)
	local own = out ~= nil
	for _, data in pairs((WhatToDoDB and WhatToDoDB.shared) or {}) do
		local r = data[kind] and data[kind][key]
		if r then
			add(r, kind == "crafts" and 1 or SHARED_WEIGHT) -- craft timings are objective: full weight
			out.friends = (out.friends or 0) + 1
		end
	end
	if out then out.own = own end
	return out
end

-- An item's sales record, own plus friends' (half weight), or nil.
function ns.SalesRecord(itemID) return combined("sales", ns.ItemName(itemID)) end

-- Multiplier for an item's expected AH net: realized price vs Auctionator's, times the share that sold.
-- Returns factor, sale record (or nil).
function ns.SellFactor(itemID)
	local s = ns.SalesRecord(itemID)
	if not s or not enabled() then return 1, s end
	local ratio = (s.expNet > 0) and clamp(s.expFor / s.expNet, 0.1, 2) or 1
	local offered = s.units + s.expired
	local through = offered > 0 and (s.units / offered) or 1
	return clamp(blend(ratio * through, s.events + s.expiredEvents), 0.05, 2), s
end

-- Multiplier for a reagent's AH cost: what you actually paid vs the scanned minimum. Returns factor, record.
-- Auctionator's price is the cheapest listing; a batch's worth of materials climbs the listings and costs more.
-- The starting markup for a materials purchase is what your own materials purchases paid over Auctionator,
-- all of them pooled (1.3 while there are none); other items start at 1. An item's own purchases take over
-- as they come (BLEND).
local MATERIAL_PRIOR, materialPrior, priorKey = 1.3, nil, nil
local function marketMarkup(itemID)
	if not (ns.ItemGroup and ns.ItemGroup(itemID) == "material") then return 1 end
	local l = ledger()
	local key = l and #l.log
	if priorKey ~= key then
		priorKey = key
		local paid, expected, events = 0, 0, 0
		for name, b in pairs((l and l.buys) or {}) do
			local id = idByName(name)
			if id and b.expected > 0 and ns.ItemGroup(id) == "material" then
				paid, expected, events = paid + b.paidFor, expected + b.expected, events + b.events
			end
		end
		local raw = expected > 0 and clamp(paid / expected, 1, 3) or MATERIAL_PRIOR
		-- few purchases: lean on the default markup
		materialPrior = MATERIAL_PRIOR + (raw - MATERIAL_PRIOR) * events / (events + BLEND)
	end
	return materialPrior
end

function ns.BuyFactor(itemID)
	local prior = enabled() and marketMarkup(itemID) or 1
	local b = combined("buys", ns.ItemName(itemID))
	if not b or not enabled() or b.expected <= 0 then return prior, b end
	local raw = clamp(b.paidFor / b.expected, 0.5, 3)
	return clamp(prior + (raw - prior) * b.events / (b.events + BLEND), 0.5, 3), b
end

-- Measured seconds per craft of a product (needs a few timed crafts, yours or friends'), or nil.
function ns.CraftSeconds(itemID)
	local c = combined("crafts", itemID)
	if c and c.gaps >= 5 and enabled() then return c.seconds / c.gaps, c end
end

-- Copper actually received from AH sales over the last `days` days.
function ns.Income(days)
	local l = ledger()
	if not l then return 0 end
	local since, sum = time() - days * 86400, 0
	for i = #l.log, 1, -1 do
		local e = l.log[i]
		if e.t < since then break end
		if e.kind == "sold" then sum = sum + e.copper end
	end
	return sum
end

-- Short text for a factor, e.g. "x0.82", or nil when it's ~1.
function ns.FactorText(f)
	if math.abs(f - 1) < 0.02 then return nil end
	return string.format("x%.2f", f)
end

function ns.LedgerReport()
	local l = ledger()
	if not l then return end
	ns.Out(string.format(T("виручка з аукціону: 7 днів %s, 30 днів %s"), ns.Coin(ns.Income(7)), ns.Coin(ns.Income(30))))
	local rows = {}
	for name, s in pairs(l.sales) do rows[#rows + 1] = { name = name, s = s } end
	table.sort(rows, function(a, b) return a.s.net > b.s.net end)
	for i = 1, math.min(10, #rows) do
		local s = rows[i].s
		local ratio = s.expNet > 0 and string.format(T("%.0f%% від очікуваного"), s.expFor / s.expNet * 100) or T("без порівняння")
		local offered = s.units + s.expired
		print(string.format(T("  %s: продано %d, повернулось %d (%.0f%%), отримано %s, %s"),
			rows[i].name, s.units, s.expired, offered > 0 and s.units / offered * 100 or 0, ns.Coin(s.net), ratio))
	end
	local buys = 0
	for _ in pairs(l.buys) do buys = buys + 1 end
	local crafts = 0
	for _ in pairs(l.crafts) do crafts = crafts + 1 end
	print(string.format(T("  купівель: %d предметів, крафтів з таймінгом: %d предметів"), buys, crafts))
end

-- Once: purchases booked before 0.22 counted every mail of a purchase at the whole price. Rebuild the
-- purchase records from the log with the mails of one purchase merged (same item and price within a minute),
-- and scale down what's left of the purchase lots (Episodes.lua) by the same item's overcount.
function ns.FixDuplicateBuys()
	local l = ledger()
	if not l or (WhatToDoDB.fixes and WhatToDoDB.fixes.dupBuys) then return end
	WhatToDoDB.fixes = WhatToDoDB.fixes or {}
	local merged, byName, raw = {}, {}, {}
	local last = {} -- name -> merged log entry of the current purchase
	for _, e in ipairs(l.log) do
		if e.kind == "bought" then
			raw[e.name] = (raw[e.name] or 0) + (e.copper or 0)
			local m = last[e.name]
			if m and m.copper == e.copper and e.t - m.t <= 60 then
				m.units = (m.units or 1) + (e.units or 1)
				if e.expected then m.expected = (m.expected or 0) + e.expected end
			else
				m = { t = e.t, kind = "bought", name = e.name, units = e.units or 1, copper = e.copper, expected = e.expected }
				last[e.name] = m
				merged[#merged + 1] = m
			end
		else
			merged[#merged + 1] = e
		end
	end
	local buys = {}
	for _, e in ipairs(merged) do
		if e.kind == "bought" then
			local b = buys[e.name] or { units = 0, events = 0, paid = 0, expected = 0, paidFor = 0 }
			buys[e.name] = b
			b.units, b.events, b.paid, b.last = b.units + (e.units or 1), b.events + 1, b.paid + e.copper, e.t
			if e.expected then b.expected, b.paidFor = b.expected + e.expected, b.paidFor + e.copper end
		end
	end
	-- items whose purchases are older than the log keep their record
	for name, b in pairs(l.buys) do if not raw[name] then buys[name] = b end end
	l.log, l.buys = merged, buys
	-- the lots left: every unit at the item's corrected average price (the overcount sat on single units)
	local unitById = {}
	for name in pairs(raw) do
		local id, b = idByName(name), buys[name]
		if id and b and b.units > 0 then unitById[id] = b.paid / b.units end
	end
	local ep = WhatToDoDB.episodes
	if ep and ep.lots then
		for itemID, lots in pairs(ep.lots) do
			local id = tonumber(itemID) or itemID
			local name = ns.ItemName(id)
			local unit = unitById[id] or (buys[name] and raw[name] and buys[name].units > 0 and buys[name].paid / buys[name].units)
			if unit then
				for _, lot in ipairs(lots) do lot.cost = math.min(lot.cost, unit) end
			end
		end
	end
	-- batches open now hold costs from the overcounted purchases: kept, but not taught to the models
	if ep and ep.open then
		for _, b in pairs(ep.open) do b.untrusted = true end
	end
	WhatToDoDB.fixes.dupBuys = true
end

local fixer = CreateFrame("Frame")
fixer:RegisterEvent("PLAYER_ENTERING_WORLD")
fixer:SetScript("OnEvent", function(self)
	self:UnregisterAllEvents()
	C_Timer.After(5, function() pcall(ns.FixDuplicateBuys) end) -- item names have to be cached first
end)

---------------------------------------------------------------------------
-- Posting: WhatToDo's own record of what you put on the AH (Auctionator's posting history doesn't always
-- get it). WhatToDoDB.posts[itemID] = { { time, quantity, price (per unit buyout) }, ... } (newest last).
-- Feeds batch tracking (Episodes.lua: posted, first post) and the units in a sale (unitsFromPostings).
---------------------------------------------------------------------------
local KEEP_POSTS = 30

local function recordPost(itemID, quantity, unitPrice)
	if not (WhatToDoDB and itemID and quantity and quantity > 0) then return end
	WhatToDoDB.posts = WhatToDoDB.posts or {}
	local list = WhatToDoDB.posts[itemID] or {}
	WhatToDoDB.posts[itemID] = list
	list[#list + 1] = { time = time(), quantity = quantity, price = unitPrice }
	while #list > KEEP_POSTS do table.remove(list, 1) end
	if ns.EpisodePost then ns.EpisodePost(itemID, quantity) end
end

-- Legacy AH: the item sits in the sell slot; remember it while it does, the slot may be empty after posting.
local sellSlot
local function readSellSlot()
	if not GetAuctionSellItemInfo then return end
	local name, _, count, _, _, _, _, _, _, itemID = GetAuctionSellItemInfo()
	if name then sellSlot = { id = itemID or idByName(name), count = count } end
end
local slotWatch = CreateFrame("Frame")
pcall(slotWatch.RegisterEvent, slotWatch, "NEW_AUCTION_UPDATE")
slotWatch:SetScript("OnEvent", readSellSlot)

if hooksecurefunc and PostAuction then
	hooksecurefunc("PostAuction", function(minBid, buyout, runTime, stackSize, numStacks)
		readSellSlot()
		local slot = sellSlot
		if not (slot and slot.id) then return end
		local size = stackSize or slot.count or 1
		local stacks = numStacks or 1
		recordPost(slot.id, size * stacks, (buyout and buyout > 0 and size > 0) and buyout / size or nil)
	end)
end
-- Modern AH
if hooksecurefunc and C_AuctionHouse then
	local function idOf(location)
		local ok, id = pcall(function() return C_Item.GetItemID(location) end)
		return ok and id or nil
	end
	if C_AuctionHouse.PostItem then
		hooksecurefunc(C_AuctionHouse, "PostItem", function(location, _, quantity, _, buyout)
			local q = quantity or 1
			recordPost(idOf(location), q, buyout and buyout / q or nil)
		end)
	end
	if C_AuctionHouse.PostCommodity then
		hooksecurefunc(C_AuctionHouse, "PostCommodity", function(location, _, quantity, unitPrice)
			recordPost(idOf(location), quantity, unitPrice)
		end)
	end
end
