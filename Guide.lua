-- The guide: dependencies (with their live status), what WhatToDo does and how to use it. Shown once on the first
-- login with the addon (WhatToDoDB.guideShown), then from /wtd guide, the "?" button in the window and the
-- game options page. Full texts in Ukrainian and English; the language button switches the whole addon.
-- Only characters the game font has: no bullets, arrows or long dashes.
local _, ns = ...

local H = "|cffffd100" -- heading colour
local E = "|r"

local GUIDE = {
	uk = {
		title = "WhatToDo - інструкція",
		ok = "встановлено",
		missing = "не знайдено",
		close = "Зрозуміло",
		open = "Відкрити WhatToDo",
		switch = "English",
		shareTitle = "WhatToDo - обмін даними",
		share = H .. "ЯК ПОДІЛИТИСЯ" .. E .. [==[

1. Будьте з другом в одній групі або рейді.
2. Підійдіть ближче, до 28 ярдів.
3. Візьміть його в таргет і натисніть "Поділитися з ціллю".
4. У друга з'явиться вікно: він має натиснути "Прийняти" протягом хвилини.
5. Перебіг передачі видно в рядку внизу вікна WhatToDo. Наприкінці обом прийде повідомлення в чат.

]==] .. H .. "УМОВИ" .. E .. [==[

- У обох однакова версія WhatToDo.
- Не в бою.
- Той самий сервер.

]==] .. H .. "ЩО ПЕРЕДАЄТЬСЯ" .. E .. [==[

Лише ваші власні дані, не те, що передали вам інші:
- продажі, повернення та купівлі з аукціону, фактичний час на крафт;
- ціни, які ви сканували за останню добу, тільки для предметів з порад;
- ваші місця фарму та збору з Yield.

]==] .. H .. "ЩО З ЦИМ РОБИТЬ ДРУГ" .. E .. [==[

- Зберігає окремо: його власні дані не змінюються.
- Ваші продажі важать для нього вдвічі менше за його власні.
- Ваша ціна використовується, лише якщо вона свіжіша за його.
- Ваші місця фарму додаються до його і позначаються зірочкою.
- Нова передача від вас замінює попередню.

]==] .. H .. "БЕЗПЕКА" .. E .. [==[

Отримане перевіряється поле за полем і ніколи не виконується як код. Неправильні дані, дані з іншого сервера і завеликий обсяг відхиляються.

]==] .. H .. "КОМАНДИ" .. E .. [==[

/wtd share - поділитися з ціллю
/wtd shared - що вам передали
/wtd shared clear [нік] - забути дані від гравця (без ніка - від усіх)]==],
		body = H .. "ЩО ЦЕ" .. E .. [==[

WhatToDo підказує, чим зараз найвигідніше зайнятися, і сортує варіанти за золотом за годину:
- рекрафт: купити дешеві матеріали на аукціоні, скрафтити, продати;
- фарм мобів і збір: майнінг, трави, скінінг, риболовля.

]==] .. H .. "ЗАЛЕЖНОСТІ" .. E .. [==[

- Auctionator: {AUCTIONATOR}
  Ціни аукціону. Без нього рекрафт не працює, а лут оцінюється лише за цінами вендора.
- Yield: {YIELD}
  Сесії фарму. Звідти WhatToDo бере місця, час і лут для фарму та збору.
Обидва необов'язкові, але без них відповідні секції будуть порожні.

]==] .. H .. "ПЕРШІ КРОКИ" .. E .. [==[

1. Проскануйте аукціон в Auctionator. Ціни, старші за 3 дні, не використовуються.
2. Зайдіть хоч раз кожним персонажем: WhatToDo запам'ятає професії та рівні навичок.
3. Відкрийте вікно кожної професії: запишуться точні рецепти, і клік по рядку відкриватиме рецепт.
4. Фарміть з увімкненим Yield хоча б 10 хвилин на одному місці.
5. Відкрийте вікно: /wtd або кнопка-монета біля мінікарти.

]==] .. H .. "ВІКНО" .. E .. [==[

Вкладки: Усе, Рекрафт, Моби, Майнінг, Трави, Скінінг, Риболовля.
У рядку: золото за годину, коротко деталі, справа довіра до поради. Наведіть мишку, щоб побачити повний розрахунок.
- РЕКРАФТ (АФК): що ваші персонажі можуть скрафтити вже зараз. Клік відкриває рецепт у професії.
- РЕКРАФТ: ЯКЩО ВИВЧИТИ: для персонажів з вільним слотом професії, з потрібним рівнем навички.
- ФАРМ і збір: місця з вашої історії Yield, лут за сьогоднішніми цінами.

]==] .. H .. "ДОВІРА" .. E .. [==[

Довіра = 40% свіжість цін + 60% підтвердження фактом.
- Ціни до 6 годин: 100%, від 6 до 12 годин довіра падає, старші за 12 годин: ненадійні.
- Факт: ваші реальні продажі з пошти та реально отримане золото.
Поки ви цього жодного разу не робили, довіра не вища за 40%.

]==] .. H .. "ФАКТИЧНИЙ РЕЗУЛЬТАТ" .. E .. [==[

Коли ви забираєте пошту з аукціону, WhatToDo записує продажі, повернення та купівлі, а також фактичний час на крафт. За цим він коригує прогнози. Журнал спільний для всіх персонажів акаунта: можна скрафтити на одному, а продати на іншому.

]==] .. H .. "ОБМІН ДАНИМИ" .. E .. [==[

Візьміть у таргет друга з вашої групи (поруч, та сама версія WhatToDo) і натисніть "Поділитися з ціллю". Він має підтвердити прийом. Отримані дані зберігаються окремо, а продажі друзів важать удвічі менше за ваші.

]==] .. H .. "ОНОВЛЕННЯ" .. E .. [==[

Якщо в когось у гільдії, групі чи серед друзів новіша версія WhatToDo, аддон повідомить про це в чаті.

]==] .. H .. "КОМАНДИ" .. E .. [==[

/wtd - вікно
/wtd top [n] - найкращі варіанти в чат
/wtd check <предмет> - чому рецепт пропонується чи ні
/wtd stats - фактичні продажі
/wtd share - поділитися даними з ціллю
/wtd shared [clear [нік]] - отримані дані
/wtd set - налаштування розрахунку
/wtd lang en|uk - мова
/wtd minimap - сховати або показати кнопку біля мінікарти
/wtd guide - ця інструкція
/wtd debug, /wtd version]==],
	},
	en = {
		title = "WhatToDo - guide",
		ok = "installed",
		missing = "not found",
		close = "Got it",
		open = "Open WhatToDo",
		switch = "Українська",
		shareTitle = "WhatToDo - sharing data",
		share = H .. "HOW TO SHARE" .. E .. [==[

1. Be in the same party or raid as your friend.
2. Get close, within 28 yards.
3. Target them and click "Share with target".
4. A window pops up for your friend: they have a minute to click "Accept".
5. The progress shows in the line at the bottom of the WhatToDo window. Both of you get a chat message at the end.

]==] .. H .. "REQUIREMENTS" .. E .. [==[

- Both have the same WhatToDo version.
- Not in combat.
- The same realm.

]==] .. H .. "WHAT IS SENT" .. E .. [==[

Only your own data, never what others shared with you:
- auction sales, returns and purchases, actual time per craft;
- prices you scanned in the last 24 hours, only for items the suggestions use;
- your farming and gathering spots from Yield.

]==] .. H .. "WHAT YOUR FRIEND DOES WITH IT" .. E .. [==[

- Keeps it separately: their own data does not change.
- Your sales weigh half as much as their own.
- Your price is used only when it is fresher than theirs.
- Your farm spots are added to theirs, marked with an asterisk.
- A new share from you replaces the previous one.

]==] .. H .. "SAFETY" .. E .. [==[

Received data is checked field by field and never run as code. Invalid data, data from another realm and oversized transfers are rejected.

]==] .. H .. "COMMANDS" .. E .. [==[

/wtd share - share with your target
/wtd shared - what was shared with you
/wtd shared clear [name] - forget a player's data (no name: everyone's)]==],
		body = H .. "WHAT IT IS" .. E .. [==[

WhatToDo suggests what is most profitable to do right now and ranks the options by gold per hour:
- recraft: buy cheap materials on the auction house, craft, sell;
- mob farming and gathering: mining, herbalism, skinning, fishing.

]==] .. H .. "DEPENDENCIES" .. E .. [==[

- Auctionator: {AUCTIONATOR}
  Auction prices. Without it recraft does not work and loot is valued at vendor prices only.
- Yield: {YIELD}
  Farming sessions. WhatToDo takes spots, time and loot for farming and gathering from it.
Both are optional, but without them the matching sections stay empty.

]==] .. H .. "FIRST STEPS" .. E .. [==[

1. Scan the auction house with Auctionator. Prices older than 3 days are not used.
2. Log in on each character at least once: WhatToDo records professions and skill levels.
3. Open each profession window: exact recipes get recorded, and clicking a row will open its recipe.
4. Farm with Yield enabled for at least 10 minutes at one spot.
5. Open the window: /wtd or the coin button at the minimap.

]==] .. H .. "THE WINDOW" .. E .. [==[

Tabs: All, Recraft, Mobs, Mining, Herbs, Skinning, Fishing.
Each row: gold per hour, short details, and the trust in the suggestion on the right. Hover for the full calculation.
- RECRAFT (AFK): what your characters can craft right now. Click to open the recipe.
- RECRAFT: IF LEARNED: for characters with a free profession slot, with the skill level needed.
- FARMING and gathering: spots from your Yield history, loot at today's prices.

]==] .. H .. "TRUST" .. E .. [==[

Trust = 40% price freshness + 60% evidence.
- Prices up to 6 hours old: 100%, 6 to 12 hours: falling, older than 12 hours: unreliable.
- Evidence: your actual sales from the mail and gold actually received.
Until you have done it at least once, trust stays at 40% or below.

]==] .. H .. "ACTUAL RESULTS" .. E .. [==[

When you take auction mail, WhatToDo records sales, returns and purchases, plus the actual time per craft, and corrects its forecasts by them. The ledger is shared by all characters on the account: craft on one, sell on another.

]==] .. H .. "SHARING DATA" .. E .. [==[

Target a friend in your group (nearby, same WhatToDo version) and click "Share with target". They must accept. Received data is kept separately, and friends' sales weigh half as much as yours.

]==] .. H .. "UPDATES" .. E .. [==[

If someone in your guild, group or friends list has a newer WhatToDo, the addon tells you in chat.

]==] .. H .. "COMMANDS" .. E .. [==[

/wtd - window
/wtd top [n] - best options to chat
/wtd check <item> - why a recipe is or isn't suggested
/wtd stats - actual sales
/wtd share - share data with your target
/wtd shared [clear [name]] - received data
/wtd set - calculation settings
/wtd lang en|uk - language
/wtd minimap - hide or show the minimap button
/wtd guide - this guide
/wtd debug, /wtd version]==],
	},
}

