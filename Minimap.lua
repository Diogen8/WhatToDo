-- Minimap button: left click opens the window, right click prints the top picks, drag moves it around the
-- minimap edge. The angle (degrees) and hidden state are saved in WhatToDoDB.settings. Hand-rolled, laid out
-- like LibDBIcon's buttons.
local _, ns = ...

local ICON = "Interface\\Icons\\INV_Misc_Coin_02"
local button

local SECTION_NAMES = {
	{ "craft", "Рекрафт" }, { "learn", "Якщо вивчити" }, { "farm", "Моби" }, { "mining", "Майнінг" },
	{ "herbalism", "Трави" }, { "skinning", "Скінінг" }, { "fishing", "Риболовля" },
}

local function angle() return ns.Setting("minimapAngle") end

local function place()
	if not button then return end
	local a = math.rad(angle())
	local radius = (Minimap:GetWidth() / 2) + 5
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * radius, math.sin(a) * radius)
end

local function dragUpdate()
	local mx, my = Minimap:GetCenter()
	local px, py = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	px, py = px / scale, py / scale
	local atan2 = math.atan2 or math.atan
	WhatToDoDB.settings.minimapAngle = math.floor(math.deg(atan2(py - my, px - mx)) % 360 + 0.5)
	place()
end

local function showTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine("WhatToDo")
	local any = false
	for _, s in ipairs(SECTION_NAMES) do
		local best = ns.Rank(s[1])[1]
		if best then
			any = true
			GameTooltip:AddDoubleLine(s[2] .. ": " .. best.title, ns.Coin(best.perHour) .. "/год", 0.9, 0.9, 0.9, 1, 1, 1)
		end
	end
	if not any then GameTooltip:AddLine("Поки нічого порадити.", 0.7, 0.7, 0.7) end
	local income = ns.Income and ns.Income(7) or 0
	if income > 0 then GameTooltip:AddDoubleLine("Виручка з аукціону, 7 дн.", ns.Coin(income), 0.7, 0.7, 0.7, 1, 1, 1) end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Лівий клік - вікно, правий - топ у чат, тягнути - перемістити", 0.6, 0.6, 0.6, true)
	GameTooltip:Show()
end

local function create()
	local b = CreateFrame("Button", "WhatToDoMinimapButton", Minimap)
	b:SetSize(31, 31)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:RegisterForDrag("LeftButton")
	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetSize(20, 20)
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetPoint("TOPLEFT", 7, -5)
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetSize(17, 17)
	icon:SetTexture(ICON)
	icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
	icon:SetPoint("TOPLEFT", 7, -6)
	local border = b:CreateTexture(nil, "OVERLAY")
	border:SetSize(53, 53)
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetPoint("TOPLEFT")

	b:SetScript("OnClick", function(_, mouse)
		if mouse == "RightButton" then
			SlashCmdList.WHATTODO("top 3")
		else
			ns.Toggle()
		end
	end)
	b:SetScript("OnDragStart", function(self)
		GameTooltip:Hide()
		self:SetScript("OnUpdate", dragUpdate)
	end)
	b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	b:SetScript("OnEnter", showTooltip)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	button = b
end

function ns.UpdateMinimapButton()
	if ns.Setting("minimapHide") == 1 then
		if button then button:Hide() end
		return
	end
	if not button then create() end
	place()
	button:Show()
end

function ns.OnLoad()
	ns.UpdateMinimapButton()
end
