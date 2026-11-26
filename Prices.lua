-- Prices from Auctionator: its public API v1 for prices, scan age and vendor prices; listed quantities
-- from its database's price history (DatabaseMixin:GetPriceHistory), which the API doesn't expose.
local _, ns = ...
local T = function(s) return ns.T(s) end
local CALLER = "WhatToDo"

function ns.HasAuctionator()
	return Auctionator ~= nil and Auctionator.API ~= nil and Auctionator.API.v1 ~= nil and Auctionator.Database ~= nil
end

local function api(fn, itemID)
	if not ns.HasAuctionator() then return nil end
	local f = Auctionator.API.v1[fn]
	if not f then return nil end
	local ok, value = pcall(f, CALLER, itemID)
	if ok then return value end
end

-- Lowest buyout Auctionator last saw (copper per unit) and how many days ago it was scanned.
-- age nil with a price: older than Auctionator's history window. (ns.AuctionPrice, below, also weighs
-- prices friends shared.)
local function ownAuctionPrice(itemID)
	local price = api("GetAuctionPriceByItemID", itemID)
	if type(price) ~= "number" or price <= 0 then return nil end
	local age = api("GetAuctionAgeByItemID", itemID)
	return price, type(age) == "number" and age or nil
end

-- What a vendor charges for the item (Auctionator caches it when you visit a merchant), or nil.
function ns.VendorBuyPrice(itemID)
	local price = api("GetVendorPriceByItemID", itemID)
	if type(price) == "number" and price > 0 then return price end
end

-- Units listed on the most recent scan day, or nil when unknown.
local function ownAvailable(itemID)
	if not ns.HasAuctionator() or not Auctionator.Database.GetPriceHistory then return nil end
	local ok, history = pcall(Auctionator.Database.GetPriceHistory, Auctionator.Database, tostring(itemID))
	if not ok or type(history) ~= "table" then return nil end
	local latest = history[1] -- newest day first
	if latest and type(latest.available) == "number" then return latest.available end
end

-- Cheapest way to buy one unit: vendor or AH. Returns cost, "Vendor"/"AH", age (AH only).
function ns.BuyCost(itemID)
	local vendor = ns.VendorBuyPrice(itemID)
	local ah, age = ns.AuctionPrice(itemID)
	if vendor and (not ah or vendor <= ah) then return vendor, "Vendor" end
	if ah then return ah, "AH", age end
end

-- What one unit brings on the AH after the cut. Returns net, gross, age.
function ns.SellNet(itemID)
	local price, age = ns.AuctionPrice(itemID)
	if not price then return nil end
	return price * (1 - ns.Setting("ahCut")), price, age
end

---------------------------------------------------------------------------
-- Price freshness and trust
-- Auctionator keeps only the scan DAY of a price. So WhatToDo records the exact time itself: it hooks the
-- database's SetPrice (every full scan and every AH search goes through it) and keeps
-- WhatToDoDB.priceSeen[itemID] = time(). Prices seen before that are aged by a worst case: the last full
-- scan if it ran on the item's day (the item was updated then or later), else the start of that day.
-- Trust: up to 6 h old 100%, 6-12 h falling to 50%, older than 12 h unreliable (0).
---------------------------------------------------------------------------

local FRESH_HOURS, STALE_HOURS = 6, 12
local KEEP_SEEN_DAYS = 30
local hookedDB

function ns.HookAuctionatorDB()
	if not (ns.HasAuctionator() and WhatToDoDB and hooksecurefunc) then return end
	local db = Auctionator.Database
	if hookedDB == db or type(db.SetPrice) ~= "function" then return end
	hookedDB = db
	WhatToDoDB.priceSeen = WhatToDoDB.priceSeen or {}
	hooksecurefunc(db, "SetPrice", function(_, dbKey)
		if type(dbKey) == "string" and WhatToDoDB and dbKey:find("^%d+$") then
			WhatToDoDB.priceSeen[dbKey] = time()
		end
	end)
