-- Update notice: copies of WhatToDo tell each other their version through hidden addon messages (guild,
-- party/raid, and online friends by whisper), like DBM and BigWigs do. Addons can't reach the internet, so this
-- only says that someone has a newer version; getting it is up to the updater (git) or the player.
--   "V:<version>" - an announcement. A receiver with an older copy shows a notice; one with a newer copy
--                   answers by whisper so the sender learns about it too.
local ADDON_NAME, ns = ...
local T = function(s) return ns.T(s) end

local PREFIX = "WhatToDoVer"
local THROTTLE = 60     -- seconds between announcements to the same channel / friend
local lastSent = {}     -- channel or friend name -> GetTime()
local answered = {}     -- sender -> true (answered with our newer version this session)
ns.newestSeen = nil     -- { version, from } when someone has a newer copy than ours

local function metadata(field)
	local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	return get and get(ADDON_NAME, field)
end

ns.VERSION = metadata("Version") or "0"

-- "0.10.2" -> {0, 10, 2}; compares part by part. Returns -1, 0 or 1.
local function compare(a, b)
	local pa, pb = {}, {}
	for n in tostring(a):gmatch("%d+") do pa[#pa + 1] = tonumber(n) end
	for n in tostring(b):gmatch("%d+") do pb[#pb + 1] = tonumber(n) end
	for i = 1, math.max(#pa, #pb) do
		local x, y = pa[i] or 0, pb[i] or 0
		if x ~= y then return x < y and -1 or 1 end
	end
	return 0
end
ns.CompareVersions = compare

local function canSend()
	if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return false end
	if InCombatLockdown and InCombatLockdown() then return false end
	return true
end

local function send(channel, target)
	if not canSend() then return end
	local key = target or channel
	local now = GetTime()
	if lastSent[key] and now - lastSent[key] < THROTTLE then return end
	lastSent[key] = now
	pcall(C_ChatInfo.SendAddonMessage, PREFIX, "V:" .. ns.VERSION, channel, target)
end

local function onlineFriends()
	local names = {}
	if C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex then
		for i = 1, C_FriendList.GetNumFriends() or 0 do
			local info = C_FriendList.GetFriendInfoByIndex(i)
			if info and info.connected and info.name then names[#names + 1] = info.name end
		end
	end
	return names
end

local function announce()
	if IsInGuild and IsInGuild() then send("GUILD") end
	if IsInRaid and IsInRaid() then
		send((IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE)) and "INSTANCE_CHAT" or "RAID")
	elseif IsInGroup and IsInGroup() then
		send((LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE)) and "INSTANCE_CHAT" or "PARTY")
	end
	for _, name in ipairs(onlineFriends()) do send("WHISPER", name) end
end

local function shortName(sender)
	return Ambiguate and Ambiguate(sender, "short") or (sender:match("^([^-]+)") or sender)
end

local function onMessage(text, channel, sender)
	local version = text:match("^V:(.+)$")
	if not version or not sender then return end
	local who = shortName(sender)
	if who == UnitName("player") then return end
	local order = compare(ns.VERSION, version)
	if order < 0 then
		-- theirs is newer
		if not ns.newestSeen or compare(ns.newestSeen.version, version) < 0 then
			ns.newestSeen = { version = version, from = who }
			ns.Out(string.format(T("доступна новіша версія |cff66ff66%s|r (у %s), у вас %s. Оновіть аддон."), version, who, ns.VERSION))
			if ns.Refresh then ns.Refresh() end
		end
	elseif order > 0 and not answered[sender] then
		-- ours is newer: tell them back, once
		answered[sender] = true
		if canSend() then pcall(C_ChatInfo.SendAddonMessage, PREFIX, "V:" .. ns.VERSION, "WHISPER", sender) end
	end
end

local f = CreateFrame("Frame")
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "GUILD_ROSTER_UPDATE", "FRIENDLIST_UPDATE", "CHAT_MSG_ADDON" }) do
	pcall(f.RegisterEvent, f, event)
end
local pending = false
f:SetScript("OnEvent", function(_, event, prefix, text, channel, sender)
	if event == "CHAT_MSG_ADDON" then
		if prefix == PREFIX and type(text) == "string" then onMessage(text, channel, sender) end
		return
	end
	-- announcements are batched a few seconds after login / roster changes
	if pending then return end
	pending = true
	C_Timer.After(event == "PLAYER_ENTERING_WORLD" and 10 or 3, function()
		pending = false
		announce()
	end)
end)

-- One line for the window's status and the minimap tooltip, or nil when up to date.
function ns.UpdateNotice()
	local n = ns.newestSeen
	if n then return string.format(T("є новіша версія %s (у %s)"), n.version, n.from) end
end
