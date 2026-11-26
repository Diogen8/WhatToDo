-- Recrafts: buy the reagents (AH or vendor, whichever is cheaper), craft, sell the product on the AH.
-- profit per craft = product price x made x (1 - AH cut) - reagent cost
-- a batch is as many crafts as the AH supply of the reagents allows (supplyShare of what's listed),
-- capped at maxBatch; its time is the casts plus a fixed overhead for buying and posting.
-- gold/h = batch profit / batch time. Selling time isn't counted: listings can take a while to go.
local _, ns = ...

local function evaluate(entry)
	local r = entry.recipe
	if r.cooldown then return nil, "рецепт має кулдаун" end
	local maxAge = ns.Setting("maxPriceAgeDays")

	local net, gross, age = ns.SellNet(r.product)
	if not net then return nil, "немає ціни продукту в Auctionator (проскануйте аукціон)" end
	if (age or math.huge) > maxAge then return nil, string.format("ціна продукту застаріла: %s дн. (ліміт %d)", age and tostring(age) or ">21", maxAge) end
	local made = r.made or 1
	local sellFactor, sold = ns.SellFactor(r.product)
	local expectedRevenue = net * made
	local revenue = expectedRevenue * sellFactor

	local cost, expectedCost, supply, parts = 0, 0, math.huge, {}
	for _, rg in ipairs(r.reagents) do
		local id, count = rg[1], rg[2]
		local unit, source, rAge = ns.BuyCost(id)
		if not unit then return nil, "немає ціни реагенту " .. ns.ItemName(id) .. " (ні аукціон, ні вендор)" end
		local buyFactor = 1
		if source == "AH" then
			if (rAge or math.huge) > maxAge then return nil, string.format("ціна реагенту %s застаріла: %s дн.", ns.ItemName(id), rAge and tostring(rAge) or ">21") end
			buyFactor = ns.BuyFactor(id)
			local listed = ns.Available(id)
			if listed then supply = math.min(supply, math.floor(listed * ns.Setting("supplyShare") / count)) end
		end
		expectedCost = expectedCost + unit * count
		cost = cost + unit * buyFactor * count
		parts[#parts + 1] = { id = id, count = count, unit = unit * buyFactor, source = source, factor = buyFactor }
	end

	local profit = revenue - cost
	if profit < ns.Setting("minProfit") then return nil, string.format("прибуток за крафт %s < мінімуму %s (продаж %s, реагенти %s)", ns.Coin(profit), ns.Coin(ns.Setting("minProfit")), ns.Coin(revenue), ns.Coin(cost)) end

	local crafts = math.min(ns.Setting("maxBatch"), supply)
	if crafts < 1 then return nil, "на аукціоні замало реагентів для хоча б одного крафту" end
	local castSeconds = (r.castMs and r.castMs > 0) and (r.castMs / 1000) or (r.castMs == 0 and 0 or ns.Setting("craftSeconds"))
	local estimatedPerCraft = castSeconds + ns.Setting("craftOverhead")
	local measured = ns.CraftSeconds(r.product)
	local perCraft = measured or estimatedPerCraft
	local seconds = crafts * perCraft + ns.Setting("batchOverhead")
	local perHour = profit * crafts * 3600 / seconds
	-- the same batch without any ledger correction, to show what the correction changed
	local expectedProfit = expectedRevenue - expectedCost
	local expectedPerHour = math.max(0, expectedProfit) * crafts * 3600 / (crafts * estimatedPerCraft + ns.Setting("batchOverhead"))

	local productName = ns.ItemName(r.product)
	local madeText = (made == 1) and "" or string.format(" x%s", (made % 1 == 0) and tostring(made) or string.format("%.1f", made))
	local inputs = {}
	for _, p in ipairs(parts) do inputs[#inputs + 1] = string.format("%dx %s", p.count, ns.ItemName(p.id)) end

	local who = (#entry.who > 0) and table.concat(entry.who, ", ") or "будь-хто"
	local need = (r.profession and r.skill) and string.format("%s %d", r.profession, r.skill) or (r.profession or "без професії")
	local listedProduct = ns.Available(r.product)
	local tip = {
		{ "Продаж" .. madeText, ns.Coin(gross * made) .. "  (чисто " .. ns.Coin(revenue) .. ")" },
	}
	for _, p in ipairs(parts) do
		local fText = p.factor and ns.FactorText(p.factor)
		tip[#tip + 1] = { string.format("  %dx %s", p.count, ns.ItemName(p.id)), string.format("-%s (%s%s)", ns.Coin(p.unit * p.count), p.source == "AH" and "аукціон" or "вендор", fText and (", факт " .. fText) or "") }
	end
	tip[#tip + 1] = { "Прибуток за крафт", ns.Coin(profit) }
	tip[#tip + 1] = { "Маржа", string.format("%.0f%%", cost > 0 and profit / cost * 100 or 0) }
	tip[#tip + 1] = { " ", " " }
	tip[#tip + 1] = { "Партія", string.format("%d крафтів за %.0f хв", crafts, seconds / 60) }
	tip[#tip + 1] = { "Прибуток партії", ns.Coin(profit * crafts) }
	if listedProduct then tip[#tip + 1] = { "Конкуренти на аукціоні", tostring(listedProduct) .. " шт." } end
	tip[#tip + 1] = { " ", " " }
	if sold and sold.units + sold.expired > 0 then
		local offered = sold.units + sold.expired
		tip[#tip + 1] = { "Факт продажів", string.format("продано %d з %d (%.0f%%)", sold.units, offered, sold.units / offered * 100) }
		if sold.expNet > 0 then tip[#tip + 1] = { "Ціна факт / очікувана", string.format("%.0f%%", sold.expFor / sold.expNet * 100) } end
	else
		tip[#tip + 1] = { "Факт продажів", "ще немає" }
	end
	if measured then tip[#tip + 1] = { "Час на крафт (факт)", string.format("%.1f с", measured) } end
	tip[#tip + 1] = { "Без поправок було б", ns.Coin(expectedPerHour) .. "/год" }
	tip[#tip + 1] = { "Ціни сканувались", (age == 0) and "сьогодні" or string.format("%d дн. тому", age or 0) }
	tip[#tip + 1] = { entry.section == "learn" and "Вивчити" or "Професія", need }
	tip[#tip + 1] = { entry.section == "learn" and "Вільний слот у" or "Хто може", who }
	if r.catalog then tip[#tip + 1] = { "Рецепт", "з каталогу (у тренера)" } end

	return {
		kind = entry.section or "craft",
		title = table.concat(inputs, " + ") .. "  >>  " .. productName .. madeText,
		perHour = perHour,
		expectedPerHour = expectedPerHour,
		corrected = (sellFactor ~= 1) or (cost ~= expectedCost) or (measured ~= nil),
		detail = entry.section == "learn"
			and string.format("вивчити %s, %s за крафт, %s", need, ns.Coin(profit), who)
			or string.format("%s за крафт, %d крафтів/партія, %s", ns.Coin(profit), crafts, who),
		tooltip = tip,
		profit = profit,
		crafts = crafts,
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
			local who = (#entry.who > 0) and table.concat(entry.who, ", ") or "будь-хто"
			local a, reason = evaluate(entry)
			local head = string.format("%s [%s, %s]", name, entry.section == "learn" and "якщо вивчити" or "рекрафт", who)
			if a then
				print(string.format("  %s: |cff66ff66пропонується|r - %s/год, %s", head, ns.Coin(a.perHour), a.detail))
			else
				print(string.format("  %s: |cffff6666ні|r - %s", head, reason or "?"))
			end
		end
	end
	if found == 0 then
		local needs = {}
		for _, r in ipairs(ns.CATALOG) do
			local name = ns.ItemName(r.product)
			if r.product == id or (q ~= "" and name:lower():find(q, 1, true)) then
				needs[#needs + 1] = string.format("%s - потрібно %s %d", name, r.profession, r.skill)
			end
		end
		if #needs > 0 then
			print("  ніхто з персонажів поки не може: " .. table.concat(needs, "; "))
		else
			print("  жоден відомий рецепт цього не робить (відкрийте вікно професії, щоб записати рецепти).")
		end
		print("  персонажі: " .. ns.KnownCharsText())
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