end

function ns.PriceHookActive() return hookedDB ~= nil end

local function pruneSeen()
	local seen = WhatToDoDB and WhatToDoDB.priceSeen
	if not seen then return end
	local cutoff = time() - KEEP_SEEN_DAYS * 86400
	for key, t in pairs(seen) do
		if t < cutoff then seen[key] = nil end
	end
end

local hookFrame = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "AUCTION_HOUSE_SHOW" }) do pcall(hookFrame.RegisterEvent, hookFrame, event) end
hookFrame:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then pruneSeen() end
	ns.HookAuctionatorDB()
	C_Timer.After(2, ns.HookAuctionatorDB) -- Auctionator may build its database a moment later
end)

local function lastFullScan()
	local sv = (Auctionator and Auctionator.SavedState) or AUCTIONATOR_SAVEDVARS or {}
	return math.max(sv.TimeOfLastReplicateScan or 0, sv.TimeOfLastGetAllScan or 0, sv.TimeOfLastBrowseScan or 0)
end

-- How many hours old your own AH price is (an upper bound when not recorded exactly), and whether exact.
-- nil without a price.
local function ownHours(itemID)
	ns.HookAuctionatorDB()
	local now = time()
	local seen = WhatToDoDB and WhatToDoDB.priceSeen and WhatToDoDB.priceSeen[tostring(itemID)]
	if seen then return (now - seen) / 3600, true end
	local price, ageDays = ownAuctionPrice(itemID)
	if not price then return nil end
	if not ageDays then return math.huge, false end
	local day0 = Auctionator.Constants and Auctionator.Constants.SCAN_DAY_0
	if not day0 then return ageDays * 24 + 24, false end
	local today = math.floor((now - day0) / 86400)
	local dayStart = day0 + (today - ageDays) * 86400
	local since = dayStart
	local full = lastFullScan()
	if full >= dayStart and full < dayStart + 86400 then since = full end
	return (now - since) / 3600, false
end

-- The freshest price a friend shared for the item (Share.lua): { p = price, t = scan time, a = listed, from }.
local function sharedPrice(itemID)
	local best
	for sender, data in pairs((WhatToDoDB and WhatToDoDB.shared) or {}) do
		local e = data.prices and data.prices[itemID]
		if e and (not best or e.t > best.t) then
			best = { p = e.p, t = e.t, a = e.a, from = sender }
		end
	end
	return best
end

-- The price to use: your own, or a friend's when theirs was scanned more recently.
-- Returns price, hours old, exact, shared entry (or nil), own age in days.
local function bestPrice(itemID)
	local price, ageDays = ownAuctionPrice(itemID)
	local hours, exact
	if price then hours, exact = ownHours(itemID) end
	local shared = sharedPrice(itemID)
	if shared then
		local sharedHours = math.max(0, (time() - shared.t) / 3600)
		if not price or (hours or math.huge) > sharedHours then
			return shared.p, sharedHours, true, shared, math.floor(sharedHours / 24)
		end
	end
	if price then return price, hours, exact, nil, ageDays end
end

function ns.AuctionPrice(itemID)
	local price, _, _, _, ageDays = bestPrice(itemID)
	if price then return price, ageDays end
end

function ns.PriceHours(itemID)
	local price, hours, exact = bestPrice(itemID)
	if price then return hours, exact end
end

function ns.Available(itemID)
	local price, _, _, shared = bestPrice(itemID)
	if shared then return shared.a end
	return ownAvailable(itemID)
end

-- Who scanned the price in use, when it came from a friend; nil for your own.
function ns.PriceFrom(itemID)
	local price, _, _, shared = bestPrice(itemID)
	return shared and shared.from
end

