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
	local history = type(AUCTIONATOR_POSTING_HISTORY) == "table" and itemID and AUCTIONATOR_POSTING_HISTORY[tostring(itemID)]
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
end

local function recordExpired(name, units)
	local l = ledger()
	if not (l and name) then return end
	local s = l.sales[name] or { units = 0, events = 0, net = 0, expired = 0, expiredEvents = 0, expNet = 0, expFor = 0 }
	l.sales[name] = s
	s.expired, s.expiredEvents, s.last = s.expired + (units or 1), s.expiredEvents + 1, time()
	log("expired", name, units or 1, 0, nil)
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
end

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
		recordBuy(name or itemName, itemID, n, paid)
	elseif what ~= "money" and subject:match(EXPIRED) then
		recent[fp] = now
		local name, _, _, n
		if GetInboxItem then name, _, _, n = GetInboxItem(index, 1) end
		recordExpired(name or subject:match(EXPIRED), n)
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
end)

---------------------------------------------------------------------------
-- Corrections
---------------------------------------------------------------------------

local function clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end
local function blend(raw, n) return 1 + (raw - 1) * n / (n + BLEND) end
local function enabled() return ns.Setting("corrections") == 1 end

-- Multiplier for an item's expected AH net: realized price vs Auctionator's, times the share that sold.
-- Returns factor, sale record (or nil).
function ns.SellFactor(itemID)
	local l = ledger()
	local s = l and l.sales[ns.ItemName(itemID)]
	if not s or not enabled() then return 1, s end
	local ratio = (s.expNet > 0) and clamp(s.expFor / s.expNet, 0.1, 2) or 1
	local offered = s.units + s.expired
	local through = offered > 0 and (s.units / offered) or 1
	return clamp(blend(ratio * through, s.events + s.expiredEvents), 0.05, 2), s
end

-- Multiplier for a reagent's AH cost: what you actually paid vs the scanned minimum. Returns factor, record.
function ns.BuyFactor(itemID)
	local l = ledger()
	local b = l and l.buys[ns.ItemName(itemID)]
	if not b or not enabled() or b.expected <= 0 then return 1, b end
	return clamp(blend(clamp(b.paidFor / b.expected, 0.5, 3), b.events), 0.5, 3), b
end

-- Measured seconds per craft of a product (needs a few timed crafts), or nil.
function ns.CraftSeconds(itemID)
	local l = ledger()
	local c = l and l.crafts[itemID]
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
	ns.Out(string.format("виручка з аукціону: 7 днів %s, 30 днів %s", ns.Coin(ns.Income(7)), ns.Coin(ns.Income(30))))
	local rows = {}
	for name, s in pairs(l.sales) do rows[#rows + 1] = { name = name, s = s } end
	table.sort(rows, function(a, b) return a.s.net > b.s.net end)
	for i = 1, math.min(10, #rows) do
		local s = rows[i].s
		local ratio = s.expNet > 0 and string.format("%.0f%% від очікуваного", s.expFor / s.expNet * 100) or "без порівняння"
		local offered = s.units + s.expired
		print(string.format("  %s: продано %d, повернулось %d (%.0f%%), отримано %s, %s",
			rows[i].name, s.units, s.expired, offered > 0 and s.units / offered * 100 or 0, ns.Coin(s.net), ratio))
	end
	local buys = 0
	for _ in pairs(l.buys) do buys = buys + 1 end
	local crafts = 0
	for _ in pairs(l.crafts) do crafts = crafts + 1 end
	print(string.format("  купівель: %d предметів, крафтів з таймінгом: %d предметів", buys, crafts))
end
