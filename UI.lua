-- The window (/wtd) and chat commands.
local _, ns = ...
local T = function(s) return ns.T(s) end

local ROW_HEIGHT, ROWS_MAX = 38, 40
local frame, rows, filter = nil, {}, "all"

local function coinText(copper)
	copper = math.floor(copper / 100 + 0.5) * 100 -- to the silver
	if GetCoinTextureString then return GetCoinTextureString(copper) end
	return ns.Coin(copper)
end

local lastTotal = 0
local function statusText(count)
	local parts = {}
	if ns.shareStatus then return "|cff66ccff" .. ns.shareStatus .. "|r" end
	parts[#parts + 1] = ns.HasAuctionator() and T("Auctionator: є") or T("|cffff6666Auctionator: немає|r")
	parts[#parts + 1] = ns.HasYield() and T("Yield: є") or T("|cffff6666Yield: немає|r")
	local recipes, chars = ns.RecipeCount()
	parts[#parts + 1] = string.format(T("рецептів: %d, персонажів: %d"), recipes, chars)
	parts[#parts + 1] = string.format(T("варіантів: %d"), count)
	parts[#parts + 1] = T("виручка 7 дн.: ") .. ns.Coin(ns.Income(7))
	local notice = ns.UpdateNotice and ns.UpdateNotice()
	parts[#parts + 1] = notice and ("|cff66ff66" .. notice .. "|r") or ("v" .. (ns.VERSION or "?"))
	return table.concat(parts, "   ")
end

-- Each activity kind: its icon (rows and tabs), and its colour (header text, rule, a faint wash behind its rows).
local SECTION = {
	craft = { icon = "Interface\\Icons\\Trade_BlackSmithing", title = "РЕКРАФТ (АФК)", note = "купити матеріали -> скрафтити -> продати", color = { 0.4, 0.67, 1 } },
	learn = { icon = "Interface\\Icons\\INV_Misc_Book_09", title = "РЕКРАФТ: ЯКЩО ВИВЧИТИ", note = "для персонажів з вільним слотом професії", color = { 1, 0.6, 0.25 }, hideEmpty = true },
	farm = { icon = "Interface\\Icons\\INV_Sword_04", title = "ФАРМ МОБІВ", note = "лут і монети з мобів (історія Yield, сьогоднішні ціни)", color = { 0.95, 0.45, 0.4 } },
	mining = { icon = "Interface\\Icons\\Trade_Mining", title = "МАЙНІНГ", note = "руда й камінь з жил, за годину на місці", color = { 0.75, 0.75, 0.85 }, hideEmpty = true },
	herbalism = { icon = "Interface\\Icons\\Trade_Herbalism", title = "ЗБІР ТРАВ", note = "трави, за годину на місці", color = { 0.45, 0.85, 0.45 }, hideEmpty = true },
	skinning = { icon = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01", title = "СКІНІНГ", note = "шкури з мобів, за годину на місці", color = { 0.85, 0.7, 0.45 }, hideEmpty = true },
	fishing = { icon = "Interface\\Icons\\Trade_Fishing", title = "РИБОЛОВЛЯ", note = "улов, за годину на місці", color = { 0.3, 0.85, 0.8 }, hideEmpty = true },
}
local SECTION_ORDER = { "craft", "learn", "farm", "mining", "herbalism", "skinning", "fishing" }
local ALL_ICON = "Interface\\Icons\\INV_Misc_Coin_02"

local function rowTooltip(row)
	local a = row.activity
	if not a then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:AddLine(a.title, 1, 0.82, 0, true)
	local sec = SECTION[a.kind]
	if sec then GameTooltip:AddLine("|T" .. sec.icon .. ":14:14:0:0:64:64:5:59:5:59|t " .. T(sec.title), sec.color[1], sec.color[2], sec.color[3]) end
	if a.range then
		GameTooltip:AddDoubleLine(T("Золота за годину"), coinText(a.range[1]) .. " - " .. coinText(a.range[3]), 1, 1, 1, 1, 1, 1)
	else
		GameTooltip:AddDoubleLine(T("Золота за годину"), coinText(a.perHour), 1, 1, 1, 1, 1, 1)
	end
	if a.priceTrust == 0 then
		GameTooltip:AddLine(T("Ціни застарілі (понад 12 год) - перевірте аукціон перед тим, як діяти."), 1, 0.3, 0.3, true)
	end
	for _, line in ipairs(a.tooltip or {}) do
		GameTooltip:AddDoubleLine(line[1], line[2], 0.8, 0.8, 0.8, 1, 1, 1)
	end
	if a.kind == "craft" then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(T("Час на продаж не враховано. Ціни - мінімальні зі сканування."), 0.6, 0.6, 0.6, true)
	elseif a.kind ~= "learn" and a.confidence and a.confidence < 1 then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(T("Мало даних - цифра може сильно гуляти."), 1, 0.5, 0.3, true)
	end
	if a.product then
		GameTooltip:AddLine(a.kind == "learn" and T("Клік - що потрібно для рецепта") or T("Клік - відкрити рецепт у професії"), 0.4, 0.8, 1, true)
	end
	GameTooltip:Show()
end

local HEADER_HEIGHT = 26

local function makeRow(parent)
	local r = CreateFrame("Button", nil, parent)
	r:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
	r.hl = r:CreateTexture(nil, "HIGHLIGHT")
	r.hl:SetAllPoints()
	r.hl:SetColorTexture(1, 1, 1, 0.08)
	r.bg = r:CreateTexture(nil, "BACKGROUND")
	r.bg:SetAllPoints()
	r.rule = r:CreateTexture(nil, "ARTWORK")
	r.rule:SetHeight(1)
	r.rule:SetPoint("BOTTOMLEFT", 4, 2)
	r.rule:SetPoint("BOTTOMRIGHT", -4, 2)
	r.header = r:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	r.header:SetPoint("LEFT", 6, 0)
	r.headerNote = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	r.headerNote:SetPoint("LEFT", r.header, "RIGHT", 10, -1)
	r.headerNote:SetPoint("RIGHT", -6, 0)
	r.headerNote:SetJustifyH("LEFT")
	r.rank = r:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	r.rank:SetPoint("TOPLEFT", 4, -4)
	r.rank:SetWidth(22)
	r.rank:SetJustifyH("RIGHT")
	r.value = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	r.value:SetPoint("TOPRIGHT", -6, -4)
	r.value:SetJustifyH("RIGHT")
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(28, 28)
	r.icon:SetPoint("LEFT", 30, 0)
	r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	r.title = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	r.title:SetPoint("TOPLEFT", 64, -4)
	r.title:SetPoint("RIGHT", r.value, "LEFT", -8, 0)
	r.title:SetJustifyH("LEFT")
	r.title:SetWordWrap(false)
	r.trust = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.trust:SetPoint("TOPRIGHT", -6, -21)
	r.trust:SetJustifyH("RIGHT")
	r.detail = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.detail:SetPoint("TOPLEFT", 64, -21)
	r.detail:SetPoint("RIGHT", r.trust, "LEFT", -8, 0)
	r.detail:SetJustifyH("LEFT")
	r.detail:SetWordWrap(false)
	r.detail:SetTextColor(0.75, 0.75, 0.75)
	r:SetScript("OnEnter", rowTooltip)
	r:SetScript("OnClick", function(self)
		if self.activity and self.activity.product then ns.OpenRecipe(self.activity) end
	end)
	r:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return r
end

local function setHeader(r, kind, count)
	local s = SECTION[kind]
	local c = s.color
	r.activity = nil
	r:SetHeight(HEADER_HEIGHT)
	r:EnableMouse(false)
	r.hl:Hide()
	r.bg:SetColorTexture(c[1], c[2], c[3], 0.12)
	r.rule:SetColorTexture(c[1], c[2], c[3], 0.8)
	r.rule:Show()
	r.header:SetText(T(s.title))
	r.header:SetTextColor(c[1], c[2], c[3])
	r.headerNote:SetText(count > 0 and T(s.note) or T("нічого вигідного (/wtd - підказки)"))
	r.header:Show(); r.headerNote:Show()
	r.rank:Hide(); r.value:Hide(); r.title:Hide(); r.detail:Hide(); r.trust:Hide(); r.icon:Hide()
end

local function setActivity(r, a, rank)
	local c = SECTION[a.kind].color
	r.activity = a
	r:SetHeight(ROW_HEIGHT)
	r:EnableMouse(true)
	r.hl:Show()
	r.bg:SetColorTexture(c[1], c[2], c[3], rank % 2 == 0 and 0.07 or 0.03)
	r.rule:Hide()
	r.header:Hide(); r.headerNote:Hide()
	r.rank:SetText(rank .. ".")
	r.icon:SetTexture(SECTION[a.kind].icon)
	r.title:SetText(a.title)
	local detail = a.detail or ""
	if a.corrected and a.expectedPerHour and a.expectedPerHour > 0 then
		detail = string.format(T("|cffffcc66факт %.0f%% від прогнозу|r, "), a.perHour / a.expectedPerHour * 100) .. detail
	end
	r.detail:SetText(detail)
	r.value:SetText(a.range and (ns.ShortGold(a.range[1]) .. " - " .. ns.ShortGold(a.range[3]) .. T("/год")) or (coinText(a.perHour) .. T("/год")))
	local label, tr, tg, tb = (a.range and ns.SuccessLabel or ns.TrustLabel)(a.trust)
	r.trust:SetText(label)
	r.trust:SetTextColor(tr, tg, tb)
	r.rank:Show(); r.value:Show(); r.title:Show(); r.detail:Show(); r.trust:Show(); r.icon:Show()
end

local function emptyText()
	return T("Поки нічого порадити.\n\n") ..
		T("Збір (майнінг, трави, скінінг, риболовля) береться з тих самих сесій Yield.\n") ..
		T("Рекрафт: проскануйте аукціон в Auctionator і зайдіть кожним персонажем хоч раз,\n") ..
		T("щоб WhatToDo запам'ятав їхні професії (вікна професій - для точних рецептів).\n") ..
		T("Фарм: увімкніть Yield і пофарміть хоча б 10 хв на одному місці.")
end

function ns.Refresh()
	if not frame or not frame:IsShown() then return end
	ns.pendingNames = false
	local limit = math.min(ns.Setting("results"), ROWS_MAX)
	local used, y, total = 0, 0, 0
	local function nextRow()
		used = used + 1
		local r = rows[used] or makeRow(frame.content)
		rows[used] = r
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, -y)
		r:SetPoint("RIGHT", frame.content, "RIGHT", 0, 0)
		r:Show()
		return r
	end
	if filter == "all" then -- one list across every activity, best first; the icon tells them apart
		local list = ns.Rank("all")
		total = #list
		for i = 1, math.min(#list, limit) do
			setActivity(nextRow(), list[i], i)
			y = y + ROW_HEIGHT
		end
	end
	for _, kind in ipairs(SECTION_ORDER) do
		local list = filter ~= "all" and (filter == kind or (filter == "craft" and kind == "learn")) and ns.Rank(kind)
		if list and not (#list == 0 and SECTION[kind].hideEmpty) then
			total = total + #list
			if y > 0 then y = y + 8 end -- a gap between the sections
			setHeader(nextRow(), kind, #list)
			y = y + HEADER_HEIGHT
			for i = 1, math.min(#list, limit) do
				setActivity(nextRow(), list[i], i)
				y = y + ROW_HEIGHT
			end
		end
	end
	for i = used + 1, #rows do rows[i]:Hide(); rows[i].activity = nil end
	frame.content:SetHeight(math.max(1, y))
	frame.empty:SetText(emptyText())
	frame.empty:SetShown(total == 0 and filter == "all")
	lastTotal = total
	frame.status:SetText(statusText(total))
	for key, b in pairs(frame.tabs) do
		if key == filter then b:LockHighlight() else b:UnlockHighlight() end
	end
end


local function create()
	local f = CreateFrame("Frame", "WhatToDoFrame", UIParent, "BasicFrameTemplateWithInset")
	f:SetSize(730, 500)
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
	f.titleText = title

	f.tabs = {}
	local function tab(key, label, x)
		local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		b:SetSize(82, 22)
		b:SetPoint("TOPLEFT", x, -30)
		b.label = label
		b:SetNormalFontObject("GameFontNormalSmall")
		b:SetHighlightFontObject("GameFontHighlightSmall")
		b:SetText(label)
		local icon = b:CreateTexture(nil, "OVERLAY")
		icon:SetSize(16, 16)
		icon:SetPoint("LEFT", 5, 0)
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		icon:SetTexture(key == "all" and ALL_ICON or SECTION[key].icon)
		local text = b:GetFontString()
		if text then
			text:ClearAllPoints()
			text:SetPoint("LEFT", icon, "RIGHT", 3, 0)
			text:SetPoint("RIGHT", -4, 0)
			text:SetJustifyH("LEFT")
			text:SetWordWrap(false)
		end
		b:SetScript("OnClick", function() filter = key; ns.Refresh() end)
		f.tabs[key] = b
	end
	local TABS = {
		{ "all", "Усе" }, { "craft", "Рекрафт" }, { "farm", "Моби" }, { "mining", "Майнінг" },
		{ "herbalism", "Трави" }, { "skinning", "Скінінг" }, { "fishing", "Риболовля" },
	}
	for i, t in ipairs(TABS) do tab(t[1], t[2], 12 + (i - 1) * 86) end

	local refresh = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	refresh:SetSize(90, 22)
	refresh:SetPoint("TOPRIGHT", -12, -30)
	refresh:SetScript("OnClick", ns.Refresh)
	f.refreshButton = refresh

	-- UA / EN switch, left of the close button
	local lang = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	lang:SetSize(38, 18)
	lang:SetPoint("TOPRIGHT", -28, -3)
	lang:SetScript("OnClick", function() ns.SetLanguage(ns.Lang() == "en" and "uk" or "en") end)
	f.langButton = lang

	-- "?" opens the guide
	local help = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	help:SetSize(22, 18)
	help:SetPoint("RIGHT", lang, "LEFT", -4, 0)
	help:SetText("?")
	help:SetScript("OnClick", function() ns.ShowGuide() end)

	local scroll = CreateFrame("ScrollFrame", "WhatToDoScroll", f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 10, -58)
	scroll:SetPoint("BOTTOMRIGHT", -32, 30)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(680, 1)
	scroll:SetScrollChild(content)
	scroll:HookScript("OnSizeChanged", function(_, w) content:SetWidth(w) end)
	f.content = content

	f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.empty:SetPoint("CENTER", 0, -20)
	f.empty:SetWidth(640)

	f.status = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.status:SetPoint("BOTTOMLEFT", 14, 10)
	f.status:SetPoint("RIGHT", f, "RIGHT", -214, 0)
	f.status:SetJustifyH("LEFT")
	f.status:SetWordWrap(false)

	local share = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	share:SetSize(170, 20)
	share:SetPoint("BOTTOMRIGHT", -12, 6)
	share:SetScript("OnClick", function() ns.ShareWithTarget() end)
	share:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(T("Поділитися даними з ціллю"))
		GameTooltip:AddLine(T("Ціль: гравець з вашої групи, поруч, із сумісною версією WhatToDo. Він має підтвердити прийом."), 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	share:SetScript("OnLeave", function() GameTooltip:Hide() end)
	f.shareButton = share

	-- "?" next to it: how sharing works
	local shareHelp = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	shareHelp:SetSize(20, 20)
	shareHelp:SetPoint("RIGHT", share, "LEFT", -3, 0)
	shareHelp:SetText("?")
	shareHelp:SetScript("OnClick", function() ns.ShowGuide("share") end)
	shareHelp:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(T("Як ділитися даними"))
		GameTooltip:AddLine(T("1. Друг у вашій групі, поруч, із сумісною версією WhatToDo."), 0.8, 0.8, 0.8, true)
		GameTooltip:AddLine(T("2. Візьміть його в таргет і натисніть \"Поділитися з ціллю\"."), 0.8, 0.8, 0.8, true)
		GameTooltip:AddLine(T("3. Він підтверджує прийом у вікні, що з'явиться."), 0.8, 0.8, 0.8, true)
		GameTooltip:AddLine(T("Клік - докладна інструкція"), 0.4, 0.8, 1, true)
		GameTooltip:Show()
	end)
	shareHelp:SetScript("OnLeave", function() GameTooltip:Hide() end)

	f:SetScript("OnShow", ns.Refresh)
	frame = f
	ns.ApplyLanguage()
	f:Hide()
	frame = f
end

-- Texts set once at creation, re-set for the current language.
function ns.ApplyLanguage()
	if frame then
		frame.titleText:SetText(T("WhatToDo - найвигідніше за годину"))
		for _, b in pairs(frame.tabs) do b:SetText(T(b.label)) end
		frame.refreshButton:SetText(T("Оновити"))
		frame.shareButton:SetText(T("Поділитися з ціллю"))
		frame.langButton:SetText(ns.Lang() == "en" and "UA" or "EN") -- the language a click switches to
	end
	if ns.RefreshGuide then ns.RefreshGuide() end
	ns.Refresh()
end

-- Just the status line (share progress), without rebuilding the list.
function ns.RefreshStatus()
	if frame and frame:IsShown() then frame.status:SetText(statusText(lastTotal)) end
end

function ns.SetLanguage(lang)
	WhatToDoDB.settings.lang = (lang == "en") and "en" or "uk"
	ns.ApplyLanguage()
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
	results = "скільки рядків показувати в кожній секції",
	corrections = "1 - коригувати прогноз за фактичними продажами/купівлями/часом крафту, 0 - ні",
	essences = "1 - рахувати об'єднання есенцій (без професії), 0 - ні",
}

local function printTop(n)
	for _, kind in ipairs(SECTION_ORDER) do
		local list = ns.Rank(kind)
		if not (#list == 0 and SECTION[kind].hideEmpty) then print("|cffffd100" .. T(SECTION[kind].title) .. "|r") end
		if #list == 0 and not SECTION[kind].hideEmpty then print(T("  нічого вигідного")) end
		for i = 1, math.min(n, #list) do
			local a = list[i]
			print(string.format(T("  %d. %s - %s/год"), i, a.title, ns.Coin(a.perHour)))
		end
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
			ns.Out(T("налаштування (/wtd set <назва> <число>):"))
			for k, help in pairs(SETTING_HELP) do print(string.format("  %s = %s - %s", k, tostring(ns.Setting(k)), T(help))) end
		end
	elseif cmd == "reset" then
		WhatToDoDB.settings = {}
		ns.Out(T("налаштування скинуто."))
		ns.Refresh()
	elseif cmd == "minimap" then
		WhatToDoDB.settings.minimapHide = (ns.Setting("minimapHide") == 1) and 0 or 1
		ns.UpdateMinimapButton()
		ns.Out(ns.Setting("minimapHide") == 1 and T("кнопку біля мінікарти сховано (/wtd minimap - повернути).") or T("кнопку біля мінікарти показано."))
	elseif cmd == "check" and rest ~= "" then
		ns.Out(T("чому пропонується чи ні: ") .. rest)
		ns.Explain(rest)
	elseif cmd == "debug" then
		local function has(x) return x and T("так") or T("ні") end
		ns.Out(T("діагностика:"))
		print(T("  навички: C_SkillInfo ") .. has(C_SkillInfo and C_SkillInfo.GetSkillLineInfo) .. T(", старий API ") .. has(GetSkillLineInfo))
		print(T("  рецепти: C_TradeSkillUI ") .. has(C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs) .. T(", старий API ") .. has(GetTradeSkillLine))
		local rows, api = ns.SkillLines()
		print(string.format(T("  рядків навичок: %s (%s)"), rows and #rows or T("немає"), api or "-"))
		print(T("  персонажі: ") .. ns.KnownCharsText())
		local recipes = ns.RecipeCount()
		print(string.format(T("  записаних рецептів: %d"), recipes))
		local ls = ns.lastScan
		if ls then
			print(string.format(T("  останнє читання вікна професії: %s"), ls.profession and string.format(T("%s через %s, %d рецептів (+%d нових)"), ls.profession, ls.api, ls.seen or 0, ls.added or 0) or ls.result))
		else
			print(T("  вікно професії в цій сесії не відкривалось"))
		end
		print("  Auctionator: " .. has(ns.HasAuctionator()) .. ", Yield: " .. has(ns.HasYield()))
		local seen = 0
		for _ in pairs(WhatToDoDB.priceSeen or {}) do seen = seen + 1 end
		print(string.format(T("  точний час цін: перехоплення %s, записано предметів: %d"), has(ns.PriceHookActive()), seen))
	elseif cmd == "lang" then
		if rest == "en" or rest == "uk" or rest == "ua" then
			ns.SetLanguage(rest == "en" and "en" or "uk")
			ns.Out(ns.Lang() == "en" and "language: English" or "мова: українська")
		else
			ns.Out("/wtd lang en | /wtd lang uk")
		end
	elseif cmd == "results" then
		ns.ResultsReport()
	elseif cmd == "guide" then
		ns.ShowGuide()
	elseif cmd == "share" then
		ns.ShareWithTarget()
	elseif cmd == "shared" then
		if rest:match("^clear") then
			ns.ForgetShared(rest:match("^clear%s+(%S+)"))
			ns.Out(T("отримані дані забуто."))
		else
			ns.Out(T("дані, якими з вами поділились:"))
			ns.SharedReport()
		end
	elseif cmd == "version" then
		ns.Out(T("версія ") .. ns.VERSION .. string.format(T(", формат даних для обміну: %d"), ns.SHARE_FORMAT or 0) .. (ns.UpdateNotice and ns.UpdateNotice() and (", " .. ns.UpdateNotice()) or T(", новішої у друзів поки не бачили")))
	elseif cmd == "stats" then
		ns.LedgerReport()
	elseif cmd == "ledger" and rest == "reset" then
		WhatToDoDB.ledger = nil
		ns.Out(T("журнал фактичних результатів очищено."))
		ns.Refresh()
	elseif cmd == "forget" then
		WhatToDoDB.recipes[ns.CharKey()] = nil
		WhatToDoDB.chars[ns.CharKey()] = nil
		ns.Out(T("рецепти й професії цього персонажа забуто; вони запишуться знову з вікна навичок і професій."))
	else
		ns.Out(T("/wtd - вікно, /wtd top [n] - топ у чат, /wtd set - налаштування, /wtd check <предмет> - чому (не) пропонується, /wtd debug, /wtd version, /wtd lang en|uk - мова, /wtd minimap - сховати/показати кнопку, /wtd stats - факт продажів, /wtd results - результати партій і сесій, /wtd share - поділитися з ціллю, /wtd shared [clear [нік]] - отримані дані, /wtd guide - інструкція, /wtd reset, /wtd ledger reset, /wtd forget - забути рецепти персонажа"))
	end
end