local frame
local topic -- nil: the full guide; "share": the sharing page

local function texts()
	return GUIDE[ns.Lang()] or GUIDE.uk
end

local function status(present, t)
	return present and ("|cff66ff66" .. t.ok .. "|r") or ("|cffff6666" .. t.missing .. "|r")
end

local function fill()
	if not frame then return end
	local t = texts()
	frame.titleText:SetText(topic == "share" and t.shareTitle or t.title)
	local body = (topic == "share" and t.share or t.body)
		:gsub("{AUCTIONATOR}", status(ns.HasAuctionator(), t))
		:gsub("{YIELD}", status(ns.HasYield(), t))
	frame.text:SetText(body)
	frame.content:SetHeight((frame.text:GetStringHeight() or 400) + 20)
	frame.closeButton:SetText(t.close)
	frame.openButton:SetText(t.open)
	frame.langButton:SetText(t.switch)
end
ns.RefreshGuide = fill

local function create()
	local f = CreateFrame("Frame", "WhatToDoGuideFrame", UIParent, "BasicFrameTemplateWithInset")
	f:SetSize(600, 540)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	table.insert(UISpecialFrames, "WhatToDoGuideFrame")

	local title = f.TitleText or f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	if not f.TitleText then title:SetPoint("TOP", 0, -5) end
	f.titleText = title

	local scroll = CreateFrame("ScrollFrame", "WhatToDoGuideScroll", f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 12, -32)
	scroll:SetPoint("BOTTOMRIGHT", -32, 44)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(540, 1)
	scroll:SetScrollChild(content)
	f.content = content

	local text = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetPoint("TOPLEFT", 4, -4)
	text:SetWidth(530)
	text:SetJustifyH("LEFT")
	text:SetJustifyV("TOP")
	if text.SetSpacing then text:SetSpacing(2) end
	f.text = text

	local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	close:SetSize(140, 24)
	close:SetPoint("BOTTOMRIGHT", -14, 12)
	close:SetScript("OnClick", function() f:Hide() end)
	f.closeButton = close

	local open = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	open:SetSize(170, 24)
	open:SetPoint("RIGHT", close, "LEFT", -8, 0)
	open:SetScript("OnClick", function()
		f:Hide()
		if not (WhatToDoFrame and WhatToDoFrame:IsShown()) then ns.Toggle() end
	end)
	f.openButton = open

	local lang = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	lang:SetSize(120, 24)
	lang:SetPoint("BOTTOMLEFT", 14, 12)
	lang:SetScript("OnClick", function() ns.SetLanguage(ns.Lang() == "en" and "uk" or "en") end)
	f.langButton = lang

	f:SetScript("OnShow", fill)
	f:Hide()
	frame = f
end

-- topic: nil for the full guide, "share" for just the sharing page.
function ns.ShowGuide(which)
	if not frame then create() end
	topic = which
	frame:Show()
	fill()
	if WhatToDoGuideScroll and WhatToDoGuideScroll.SetVerticalScroll then WhatToDoGuideScroll:SetVerticalScroll(0) end
end

-- First login with the addon: show the guide once, a moment after the UI settles.
local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", function()
	C_Timer.After(4, function()
		if WhatToDoDB and not WhatToDoDB.guideShown then
			WhatToDoDB.guideShown = true
			ns.ShowGuide()
		end
	end)
end)
