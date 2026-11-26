-- Recrafts: buy the reagents (AH or vendor, whichever is cheaper), craft, sell the product on the AH.
-- profit per craft = product price x made x (1 - AH cut) - reagent cost
-- a batch is as many crafts as the AH supply of the reagents allows (supplyShare of what's listed),
-- capped at maxBatch; its time is the casts plus a fixed overhead for buying and posting.
-- gold/h = batch profit / batch time. Selling time isn't counted: listings can take a while to go.
local _, ns = ...
local T = function(s) return ns.T(s) end

local function evaluate(entry)
	local r = entry.recipe
	if r.cooldown then return nil, T("рецепт має кулдаун") end
	local maxAge = ns.Setting("maxPriceAgeDays")

	local net, gross, age = ns.SellNet(r.product)
	if not net then return nil, T("немає ціни продукту в Auctionator (проскануйте аукціон)") end
	if (age or math.huge) > maxAge then return nil, string.format(T("ціна продукту застаріла: %s дн. (ліміт %d)"), age and tostring(age) or ">21", maxAge) end
	local made = r.made or 1
	local sellFactor, sold = ns.SellFactor(r.product)
	local expectedRevenue = net * made
	local revenue = expectedRevenue * sellFactor

	local cost, expectedCost, supply, parts = 0, 0, math.huge, {}
	for _, rg in ipairs(r.reagents) do
		local id, count = rg[1], rg[2]
		local unit, source, rAge = ns.BuyCost(id)
		if not unit then return nil, T("немає ціни реагенту ") .. ns.ItemName(id) .. T(" (ні аукціон, ні вендор)") end
		local buyFactor = 1
		if source == "AH" then
			if (rAge or math.huge) > maxAge then return nil, string.format(T("ціна реагенту %s застаріла: %s дн."), ns.ItemName(id), rAge and tostring(rAge) or ">21") end
			buyFactor = ns.BuyFactor(id)
			local listed = ns.Available(id)
			if listed then supply = math.min(supply, math.floor(listed * ns.Setting("supplyShare") / count)) end
		end
		expectedCost = expectedCost + unit * count
		cost = cost + unit * buyFactor * count
		parts[#parts + 1] = { id = id, count = count, unit = unit * buyFactor, source = source, factor = buyFactor }
	end

	-- trust in the prices: the stalest AH price among the product and the AH-bought reagents
	local stalestHours, stalestItem = ns.PriceHours(r.product) or math.huge, r.product
	for _, p in ipairs(parts) do
		if p.source == "AH" then
			local h = ns.PriceHours(p.id) or math.huge
			if h > stalestHours then stalestHours, stalestItem = h, p.id end
		end
	end
	local priceTrust = ns.TrustOfHours(stalestHours)
	-- evidence: real sales of the product; never for recipes not learned yet
	local salesCount = ns.SalesCount(r.product)
	local evidence = entry.section == "learn" and 0 or ns.EvidenceOfSales(salesCount)
	local trust = ns.CombineTrust(priceTrust, evidence)

	local profit = revenue - cost
	if profit < ns.Setting("minProfit") then return nil, string.format(T("прибуток за крафт %s < мінімуму %s (продаж %s, реагенти %s)"), ns.Coin(profit), ns.Coin(ns.Setting("minProfit")), ns.Coin(revenue), ns.Coin(cost)) end

	local crafts = math.min(ns.Setting("maxBatch"), supply)
	if crafts < 1 then return nil, T("на аукціоні замало реагентів для хоча б одного крафту") end
	-- no bigger than the market takes in the 2 days a batch has
	local cap = ns.DemandCap and ns.DemandCap(r.product, made)
	local capped = cap and crafts > cap
	if capped then crafts = cap end
	local castSeconds = (r.castMs and r.castMs > 0) and (r.castMs / 1000) or (r.castMs == 0 and 0 or ns.Setting("craftSeconds"))
	local estimatedPerCraft = castSeconds + ns.Setting("craftOverhead")
	local measured = ns.CraftSeconds(r.product)
	local perCraft = measured or estimatedPerCraft
	local seconds = crafts * perCraft + ns.Setting("batchOverhead")
	local perHour = profit * crafts * 3600 / seconds
	-- the same batch without any ledger correction, to show what the correction changed
	local expectedProfit = expectedRevenue - expectedCost
	local expectedPerHour = math.max(0, expectedProfit) * crafts * 3600 / (crafts * estimatedPerCraft + ns.Setting("batchOverhead"))

	-- model 1: play the batch out (Model.lua). Works from the scanned price before ledger corrections: the model
	-- applies real sales itself, so they aren't counted twice.
	local sim
	if ns.SimulateCraft then
		local ahCost = 0
		for _, p in ipairs(parts) do
			if p.source == "AH" then ahCost = ahCost + p.unit * p.count end
		end
		local vendor = select(11, (C_Item and C_Item.GetItemInfo or GetItemInfo)(r.product)) or 0
		sim = ns.SimulateCraft({
			product = r.product, crafts = crafts, made = made, net = net, vendor = vendor,
			cost = cost * crafts, ahCostShare = cost > 0 and ahCost / cost or 0,
			activeSeconds = seconds, priceHours = stalestHours, capped = capped,
		})
	end

	if sim and sim.p90 <= 0 then
		return nil, string.format(T("модель: навіть оптимістичний сценарій у мінусі (%s - %s/год, у плюс %d%%)"),
			ns.Coin(sim.p10), ns.Coin(sim.p90), math.floor(sim.success * 100 + 0.5))
	end

	local productName = ns.ItemName(r.product)
	local madeText = (made == 1) and "" or string.format(" x%s", (made % 1 == 0) and tostring(made) or string.format("%.1f", made))
	local inputs = {}
	for _, p in ipairs(parts) do inputs[#inputs + 1] = string.format("%dx %s", p.count, ns.ItemName(p.id)) end

	local who = (#entry.who > 0) and table.concat(entry.who, ", ") or T("будь-хто")
	local need = (r.profession and r.skill) and string.format("%s %d", r.profession, r.skill) or (r.profession or T("без професії"))
	if entry.section == "learn" and r.skill then need = need .. string.format(T(" (з %d рівня)"), ns.LevelForSkill(r.skill)) end
	local listedProduct = ns.Available(r.product)
	local tip = {
		{ T("Рецепт"), table.concat(inputs, " + ") },
	}
	if sim then
		tip[#tip + 1] = { T("Діапазон (8 з 10 випадків)"), ns.Coin(sim.p10) .. " - " .. ns.Coin(sim.p90) .. T("/год") }
		tip[#tip + 1] = { T("Найімовірніше"), ns.Coin(sim.p50) .. T("/год") }
		tip[#tip + 1] = { T("У плюс"), string.format("%d%%", math.floor(sim.success * 100 + 0.5)) }
		tip[#tip + 1] = { T("Прибуток партії"), ns.Coin(sim.profit10) .. " - " .. ns.Coin(sim.profit90) }
		tip[#tip + 1] = { T("Гроші повернуться"), string.format(T("за ~%s"), ns.AgeText(sim.model.waitHours)) }
		tip[#tip + 1] = { T("Група"), ns.GroupName(sim.model.group) .. ((sim.model.events or 0) > 0 and string.format(T(", продажів у моделі: %s"), tostring(math.floor(sim.model.events + 0.5))) or "") }
		for i, d in ipairs(sim.drivers) do tip[#tip + 1] = { i == 1 and T("Невизначеність") or " ", d } end
		tip[#tip + 1] = { " ", " " }
	end
	for _, line in ipairs({
		{ T("Без моделі (лише ціни)"), ns.Coin(perHour) .. T("/год") },
		{ T("Продаж") .. madeText, ns.Coin(gross * made) .. T("  (чисто ") .. ns.Coin(revenue) .. ")" },
	}) do tip[#tip + 1] = line end
	for _, p in ipairs(parts) do
		local fText = p.factor and ns.FactorText(p.factor)
		tip[#tip + 1] = { string.format("  %dx %s", p.count, ns.ItemName(p.id)), string.format("-%s (%s%s)", ns.Coin(p.unit * p.count), p.source == "AH" and T("аукціон") or T("вендор"), fText and (T(", факт ") .. fText) or "") }
	end
	tip[#tip + 1] = { T("Прибуток за крафт"), ns.Coin(profit) }
	tip[#tip + 1] = { T("Маржа"), string.format("%.0f%%", cost > 0 and profit / cost * 100 or 0) }
	tip[#tip + 1] = { " ", " " }
	tip[#tip + 1] = { T("Партія"), string.format(T("%d крафтів за %.0f хв"), crafts, seconds / 60) }
	tip[#tip + 1] = { sim and T("Прибуток партії, якщо все продасться") or T("Прибуток партії"), ns.Coin(profit * crafts) }
	if listedProduct then tip[#tip + 1] = { T("Конкуренти на аукціоні"), tostring(listedProduct) .. T(" шт.") } end
	tip[#tip + 1] = { " ", " " }
	if sold and sold.units + sold.expired > 0 then
		local offered = sold.units + sold.expired
		tip[#tip + 1] = { T("Факт продажів"), string.format(T("продано %d з %d (%.0f%%)"), math.floor(sold.units + 0.5), math.floor(offered + 0.5), sold.units / offered * 100)
			.. ((sold.friends or 0) > 0 and (sold.own and T(", з даними друзів") or T(", лише дані друзів")) or "") }
		if sold.expNet > 0 then tip[#tip + 1] = { T("Ціна факт / очікувана"), string.format("%.0f%%", sold.expFor / sold.expNet * 100) } end
	else
		tip[#tip + 1] = { T("Факт продажів"), T("ще немає") }
	end
	local batches, inPlus, openBatch = ns.BatchStats and ns.BatchStats(r.product)
	if (batches or 0) > 0 or openBatch then
		tip[#tip + 1] = { T("Партії"), string.format(T("закрито %d, у плюс %d"), batches or 0, inPlus or 0) .. (openBatch and T(", одна відкрита") or "") }
	end
	if measured then tip[#tip + 1] = { T("Час на крафт (факт)"), string.format(T("%.1f с"), measured) } end
	if not sim then tip[#tip + 1] = { T("Без поправок було б"), ns.Coin(expectedPerHour) .. T("/год") } end
	tip[#tip + 1] = { T("Найстаріша ціна"), string.format(T("%s, %s тому"), ns.ItemName(stalestItem), ns.AgeText(stalestHours))
		.. (ns.PriceFrom(stalestItem) and string.format(T(" (скан %s)"), ns.PriceFrom(stalestItem)) or "") }
	tip[#tip + 1] = { entry.section == "learn" and T("Вивчити") or T("Професія"), need }
	tip[#tip + 1] = { entry.section == "learn" and T("Вільний слот у") or T("Хто може"), who }
	if r.catalog then tip[#tip + 1] = { T("Джерело рецепта"), T("каталог (у тренера)") } end

	return {
		kind = entry.section or "craft",
		title = productName .. madeText,
		perHour = sim and sim.p50 or perHour,
		expectedPerHour = expectedPerHour,
		corrected = not sim and ((sellFactor ~= 1) or (cost ~= expectedCost) or (measured ~= nil)),
		detail = entry.section == "learn"
			and string.format(T("вивчити %s, %s за крафт, %s"), need, ns.Coin(profit), who)
			or string.format(T("%s за крафт, %d крафтів/партія, %s"), ns.Coin(profit), crafts, who),
		tooltip = tip,
		profit = profit,
		crafts = crafts,
		product = r.product,
		trust = sim and sim.success or trust,
		range = sim and { sim.p10, sim.p50, sim.p90 } or nil,
		rawPerHour = perHour,
		priceTrust = priceTrust,
		trustHours = stalestHours,
		trustItem = stalestItem,
		who = who,
		need = need,
		conversion = r.profession == "Essences",
	}
end

-- /wtd check <item name or ID>: why each recipe making that item is or isn't suggested.
function ns.Explain(query)
	local id = tonumber(query)
	local q = (query or ""):lower()
	local found = 0
	for _, entry in ipairs(ns.AllRecipes()) do
		local r = entry.recipe
		local name = ns.ItemName(r.product)
		if r.product == id or (q ~= "" and name:lower():find(q, 1, true)) then
			found = found + 1
			local who = (#entry.who > 0) and table.concat(entry.who, ", ") or T("будь-хто")
			local a, reason = evaluate(entry)
			local head = string.format("%s [%s, %s]", name, entry.section == "learn" and T("якщо вивчити") or T("рекрафт"), who)
			if a then
				print(string.format(T("  %s: |cff66ff66пропонується|r - %s/год, %s, %s (%s: %s тому)"), head, ns.Coin(a.perHour), a.detail, ((a.range and ns.SuccessLabel or ns.TrustLabel)(a.trust)), ns.ItemName(a.trustItem), ns.AgeText(a.trustHours)))
			else
				print(string.format(T("  %s: |cffff6666ні|r - %s"), head, reason or "?"))
			end
		end
	end
	if found == 0 then
		local needs = {}
		for _, r in ipairs(ns.CATALOG) do
			local name = ns.ItemName(r.product)
			if r.product == id or (q ~= "" and name:lower():find(q, 1, true)) then
				needs[#needs + 1] = string.format(T("%s - потрібно %s %d"), name, r.profession, r.skill)
			end
		end
		if #needs > 0 then
			print(T("  ніхто з персонажів поки не може: ") .. table.concat(needs, "; "))
		else
			print(T("  жоден відомий рецепт цього не робить (відкрийте вікно професії, щоб записати рецепти)."))
		end
		print(T("  персонажі: ") .. ns.KnownCharsText())
	end
end

function ns.CraftActivities()
	local out = {}
	if not ns.HasAuctionator() then return out end
	for _, entry in ipairs(ns.AllRecipes()) do
		local a = evaluate(entry)
		if a then out[#out + 1] = a end
	end
	return out
end
