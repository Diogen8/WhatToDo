-- Highlighting a farming spot on the world map (a click on a farming or gathering row):
--   1. the subzone itself: the explored-map overlay that holds the spot, drawn again over the map in yellow;
--   2. the farmed area: a soft ellipse around where you actually looted (centre and spread from WhatToDoDB.spotPos).
-- Both stay while the map shows that zone and go when the map closes or shows another one.
local _, ns = ...

local TILE = 256
local overlay, shownMap

local function canvas()
	return WorldMapFrame and (WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas() or (WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child))
end

local function clear()
	if overlay then
		for _, t in ipairs(overlay.tiles) do t:Hide() end
		overlay.area:Hide()
		overlay:Hide()
	end
	shownMap = nil
end

local function ensure(parent)
	if overlay then
		if overlay:GetParent() ~= parent then overlay:SetParent(parent) end
		return overlay
	end
	overlay = CreateFrame("Frame", nil, parent)
	overlay.tiles = {}
	overlay.area = overlay:CreateTexture(nil, "OVERLAY")
	overlay.area:SetColorTexture(1, 0.85, 0.2, 0.3)
	if overlay.CreateMaskTexture then
		local mask = overlay:CreateMaskTexture() -- a round mask makes the square soft ellipse
		if mask then
			mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
			mask:SetAllPoints(overlay.area)
			overlay.area:AddMaskTexture(mask)
		end
	end
	-- follow the map: another zone or a closed map takes the highlight away
	if WorldMapFrame.OnMapChanged then
		hooksecurefunc(WorldMapFrame, "OnMapChanged", function()
			if shownMap and WorldMapFrame:GetMapID() ~= shownMap then clear() end
		end)
	end
	WorldMapFrame:HookScript("OnHide", clear)
	return overlay
end

-- The explored overlay (in map-art pixels) holding the point; the smallest when several boxes hold it.
local function overlayAt(mapID, px, py)
	if not (C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures) then return nil end
	local best, bestArea
	for _, info in ipairs(C_MapExplorationInfo.GetExploredMapTextures(mapID) or {}) do
		local x0, y0 = info.offsetX, info.offsetY
		if px >= x0 and px <= x0 + info.textureWidth and py >= y0 and py <= y0 + info.textureHeight then
			local area = info.textureWidth * info.textureHeight
			if not bestArea or area < bestArea then best, bestArea = info, area end
		end
	end
	return best
end

local function fileSize(pixels)
	local size = 16
	while size < pixels do size = size * 2 end
	return size
end

local function draw(mapID, p)
	local child = canvas()
	if not child or WorldMapFrame:GetMapID() ~= mapID then return end
	local f = ensure(child)
	for _, t in ipairs(f.tiles) do t:Hide() end
	f:SetAllPoints(child)
	f:SetFrameLevel(child:GetFrameLevel() + 50)
	f:Show()
	shownMap = mapID
	local w, h = child:GetWidth(), child:GetHeight()

	-- 1. the subzone shape
	local layers = C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(mapID)
	local layer = layers and layers[1]
	if layer and layer.layerWidth and layer.layerWidth > 0 then
		local sx, sy = w / layer.layerWidth, h / layer.layerHeight
		local info = overlayAt(mapID, p.x * layer.layerWidth, p.y * layer.layerHeight)
		if info and info.fileDataIDs then
			local wide, tall = math.ceil(info.textureWidth / TILE), math.ceil(info.textureHeight / TILE)
			local n = 0
			for j = 1, tall do
				local ph = (j < tall) and TILE or ((info.textureHeight % TILE == 0) and TILE or info.textureHeight % TILE)
				local fh = (j < tall) and TILE or fileSize(ph)
				for k = 1, wide do
					local pw = (k < wide) and TILE or ((info.textureWidth % TILE == 0) and TILE or info.textureWidth % TILE)
					local fw = (k < wide) and TILE or fileSize(pw)
					local file = info.fileDataIDs[(j - 1) * wide + k]
					if file then
						n = n + 1
						local t = f.tiles[n]
						if not t then
							t = f:CreateTexture(nil, "ARTWORK")
							t:SetBlendMode("ADD")
							t:SetVertexColor(1, 0.8, 0.1, 0.9)
							f.tiles[n] = t
						end
						t:SetTexture(file)
						t:SetTexCoord(0, pw / fw, 0, ph / fh)
						t:SetSize(pw * sx, ph * sy)
						t:ClearAllPoints()
						t:SetPoint("TOPLEFT", f, "TOPLEFT", (info.offsetX + TILE * (k - 1)) * sx, -(info.offsetY + TILE * (j - 1)) * sy)
						t:Show()
					end
				end
			end
		end
	end

	-- 2. the farmed area: 1.5 spreads around the centre, at least 1.5% and at most 15% of the map
	local sdx = math.sqrt(math.max((p.x2 or 0) - p.x * p.x, 0))
	local sdy = math.sqrt(math.max((p.y2 or 0) - p.y * p.y, 0))
	local rx = math.min(math.max(1.5 * sdx, 0.015), 0.15)
	local ry = math.min(math.max(1.5 * sdy, 0.015), 0.15)
	f.area:ClearAllPoints()
	f.area:SetSize(2 * rx * w, 2 * ry * h)
	f.area:SetPoint("CENTER", f, "TOPLEFT", p.x * w, -p.y * h)
	f.area:Show()
end

function ns.HighlightSpot(mapID, p)
	if not WorldMapFrame then return end
	-- a frame later: the map has to switch to the zone and size its canvas first
	C_Timer.After(0, function() pcall(draw, mapID, p) end)
end
