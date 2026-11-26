-- The window (/wtd) and chat commands.
local _, ns = ...

local ROW_HEIGHT, ROWS_MAX = 38, 60
local frame, rows, filter = nil, {}, "all"
local KIND_TAG = { farm = "|cff66cc66ФАРМ|r", craft = "|cff66aaffКРАФТ|r" }

local function coinText(copper)
	copper = math.floor(copper / 100 + 0.5) * 100 -- to the silver
	if GetCoinTextureString then return GetCoinTextureString(copper) end
	return ns.Coin(copper)
end

local function statusText(count)
	local parts = {}
	parts[#parts + 1] = ns.HasAuctionator() and "Auctionator: є" or "|cffff6666Auctionator: немає|r"
	parts[#parts + 1] = ns.HasYield() and "Yield: є" or "|cffff6666Yield: немає|r"
	local recipes, chars = ns.RecipeCount()
	parts[#parts + 1] = string.format("рецептів: %d (%d перс.)", recipes, chars)
	parts[#parts + 1] = string.format("варіантів: %d", count)
	return table.concat(parts, "   ")
end

local function rowTooltip(row)
	local a = row.activity
	if not a then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:AddLine(a.title, 1, 0.82, 0, true)
	GameTooltip:AddDoubleLine("Золота за годину", coinText(a.perHour), 1, 1, 1, 1, 1, 1)
	for _, line in ipairs(a.tooltip or {}) do
		GameTooltip:AddDoubleLine(line[1], line[2], 0.8, 0.8, 0.8, 1, 1, 1)
	end
	if a.kind == "craft" then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Час на продаж не враховано. Ціни — мінімальні зі сканування.", 0.6, 0.6, 0.6, true)
	elseif a.confidence and a.confidence < 1 then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Мало даних — цифра може сильно гуляти.", 1, 0.5, 0.3, true)
	end
	GameTooltip:Show()
end

local function makeRow(parent, i)
	local r = CreateFrame("Button", nil, parent)
	r:SetHeight(ROW_HEIGHT)
	r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
	r:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
	local hl = r:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.08)
	if i % 2 == 0 then
		local bg = r:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(1, 1, 1, 0.03)
	end
	r.rank = r:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	r.rank:SetPoint("TOPLEFT", 4, -4)
	r.rank:SetWidth(22)
	r.rank:SetJustifyH("RIGHT")
	r.tag = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.tag:SetPoint("TOPLEFT", 32, -5)
	r.value = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	r.value:SetPoint("TOPRIGHT", -6, -4)
	r.value:SetJustifyH("RIGHT")
	r.title = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	r.title:SetPoint("TOPLEFT", 82, -4)
	r.title:SetPoint("RIGHT", r.value, "LEFT", -8, 0)
	r.title:SetJustifyH("LEFT")
	r.title:SetWordWrap(false)
	r.detail = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.detail:SetPoint("TOPLEFT", 82, -21)
	r.detail:SetPoint("RIGHT", -6, 0)
	r.detail:SetJustifyH("LEFT")
	r.detail:SetWordWrap(false)
	r.detail:SetTextColor(0.75, 0.75, 0.75)
	r:SetScript("OnEnter", rowTooltip)
	r:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return r
end

function ns.Refresh()
	if not frame or not frame:IsShown() then return end
	ns.pendingNames = false
	local list = ns.Rank(filter)
	local shown = math.min(#list, ns.Setting("results"), ROWS_MAX)
	for i = 1, shown do
		local r = rows[i] or makeRow(frame.content, i)
		rows[i] = r
		local a = list[i]
		r.activity = a
		r.rank:SetText(i .. ".")
		r.tag:SetText(KIND_TAG[a.kind] or a.kind)
		r.title:SetText(a.title)
		r.detail:SetText(a.detail or "")
		r.value:SetText(coinText(a.perHour) .. "/год")
		r:Show()
	end
	for i = shown + 1, #rows do rows[i]:Hide(); rows[i].activity = nil end
	frame.content:SetHeight(math.max(1, shown * ROW_HEIGHT))
	frame.empty:SetShown(shown == 0)
	frame.status:SetText(statusText(#list))
	for key, b in pairs(frame.tabs) do
		if key == filter then b:LockHighlight() else b:UnlockHighlight() end
	end
end

local EMPTY_TEXT = "Поки нічого порадити.\n\n" ..
	"Фарм: увімкніть Yield і пофарміть хоча б 10 хв на одному місці.\n" ..
	"Крафт: проскануйте аукціон в Auctionator і відкрийте вікна своїх професій,\n" ..
	"щоб WhatToDo запам'ятав рецепти (з усіх персонажів)."

local function create()
	local f = CreateFrame("Frame", "WhatToDoFrame", UIParent, "BasicFrameTemplateWithInset")
	f:SetSize(620, 480)
	f:SetPoint("CENTER")
	f:SetFrameStrata("HIGH")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	table.insert(UISpecialFrames, "WhatToDoFrame")

	local title = f.TitleText or f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	if not f.TitleText then title:SetPoint("TOP", 0, -5) end
	title:SetText("WhatToDo — найвигідніше за годину")

	f.tabs = {}
	local function tab(key, label, x)
		local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		b:SetSize(80, 22)
		b:SetPoint("TOPLEFT", x, -30)
		b:SetText(label)
		b:SetScript("OnClick", function() filter = key; ns.Refresh() end)
		f.tabs[key] = b
	end
	tab("all", "Усе", 12)
	tab("farm", "Фарм", 96)
	tab("craft", "Крафт", 180)

	local refresh = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	refresh:SetSize(90, 22)
	refresh:SetPoint("TOPRIGHT", -12, -30)
	refresh:SetText("Оновити")
	refresh:SetScript("OnClick", ns.Refresh)

	local scroll = CreateFrame("ScrollFrame", "WhatToDoScroll", f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 10, -58)
	scroll:SetPoint("BOTTOMRIGHT", -32, 30)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(570, 1)
	scroll:SetScrollChild(content)
	scroll:HookScript("OnSizeChanged", function(_, w) content:SetWidth(w) end)
	f.content = content

	f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.empty:SetPoint("CENTER", 0, 10)
	f.empty:SetWidth(540)
	f.empty:SetText(EMPTY_TEXT)

	f.status = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.status:SetPoint("BOTTOMLEFT", 14, 10)

	f:SetScript("OnShow", ns.Refresh)
	f:Hide()
	frame = f
end

function ns.Toggle()
	if not frame then create() end
	frame:SetShown(not frame:IsShown())
end

-- Names arriving from the server: redraw (at most twice a second) so "item:1234" placeholders resolve.
local pendingRedraw = false
local ev = CreateFrame("Frame")
ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
ev:RegisterEvent("AUCTION_HOUSE_CLOSED")
ev:SetScript("OnEvent", function(_, event)
	if event == "GET_ITEM_INFO_RECEIVED" and not ns.pendingNames then return end
	if pendingRedraw or not (frame and frame:IsShown()) then return end
	pendingRedraw = true
	C_Timer.After(0.5, function() pendingRedraw = false; ns.Refresh() end)
end)

---------------------------------------------------------------------------
-- Slash: /wtd [top|set|reset|help]
---------------------------------------------------------------------------

local SETTING_HELP = {
	craftSeconds = "сек. на крафт, якщо час касту невідомий",
	craftOverhead = "додаткові сек. на кожен крафт",
	batchOverhead = "сек. на партію (дійти до аукціону, купити, виставити)",
	maxBatch = "максимум крафтів у партії",
	supplyShare = "частка виставлених реагентів, яку реально купити (0-1)",
	minFarmMinutes = "мінімум хвилин даних Yield для місця фарму",
	maxPriceAgeDays = "макс. вік цін аукціону, днів",
	minProfit = "мінімальний прибуток за крафт, мідь",
	results = "скільки рядків показувати",
}

local function printTop(n)
	local list = ns.Rank("all")
	if #list == 0 then return ns.Out("поки нічого порадити — /wtd відкриє вікно з підказками.") end
	for i = 1, math.min(n, #list) do
		local a = list[i]
		print(string.format("%d. [%s] %s — %s/год", i, a.kind == "farm" and "фарм" or "крафт", a.title, ns.Coin(a.perHour)))
	end
end

SLASH_WHATTODO1 = "/wtd"
SLASH_WHATTODO2 = "/whattodo"
SlashCmdList.WHATTODO = function(msg)
	local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = cmd:lower()
	if cmd == "" then
		ns.Toggle()
	elseif cmd == "top" then
		printTop(tonumber(rest) or 5)
	elseif cmd == "set" then
		local key, value = rest:match("^(%S+)%s+(%S+)$")
		if key and ns.DEFAULTS[key] ~= nil and tonumber(value) then
			WhatToDoDB.settings[key] = tonumber(value)
			ns.Out(key .. " = " .. value)
			ns.Refresh()
		else
			ns.Out("налаштування (/wtd set <назва> <число>):")
			for k, help in pairs(SETTING_HELP) do print(string.format("  %s = %s — %s", k, tostring(ns.Setting(k)), help)) end
		end
	elseif cmd == "reset" then
		WhatToDoDB.settings = {}
		ns.Out("налаштування скинуто.")
		ns.Refresh()
	elseif cmd == "forget" then
		WhatToDoDB.recipes[ns.CharKey()] = nil
		ns.Out("рецепти цього персонажа забуто; відкрийте вікна професій знову.")
	else
		ns.Out("/wtd — вікно · /wtd top [n] — топ у чат · /wtd set — налаштування · /wtd reset · /wtd forget — забути рецепти персонажа")
	end
end

function ns.OnLoad() end