-- For sharing: your own exact price snapshot { p, t, a } of an item, scanned within maxHours, or nil.
function ns.OwnPriceSnapshot(itemID, maxHours)
	local seen = WhatToDoDB and WhatToDoDB.priceSeen and WhatToDoDB.priceSeen[tostring(itemID)]
	if not seen or time() - seen > maxHours * 3600 then return nil end
	local price = ownAuctionPrice(itemID)
	if not price then return nil end
	return { p = price, t = seen, a = ownAvailable(itemID) }
end

function ns.TrustOfHours(hours)
	if not hours then return nil end
	if hours <= FRESH_HOURS then return 1 end
	if hours <= STALE_HOURS then return 1 - 0.5 * (hours - FRESH_HOURS) / (STALE_HOURS - FRESH_HOURS) end
	return 0
end

-- "12 хв", "3.5 год", "2 дн."
function ns.AgeText(hours)
	if not hours then return "?" end
	if hours == math.huge then return T("понад 21 дн.") end
	if hours < 1 then return string.format(T("%d хв"), math.floor(hours * 60 + 0.5)) end
	if hours < 48 then return string.format(T("%.1f год"), hours) end
	return string.format(T("%d дн."), math.floor(hours / 24))
end

-- Overall trust in a suggestion: real gold received weighs more than fresh prices.
--   trust = 0.4 x price freshness + 0.6 x evidence (0..1 each)
-- With no gold ever received for the activity (evidence 0) it can't go above 40%.
local PRICE_WEIGHT, EVIDENCE_WEIGHT = 0.4, 0.6
function ns.CombineTrust(priceTrust, evidence)
	return PRICE_WEIGHT * (priceTrust or 0) + EVIDENCE_WEIGHT * (evidence or 0)
end

-- Evidence from a number of real sales: 1 -> 0.25, 3 -> 0.5, 9 -> 0.75.
function ns.EvidenceOfSales(n)
	n = n or 0
	return n / (n + 3)
end

-- Times an item was actually sold: every character's, plus friends' shared sales at half weight. 0 if never.
function ns.SalesCount(itemID)
	local s = ns.SalesRecord and ns.SalesRecord(itemID)
	return s and s.events or 0
end

-- Text and colour for a trust value: green from 75%, yellow from 40%, red below.
function ns.TrustLabel(trust)
	if not trust then return "", 0.6, 0.6, 0.6 end
	local text = string.format(T("довіра %d%%"), math.floor(trust * 100 + 0.5))
	if trust >= 0.75 then return text, 0.3, 0.9, 0.3 end
	if trust >= 0.4 then return text, 1, 0.82, 0.2 end
	return text, 1, 0.3, 0.3
end

-- "успіх 85%", coloured like trust: the model's chance of success (Model.lua).
function ns.SuccessLabel(p)
	if not p then return "", 0.6, 0.6, 0.6 end
	local text = string.format(T("успіх %d%%"), math.floor(p * 100 + 0.5))
	if p >= 0.75 then return text, 0.3, 0.9, 0.3 end
	if p >= 0.4 then return text, 1, 0.82, 0.2 end
	return text, 1, 0.3, 0.3
end

-- Compact gold for ranges: "15.3g", "2.1g", "54s", "-1.2g".
function ns.ShortGold(copper)
	copper = copper or 0
	local sign = copper < 0 and "-" or ""
	copper = math.abs(copper)
	if copper >= 100000 then return sign .. string.format("%dg", math.floor(copper / 10000 + 0.5)) end
	if copper >= 10000 then return sign .. string.format("%.1fg", copper / 10000) end
	if copper >= 100 then return sign .. string.format("%ds", math.floor(copper / 100 + 0.5)) end
	return sign .. string.format("%dc", math.floor(copper + 0.5))
end

-- Tooltip text explaining a trust value.
function ns.TrustExplain(priceTrust, evidence, evidenceText)
	return string.format(T("ціни %d%%, факт %d%%%s"), math.floor((priceTrust or 0) * 100 + 0.5), math.floor((evidence or 0) * 100 + 0.5),
		evidenceText and (" (" .. evidenceText .. ")") or "")
end
