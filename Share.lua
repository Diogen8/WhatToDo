-- Sharing data with one player, on request, like VuhDo's profile sharing:
--   the sender targets a player who is in their group, nearby and runs the same WhatToDo version, and clicks
--   "Share data" (window, game options panel, /wtd share). The receiver sees a popup and must accept.
-- What's shared (your own data only, never what friends shared with you):
--   ledger sales / buys / craft timings, exact AH prices scanned in the last 24 h for items the suggestions use,
--   and your Yield farm spots (seconds, coin, counts, loot per category).
-- The receiver keeps it apart, in WhatToDoDB.shared[sender] (a new share from the same player replaces the old);
-- Ledger.lua weighs friends' sales at half, Prices.lua uses a friend's price only when it's fresher, Farm.lua
-- adds friends' spots.
--
-- Protocol (hidden addon whispers, prefix "WhatToDoShr"):
--   sender -> PING            receiver -> PONG:<version>
--   sender -> OFFER:<version>:<chunks>:<bytes>:<summary>
--   receiver (popup) -> ACCEPT | DECLINE
--   sender -> D:<i>:<chunk> ... END:<checksum>
--   receiver -> DONE | FAIL:<reason>
-- The payload is a length-prefixed serialization decoded by a parser (never loadstring), then checked against
-- limits before anything is stored.
local _, ns = ...
local T = function(s) return ns.T(s) end

local PREFIX = "WhatToDoShr"
local CHUNK = 230              -- payload characters per message (the limit is 255 with the header)
local MAX_BYTES = 150000       -- refuse anything bigger
local SEND_INTERVAL = 0.12     -- seconds between chunks; throttled sends are retried
local PING_TIMEOUT = 5
local OFFER_TIMEOUT = 65
local IDLE_TIMEOUT = 30        -- receiver gives up when no chunk arrives for this long
local PRICE_HOURS = 24         -- only prices scanned this recently are shared
local SPOT_ITEMS = 25          -- most-looted items per spot category that are shared

local outgoing                 -- { target, phase, chunks, index, payloadSummary, failures }
local incoming                 -- { from, n, bytes, parts, got, last }

---------------------------------------------------------------------------
-- Serialization: i<int>; f<float>; s<len>:<bytes>; T; F; { key value ... }
---------------------------------------------------------------------------

