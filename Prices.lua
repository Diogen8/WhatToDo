-- Prices from Auctionator: its public API v1 for prices, scan age and vendor prices; listed quantities
-- from its database's price history (DatabaseMixin:GetPriceHistory), which the API doesn't expose.
local _, ns = ...
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
-- age nil with a price: older than Auctionator's history window.
function ns.AuctionPrice(itemID)
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
function ns.Available(itemID)
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
