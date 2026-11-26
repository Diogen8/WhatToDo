-- What every character owns: bags on every change, the bank while it's open. Account-wide, so alts count while
-- logged out: WhatToDoDB.inventory[charKey] = { bags = { [itemID] = n }, bank = { [itemID] = n }, bagsAt, bankAt }.
-- Recrafts use owned reagents first (Craft.lua): at what they'd fetch, not at what buying them costs.
local _, ns = ...
local T = function(s) return ns.T(s) end

local function scan(bags)
	local items = {}
	for _, bag in ipairs(bags) do
		local slots = (C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots)(bag) or 0
		for slot = 1, slots do
			local id, count
			if C_Container and C_Container.GetContainerItemInfo then
				local info = C_Container.GetContainerItemInfo(bag, slot)
				if info then id, count = info.itemID, info.stackCount end
			elseif GetContainerItemInfo then
				local _, n, _, _, _, _, link = GetContainerItemInfo(bag, slot)
				id, count = link and tonumber(link:match("item:(%d+)")), n
			end
			if id and count then items[id] = (items[id] or 0) + count end
		end
	end
	return items
end

local function record(which)
	if not WhatToDoDB then return end
	WhatToDoDB.inventory = WhatToDoDB.inventory or {}
	local key = ns.CharKey()
	local inv = WhatToDoDB.inventory[key] or {}
	WhatToDoDB.inventory[key] = inv
	if which == "bags" then
		local bags = {}
		for b = 0, (NUM_BAG_SLOTS or 4) do bags[#bags + 1] = b end
		inv.bags, inv.bagsAt = scan(bags), time()
	else
		local bags = { BANK_CONTAINER or -1 }
		local first = (NUM_BAG_SLOTS or 4) + 1
		for b = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do bags[#bags + 1] = b end
		inv.bank, inv.bankAt = scan(bags), time()
	end
end

local bankOpen, pending = false, false
local watch = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED" }) do
	pcall(watch.RegisterEvent, watch, event)
end
watch:SetScript("OnEvent", function(_, event)
	if event == "BANKFRAME_OPENED" then bankOpen = true end
	if event == "BANKFRAME_CLOSED" then bankOpen = false return end
	if pending then return end
	pending = true
	C_Timer.After(1, function() -- many bag events come at once: one scan a second is plenty
		pending = false
		pcall(record, "bags")
		if bankOpen then pcall(record, "bank") end
	end)
end)

-- How many of an item every character owns (bags and bank).
function ns.Owned(itemID)
	local total = 0
	for _, inv in pairs((WhatToDoDB and WhatToDoDB.inventory) or {}) do
		total = total + ((inv.bags or {})[itemID] or 0) + ((inv.bank or {})[itemID] or 0)
	end
	return total
end

-- "Trader 3 (bank), Diogen 2"
function ns.OwnedWhere(itemID)
	local parts = {}
	for key, inv in pairs((WhatToDoDB and WhatToDoDB.inventory) or {}) do
		local bags, bank = (inv.bags or {})[itemID] or 0, (inv.bank or {})[itemID] or 0
		if bags + bank > 0 then
			local name = key:match("^([^-]+)") or key
			local text = name .. " " .. (bags + bank)
			if bank > 0 and bags == 0 then text = text .. T(" (банк)") elseif bank > 0 then text = text .. string.format(T(" (%d у банку)"), bank) end
			parts[#parts + 1] = text
		end
	end
	table.sort(parts)
	return table.concat(parts, ", ")
end

---------------------------------------------------------------------------
-- An Auctionator shopping list for a recraft batch (right-click on a recraft row): what's still to buy,
-- with the most worth paying for each.
---------------------------------------------------------------------------
function ns.MakeShoppingList(a)
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if not (api and api.CreateShoppingList and api.ConvertToSearchString) then
		ns.Out(T("Потрібен Auctionator зі списками покупок."))
		return
	end
	local list = a.shopping or {}
	if #list == 0 then
		ns.Out(string.format(T("%s: усе потрібне вже є у персонажів, купувати нічого."), a.title))
		return
	end
	local strings, lines = {}, {}
	for _, item in ipairs(list) do
		local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
		local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(item.id)) or (getInfo and getInfo(item.id))
		if not name then
			ns.Out(T("Назви предметів ще вантажаться - спробуйте за секунду."))
			return
		end
		strings[#strings + 1] = api.ConvertToSearchString("WhatToDo", {
			searchString = name, isExact = true, categoryKey = "", quantity = item.quantity, maxPrice = item.maxPrice,
		})
		lines[#lines + 1] = string.format("%dx %s (<= %s)", item.quantity, name, ns.Coin(item.maxPrice))
	end
	local listName = "WhatToDo: " .. (ns.ItemName(a.product) or a.title)
	local ok, err = pcall(api.CreateShoppingList, "WhatToDo", listName, strings)
	if not ok then
		ns.Out(T("Auctionator не створив список: ") .. tostring(err))
		return
	end
	ns.Out(string.format(T("Список покупок \"%s\" в Auctionator: %s"), listName, table.concat(lines, ", ")))
end