local function encode(v, out)
	local t = type(v)
	if t == "number" then
		if v == math.floor(v) and math.abs(v) < 2 ^ 52 then
			out[#out + 1] = "i" .. string.format("%d", v) .. ";"
		else
			out[#out + 1] = "f" .. string.format("%.10g", v) .. ";"
		end
	elseif t == "string" then
		out[#out + 1] = "s" .. #v .. ":" .. v
	elseif t == "boolean" then
		out[#out + 1] = v and "T" or "F"
	elseif t == "table" then
		out[#out + 1] = "{"
		for k, val in pairs(v) do
			local kt, vt = type(k), type(val)
			if (kt == "string" or kt == "number") and (vt == "table" or vt == "string" or vt == "number" or vt == "boolean") then
				encode(k, out)
				encode(val, out)
			end
		end
		out[#out + 1] = "}"
	end
end

local function serialize(v)
	local out = {}
	encode(v, out)
	-- "|" starts escape codes in WoW text: keep it (and the escape char) out of the messages
	return (table.concat(out):gsub("~", "~t"):gsub("|", "~p"))
end

local MAX_ENTRIES, MAX_DEPTH, MAX_STRING = 60000, 8, 200

local function deserialize(text)
	local str = text:gsub("~([tp])", { t = "~", p = "|" })
	local pos, depth, entries = 1, 0, 0
	local function value()
		local c = str:sub(pos, pos)
		if c == "i" or c == "f" then
			local e = str:find(";", pos, true)
			if not e then error("number") end
			local n = tonumber(str:sub(pos + 1, e - 1))
			if not n or n ~= n then error("number") end
			pos = e + 1
			return n
		elseif c == "s" then
			local colon = str:find(":", pos, true)
			local len = colon and tonumber(str:sub(pos + 1, colon - 1))
			if not len or len < 0 or len > MAX_STRING then error("string") end
			local s = str:sub(colon + 1, colon + len)
			if #s ~= len then error("string") end
			pos = colon + len + 1
			return s
		elseif c == "T" then
			pos = pos + 1
			return true
		elseif c == "F" then
			pos = pos + 1
			return false
		elseif c == "{" then
			depth = depth + 1
			if depth > MAX_DEPTH then error("depth") end
			pos = pos + 1
			local t = {}
			while str:sub(pos, pos) ~= "}" do
				if pos > #str then error("end") end
				local k = value()
				if type(k) ~= "string" and type(k) ~= "number" then error("key") end
				t[k] = value()
				entries = entries + 1
				if entries > MAX_ENTRIES then error("size") end
			end
			pos = pos + 1
			depth = depth - 1
			return t
		end
		error("tag")
	end
	local ok, result = pcall(value)
	if ok and pos == #str + 1 and type(result) == "table" then return result end
end

local function checksum(s)
	local sum = 0
	for i = 1, #s do sum = (sum * 31 + s:byte(i)) % 16777213 end
	return sum
end

---------------------------------------------------------------------------
-- Building the payload (your own data only) and checking a received one
---------------------------------------------------------------------------

local SALE_FIELDS = { "units", "events", "net", "expired", "expiredEvents", "expNet", "expFor" }
local BUY_FIELDS = { "units", "events", "paid", "expected", "paidFor" }
local CRAFT_FIELDS = { "crafts", "units", "seconds", "gaps" }
local CATS = { farm = true, mining = true, herbalism = true, fishing = true, skinning = true }

local function pick(r, fields)
	local out = {}
	for _, f in ipairs(fields) do out[f] = tonumber(r[f]) or 0 end
	return out
end

local function count(t)
	local n = 0
	for _ in pairs(t or {}) do n = n + 1 end
	return n
end

local function buildPayload()
	local l = (ns.Ledger and ns.Ledger()) or { sales = {}, buys = {}, crafts = {} }
	local p = { v = 1, realm = GetRealmName(), t = time(), sales = {}, buys = {}, crafts = {}, prices = {}, spots = {} }
	for name, r in pairs(l.sales or {}) do p.sales[name] = pick(r, SALE_FIELDS) end
	for name, r in pairs(l.buys or {}) do p.buys[name] = pick(r, BUY_FIELDS) end
	for id, r in pairs(l.crafts or {}) do p.crafts[id] = pick(r, CRAFT_FIELDS) end

	-- items whose prices matter: everything the recipes, the catalog and the farm spots use
	local ids = {}
	local function want(id) if type(id) == "number" then ids[id] = true end end
	for _, entry in ipairs(ns.AllRecipes()) do
		want(entry.recipe.product)
		for _, rg in ipairs(entry.recipe.reagents) do want(rg[1]) end
	end
	for _, r in ipairs(ns.CATALOG or {}) do
		want(r.product)
		for _, rg in ipairs(r.reagents) do want(rg[1]) end
	end

	local spots, db = ns.CollectSpots(false)
	for _, s in pairs(spots) do
		if s.seconds >= 60 then
			local entry = { m = s.mapID, z = s.subzone, zn = ns.SpotZoneName(db, s), s = math.floor(s.seconds + 0.5), c = {} }
			for cat, c in pairs(s.cats) do
				local items = {}
				for id, n in pairs(c.items) do items[#items + 1] = { id, n } end
				table.sort(items, function(a, b) return a[2] > b[2] end)
				local top = {}
				for i = 1, math.min(SPOT_ITEMS, #items) do
					top[items[i][1]] = items[i][2]
					want(items[i][1])
				end
				entry.c[cat] = { mo = c.money, n = c.count, i = top }
			end
			p.spots[#p.spots + 1] = entry
		end
	end

	for id in pairs(ids) do
		local snap = ns.OwnPriceSnapshot(id, PRICE_HOURS)
		if snap then p.prices[id] = snap end
	end
	local summary = string.format("%d/%d/%d/%d", count(p.sales), count(p.prices), #p.spots, count(p.crafts))
	return p, summary
end

local function num(x, lo, hi)
	x = tonumber(x)
	if not x or x ~= x or x < lo or x > hi then return nil end
	return x
end

local function str(x, maxLen)
	if type(x) ~= "string" or #x == 0 or #x > maxLen then return nil end
	return x
end

local function cleanRecord(r, fields)
	if type(r) ~= "table" then return nil end
	local out = {}
	for _, f in ipairs(fields) do
		local v = num(r[f] or 0, 0, 1e12)
		if not v then return nil end
		out[f] = v
	end
	return out
end

-- A received payload, checked field by field; nil plus a reason when it doesn't hold up.
local function sanitize(p)
	if type(p) ~= "table" or p.v ~= 1 then return nil, "format" end
	if p.realm ~= GetRealmName() then return nil, "realm" end
	local now = time()
	local out = { received = now, sales = {}, buys = {}, crafts = {}, prices = {}, spots = {} }
	for name, r in pairs(type(p.sales) == "table" and p.sales or {}) do
		local key, rec = str(name, 100), cleanRecord(r, SALE_FIELDS)
		if key and rec then out.sales[key] = rec end
	end
	for name, r in pairs(type(p.buys) == "table" and p.buys or {}) do
		local key, rec = str(name, 100), cleanRecord(r, BUY_FIELDS)
		if key and rec then out.buys[key] = rec end
	end
	for id, r in pairs(type(p.crafts) == "table" and p.crafts or {}) do
		local key, rec = num(id, 1, 1e7), cleanRecord(r, CRAFT_FIELDS)
		if key and rec and rec.gaps > 0 and rec.seconds / rec.gaps <= 600 then out.crafts[key] = rec end
	end
	for id, e in pairs(type(p.prices) == "table" and p.prices or {}) do
		local key = num(id, 1, 1e7)
		if key and type(e) == "table" then
			local price, t = num(e.p, 1, 1e10), num(e.t, now - (PRICE_HOURS + 12) * 3600, now + 600)
			if price and t then out.prices[key] = { p = price, t = math.min(t, now), a = num(e.a, 0, 1e6) } end
		end
	end
	if type(p.spots) == "table" then
		for i = 1, math.min(#p.spots, 3000) do
			local sp = p.spots[i]
			if type(sp) == "table" then
				local m, z, s = num(sp.m, -1e7, 1e7), type(sp.z) == "string" and #sp.z <= 100 and sp.z, num(sp.s, 1, 1e8)
				if m and z and s then
					local entry = { m = m, z = z, zn = str(sp.zn, 100), s = s, c = {} }
					for cat, c in pairs(type(sp.c) == "table" and sp.c or {}) do
						if CATS[cat] and type(c) == "table" then
							local items = {}
							for id, n in pairs(type(c.i) == "table" and c.i or {}) do
								local key, v = num(id, 1, 1e7), num(n, 0, 1e7)
								if key and v then items[key] = v end
							end
							entry.c[cat] = { mo = num(c.mo or 0, 0, 1e12) or 0, n = num(c.n or 0, 0, 1e7) or 0, i = items }
						end
					end
					out.spots[#out.spots + 1] = entry
				end
			end
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Messaging
---------------------------------------------------------------------------

local function short(name)
	return Ambiguate and Ambiguate(name, "short") or (name:match("^([^-]+)") or name)
end

local function sendTo(target, msg)
	if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return false end
	local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, "WHISPER", target)
	if not ok then return false end
	return res == nil or res == true or res == 0 -- older clients: nil/boolean; newer: Enum result, 0 = success
end

local function status(text)
	ns.shareStatus = text
	if ns.RefreshStatus then ns.RefreshStatus() end
end

local function inGroupWith(unitOrName)
	return (UnitInParty and UnitInParty(unitOrName)) or (UnitInRaid and UnitInRaid(unitOrName)) or false
end

local function nearby(unit)
	if CheckInteractDistance then
		local ok, close = pcall(CheckInteractDistance, unit, 4) -- ~28 yards
		if ok and close ~= nil then return close and true or false end
	end
	if UnitInRange then
		local inRange, checked = UnitInRange(unit)
		if checked then return inRange and true or false end
	end
	return true -- the client can't tell: don't block on it
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------

local function finishOutgoing(text)
	if text then ns.Out(text) end
	outgoing = nil
	status(nil)
end

local function sendChunks()
	local o = outgoing
	if not o or o.phase ~= "sending" then return end
	if o.index > #o.chunks then
		if sendTo(o.target, "END:" .. o.sum) then
			o.phase = "waiting"
			status(string.format(T("надіслано %s, чекаю підтвердження"), short(o.target)))
			C_Timer.After(OFFER_TIMEOUT, function()
				if outgoing == o and o.phase == "waiting" then finishOutgoing(T("одержувач не підтвердив отримання.")) end
			end)
		else
			C_Timer.After(1, sendChunks)
		end
		return
	end
	if sendTo(o.target, "D:" .. o.index .. ":" .. o.chunks[o.index]) then
		o.index, o.failures = o.index + 1, 0
		if o.index % 10 == 0 or o.index > #o.chunks then
			status(string.format(T("надсилаю %s: %d%%"), short(o.target), math.floor((o.index - 1) / #o.chunks * 100)))
		end
		C_Timer.After(SEND_INTERVAL, sendChunks)
	else
		o.failures = o.failures + 1
		if o.failures > 60 then return finishOutgoing(T("передачу перервано: гра не пропускає повідомлення.")) end
		C_Timer.After(1, sendChunks) -- throttled: wait and retry the same chunk
	end
end

-- The "Share data" button: checks the target and starts with a version ping.
function ns.ShareWithTarget()
	if outgoing then return ns.Out(T("вже йде передача - зачекайте.")) end
	if InCombatLockdown and InCombatLockdown() then return ns.Out(T("у бою передача недоступна.")) end
	if not (UnitExists and UnitExists("target")) or not UnitIsPlayer("target") or UnitIsUnit("target", "player") then
		return ns.Out(T("візьміть у таргет гравця, з яким хочете поділитися."))
	end
	if not inGroupWith("target") then return ns.Out(T("ціль має бути у вашій групі або рейді.")) end
	if not nearby("target") then return ns.Out(T("ціль занадто далеко - підійдіть ближче.")) end
	local target = GetUnitName and GetUnitName("target", true) or UnitName("target")
	outgoing = { target = target, phase = "ping", failures = 0 }
	status(string.format(T("перевіряю версію в %s..."), short(target)))
	sendTo(target, "PING")
	local o = outgoing
	C_Timer.After(PING_TIMEOUT, function()
		if outgoing == o and o.phase == "ping" then
			finishOutgoing(string.format(T("%s не відповідає - у нього не встановлений або вимкнений WhatToDo."), short(target)))
		end
	end)
end

local function onPong(sender, version)
	local o = outgoing
	if not o or o.phase ~= "ping" or short(sender) ~= short(o.target) then return end
	if version ~= ns.VERSION then
		return finishOutgoing(string.format(T("у %s версія %s, у вас %s - потрібна однакова версія."), short(sender), version, ns.VERSION))
	end
	local payload, summary = buildPayload()
	local data = serialize(payload)
	if #data > MAX_BYTES then return finishOutgoing(T("забагато даних для передачі.")) end
	o.chunks = {}
	for i = 1, #data, CHUNK do o.chunks[#o.chunks + 1] = data:sub(i, i + CHUNK - 1) end
	o.sum, o.index = checksum(data), 1
	o.phase = "offer"
	sendTo(o.target, string.format("OFFER:%s:%d:%d:%s", ns.VERSION, #o.chunks, #data, summary))
	status(string.format(T("чекаю, поки %s прийме дані..."), short(o.target)))
	C_Timer.After(OFFER_TIMEOUT, function()
		if outgoing == o and o.phase == "offer" then finishOutgoing(string.format(T("%s не відповів на пропозицію."), short(o.target))) end
	end)
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------

local function summaryText(summary)
	local sales, prices, spots, crafts = (summary or ""):match("^(%d+)/(%d+)/(%d+)/(%d+)$")
	return string.format(T("продажі: %s, ціни: %s, місця фарму: %s, крафти: %s"), sales or "?", prices or "?", spots or "?", crafts or "?")
end

local function respond(answer)
	local i = incoming
	if not i or i.phase ~= "asking" then return end
	if answer then
		i.phase, i.last = "receiving", GetTime()
		sendTo(i.from, "ACCEPT")
		status(string.format(T("отримую дані від %s..."), short(i.from)))
		local function watch()
			if incoming ~= i then return end
			if GetTime() - i.last > IDLE_TIMEOUT then
				incoming = nil
				status(nil)
				return ns.Out(string.format(T("передачу від %s перервано: дані перестали надходити."), short(i.from)))
			end
			C_Timer.After(5, watch)
		end
		C_Timer.After(5, watch)
	else
		sendTo(i.from, "DECLINE")
		incoming = nil
	end
end

-- Only our own key is added: assigning the StaticPopupDialogs global itself (even to the same table) taints it,
-- and the game then blocks protected actions in every Blizzard popup, blaming WhatToDo.
StaticPopupDialogs["WHATTODO_SHARE_OFFER"] = {
	text = "%s",
	button1 = "OK",
	button2 = "Cancel",
	OnAccept = function() respond(true) end,
	OnCancel = function() respond(false) end,
	timeout = 60,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

local function onOffer(sender, version, n, bytes, summary)
	if incoming then return sendTo(sender, "DECLINE") end
	if version ~= ns.VERSION then return sendTo(sender, "FAIL:version") end
	if not inGroupWith(short(sender)) then return sendTo(sender, "FAIL:group") end
	n, bytes = tonumber(n), tonumber(bytes)
	if not n or not bytes or bytes > MAX_BYTES or n > math.ceil(MAX_BYTES / CHUNK) then return sendTo(sender, "FAIL:size") end
	incoming = { from = sender, n = n, bytes = bytes, parts = {}, got = 0, phase = "asking" }
	local dialog = StaticPopupDialogs["WHATTODO_SHARE_OFFER"]
	dialog.button1, dialog.button2 = T("Прийняти"), T("Відхилити")
	local text = string.format(T("%s хоче поділитися даними WhatToDo (%s, %.0f КБ).\n\nВаші власні дані не зміняться: отримане зберігається окремо.\nПрийняти?"),
		short(sender), summaryText(summary), bytes / 1024)
	if StaticPopup_Show then
		StaticPopup_Show("WHATTODO_SHARE_OFFER", text)
	else
		respond(false)
	end
end

local function onEnd(sender, sum)
	local i = incoming
	if not i or i.phase ~= "receiving" or sender ~= i.from then return end
	incoming = nil
	status(nil)
	if i.got ~= i.n then
		sendTo(sender, "FAIL:missing")
		return ns.Out(string.format(T("дані від %s прийшли не повністю - спробуйте ще раз."), short(sender)))
	end
	local data = table.concat(i.parts)
	if #data ~= i.bytes or checksum(data) ~= tonumber(sum) then
		sendTo(sender, "FAIL:checksum")
		return ns.Out(string.format(T("дані від %s пошкоджені - спробуйте ще раз."), short(sender)))
	end
	local clean, reason = sanitize(deserialize(data))
	if not clean then
		sendTo(sender, "FAIL:" .. (reason or "format"))
		return ns.Out(string.format(T("дані від %s відхилено (%s)."), short(sender), reason == "realm" and T("інший сервер") or T("неправильний формат")))
	end
	WhatToDoDB.shared = WhatToDoDB.shared or {}
	WhatToDoDB.shared[short(sender)] = clean
	sendTo(sender, "DONE")
	ns.Out(string.format(T("отримано дані від %s: %s."), short(sender),
		summaryText(string.format("%d/%d/%d/%d", count(clean.sales), count(clean.prices), #clean.spots, count(clean.crafts)))))
	if ns.Refresh then ns.Refresh() end
end

---------------------------------------------------------------------------
-- Dispatch
---------------------------------------------------------------------------

local FAIL_TEXT = {
	version = "у одержувача інша версія WhatToDo.",
	group = "одержувач не бачить вас у групі.",
	size = "одержувач відхилив: забагато даних.",
	missing = "дані дійшли не повністю.",
	checksum = "дані пошкодилися в дорозі.",
	realm = "одержувач на іншому сервері.",
	format = "одержувач не зміг прочитати дані.",
}

local function onMessage(text, sender)
	if text == "PING" then
		sendTo(sender, "PONG:" .. ns.VERSION)
		return
	end
	local version = text:match("^PONG:(.+)$")
	if version then return onPong(sender, version) end
	local v, n, bytes, summary = text:match("^OFFER:([^:]+):(%d+):(%d+):(.*)$")
	if v then return onOffer(sender, v, n, bytes, summary) end
	local index, chunk = text:match("^D:(%d+):(.*)$")
	if index then
		local i = incoming
		if i and i.phase == "receiving" and sender == i.from then
			index = tonumber(index)
			if index and index >= 1 and index <= i.n and not i.parts[index] then
				i.parts[index], i.got, i.last = chunk, i.got + 1, GetTime()
				if i.got % 10 == 0 then status(string.format(T("отримую дані від %s: %d%%"), short(sender), math.floor(i.got / i.n * 100))) end
			end
		end
		return
	end
	local sum = text:match("^END:(%d+)$")
	if sum then return onEnd(sender, sum) end

	-- answers to our offer
	local o = outgoing
	if not o or short(sender) ~= short(o.target) then return end
	if text == "ACCEPT" and o.phase == "offer" then
		o.phase = "sending"
		sendChunks()
	elseif text == "DECLINE" and (o.phase == "offer" or o.phase == "ping") then
		finishOutgoing(string.format(T("%s відхилив передачу."), short(sender)))
	elseif text == "DONE" then
		finishOutgoing(string.format(T("%s отримав ваші дані."), short(sender)))
	else
		local reason = text:match("^FAIL:(.+)$")
		if reason then finishOutgoing(string.format(T("не вдалося: %s"), T(FAIL_TEXT[reason] or reason))) end
	end
end

local f = CreateFrame("Frame")
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
pcall(f.RegisterEvent, f, "CHAT_MSG_ADDON")
f:SetScript("OnEvent", function(_, _, prefix, text, channel, sender)
	if prefix == PREFIX and channel == "WHISPER" and type(text) == "string" and type(sender) == "string" then
		onMessage(text, sender)
	end
end)

---------------------------------------------------------------------------
-- Received data: list and forget
---------------------------------------------------------------------------

function ns.SharedReport()
	local any = false
	for name, data in pairs((WhatToDoDB and WhatToDoDB.shared) or {}) do
		any = true
		print(string.format(T("  %s: %s, отримано %s тому"), name,
			summaryText(string.format("%d/%d/%d/%d", count(data.sales), count(data.prices), #(data.spots or {}), count(data.crafts))),
			ns.AgeText((time() - (data.received or time())) / 3600)))
	end
	if not any then print(T("  ще ніхто не ділився з вами даними.")) end
end

function ns.ForgetShared(name)
	if not (WhatToDoDB and WhatToDoDB.shared) then return end
	if name and name ~= "" then
		for key in pairs(WhatToDoDB.shared) do
			if key:lower() == name:lower() then WhatToDoDB.shared[key] = nil end
		end
	else
		WhatToDoDB.shared = {}
	end
	if ns.Refresh then ns.Refresh() end
end

---------------------------------------------------------------------------
-- The addon's page in the game's options (Esc > Options > AddOns)
---------------------------------------------------------------------------

local function registerOptions()
	local panel = CreateFrame("Frame")
	panel.name = "WhatToDo"
	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	local note = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	note:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
	note:SetWidth(560)
	note:SetJustifyH("LEFT")
	local share = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	share:SetSize(240, 26)
	share:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -16)
	share:SetScript("OnClick", function() ns.ShareWithTarget() end)
	local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	open:SetSize(240, 26)
	open:SetPoint("TOPLEFT", share, "BOTTOMLEFT", 0, -8)
	open:SetScript("OnClick", function() ns.Toggle() end)
	local guide = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	guide:SetSize(240, 26)
	guide:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -8)
	guide:SetScript("OnClick", function() ns.ShowGuide() end)
	local lang = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	lang:SetSize(240, 26)
	lang:SetPoint("TOPLEFT", guide, "BOTTOMLEFT", 0, -8)
	local function texts()
		title:SetText("WhatToDo " .. (ns.VERSION or ""))
		note:SetText(T("Поділитися даними: візьміть у таргет гравця з вашої групи, який стоїть поруч і має ту саму версію WhatToDo. Він має підтвердити прийом."))
		share:SetText(T("Поділитися даними з ціллю"))
		open:SetText(T("Відкрити вікно WhatToDo"))
		guide:SetText(T("Інструкція"))
		lang:SetText(ns.Lang() == "en" and "Українська" or "English")
	end
	lang:SetScript("OnClick", function()
		ns.SetLanguage(ns.Lang() == "en" and "uk" or "en")
		texts()
	end)
	panel:SetScript("OnShow", texts)
	texts()
	if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
		local category = Settings.RegisterCanvasLayoutCategory(panel, "WhatToDo")
		Settings.RegisterAddOnCategory(category)
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(panel)
	end
end

local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", function() pcall(registerOptions) end)

-- for tests
ns._share = { serialize = serialize, deserialize = deserialize, sanitize = sanitize, buildPayload = buildPayload, checksum = checksum }
