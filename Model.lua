-- Trust model, stage 2 ("model 1"): what a suggestion will REALLY give, as a range, and how likely it is to succeed.
--
-- Every item belongs to a group with its own starting assumptions (priors):
--   gear (weapons, armor)            demand swings: little of it sells, the price jumps around, selling is slow;
--   consumables (potions, stones...) fairly steady;
--   materials (bars, bolts, leather) the steadiest;
--   other                            in between.
-- Each prior weighs as a few imagined sales, so real ones (yours in full, friends' at half) move it, and an
-- item you sell often stops being judged by its group:
--   share of what's posted that sells    Beta(prior + sold, prior + returned)
--   realized / scanned price (after cut) log-normal, its spread shrinking with every sale
--   units the market takes per day       the group's prior, refined by your closed batches
--   hours until the money is back        likewise
--
-- Recraft: the batch is capped at what the market takes in 2 days (no more 20 axes), then 300 scenarios are
-- played out (seeded per item, so the numbers don't flicker): units sold, price, unsold units at vendor price,
-- your active time. Range = 10th to 90th percentile of gold per active hour; success = share of scenarios in
-- profit; the median is used for sorting.
-- Farm: the next session at a spot = its history's rate times a log-normal factor whose spread comes from how far
-- checked sessions fell from their forecasts (Episodes.lua), how much time backs the spot, how old the AH prices
-- are and how much of the loot is gear. Success = at least half the forecast.
local _, ns = ...
local T = function(s) return ns.T(s) end

local SCENARIOS = 300
local Z90 = 1.2816 -- standard normal 90th percentile

local GROUPS = {
	--               sells   weight  price spread  price bias  per day  hours to sell
	gear       = { sell = 0.30, k = 10, sigma = 0.35, mu = -0.10, demand = 2,  wait = 24 },
	consumable = { sell = 0.70, k = 6,  sigma = 0.15, mu = -0.05, demand = 10, wait = 10 },
	material   = { sell = 0.75, k = 4,  sigma = 0.12, mu = -0.03, demand = 20, wait = 6 },
	other      = { sell = 0.50, k = 6,  sigma = 0.25, mu = -0.07, demand = 5,  wait = 12 },
}
local GROUP_NAME = { gear = "екіпірування", consumable = "розхідники", material = "матеріали", other = "інше" }

-- Item class -> group: 2 weapon, 4 armor = gear; 0 consumable; 7 trade goods, 5 reagent, 3 gem = materials.
function ns.ItemGroup(itemID)
	local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
	local classID
	if f then
		local ok, _, _, _, _, _, c = pcall(f, itemID)
		if ok then classID = c end
	end
	if classID == 2 or classID == 4 then return "gear" end
	if classID == 0 then return "consumable" end
	if classID == 7 or classID == 5 or classID == 3 then return "material" end
	return "other"
end

function ns.GroupName(group) return T(GROUP_NAME[group] or group) end

---------------------------------------------------------------------------
-- Random numbers: a seeded Park-Miller generator (exact in Lua's doubles), Box-Muller normals, Marsaglia-Tsang gammas
---------------------------------------------------------------------------

local function rng(seed)
	local state = (seed % 2147483646) + 1
	local r = {}
	function r.uniform()
		state = (16807 * state) % 2147483647
		return state / 2147483647
	end
	function r.normal()
		local u1, u2 = r.uniform(), r.uniform()
		return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
	end
	function r.gamma(a)
		if a < 1 then return r.gamma(a + 1) * r.uniform() ^ (1 / a) end
		local d = a - 1 / 3
		local c = 1 / math.sqrt(9 * d)
		while true do
			local x, v
			repeat
				x = r.normal()
				v = 1 + c * x
			until v > 0
			v = v * v * v
			local u = r.uniform()
			if math.log(u) < 0.5 * x * x + d - d * v + d * math.log(v) then return d * v end
		end
	end
	function r.beta(a, b)
		local x, y = r.gamma(a), r.gamma(b)
		return x / (x + y)
	end
	return r
end

-- Standard normal CDF (Abramowitz-Stegun 7.1.26 through erf).
local function phi(x)
	local t = 1 / (1 + 0.3275911 * math.abs(x) / math.sqrt(2))
	local y = 1 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t
		* math.exp(-x * x / 2)
	return x >= 0 and 0.5 * (1 + y) or 0.5 * (1 - y)
end

-- Extra price spread from age: 0.1 at 6 h, 0.14 at 12 h, 0.2 at a day, capped at 0.35.
local function ageSigma(hours)
	if not hours or hours == math.huge then return 0.35 end
	return math.min(0.35, 0.04 * math.sqrt(math.max(0, hours)))
end

---------------------------------------------------------------------------
-- Per-item posterior
---------------------------------------------------------------------------

-- Closed batches of the product: average units sold per day and hours until sold.
local function batchHistory(product)
	local e = ns.EpisodeData and ns.EpisodeData()
	local n, rate, wait = 0, 0, 0
	for _, o in ipairs((e and e.closed) or {}) do
		if o.product == product and o.sold > 0 then
			n = n + 1
			rate = rate + o.sold / math.max(0.5, (o.waitHours or 24) / 24)
			wait = wait + (o.waitHours or 24)
		end
	end
	if n == 0 then return 0 end
	return n, rate / n, wait / n
end

function ns.ItemModel(itemID)
	local group = ns.ItemGroup(itemID)
	local g = GROUPS[group]
	local s = ns.SalesRecord and ns.SalesRecord(itemID)
	local sold, returned, events = 0, 0, 0
	local mu, sigma = g.mu, g.sigma
	if s then
		sold, returned, events = s.units or 0, s.expired or 0, (s.events or 0) + (s.expiredEvents or 0)
		if (s.expNet or 0) > 0 and (s.expFor or 0) > 0 then
			local n = s.events or 0
			mu = (g.k * g.mu + n * math.log(s.expFor / s.expNet)) / (g.k + n)
			sigma = math.max(0.05, g.sigma * math.sqrt(g.k / (g.k + n)))
		end
	end
	local nb, rate, wait = batchHistory(itemID)
	local demand, waitHours = g.demand, g.wait
	if nb > 0 then
		demand = (2 * g.demand + nb * rate) / (2 + nb)
		waitHours = (2 * g.wait + nb * wait) / (2 + nb)
	end
	return {
		group = group,
		alpha = g.sell * g.k + sold, beta = (1 - g.sell) * g.k + returned,
		mu = mu, sigma = sigma, demand = demand, waitHours = waitHours,
		events = events, batches = nb, friends = s and s.friends or 0, own = s and s.own,
	}
end

---------------------------------------------------------------------------
-- Recraft: play the batch out
---------------------------------------------------------------------------

-- Crafts per batch the market can take in the 2 days a batch has (at least 1).
function ns.DemandCap(product, made)
	local m = ns.ItemModel(product)
	return math.max(1, math.floor(m.demand * 2 / math.max(1, made or 1))), m
end

local function percentile(sorted, q)
	local i = math.max(1, math.min(#sorted, math.floor(q * (#sorted - 1) + 1.5)))
	return sorted[i]
end

-- p: { product, crafts, made, net (scanned price after cut, per unit), vendor (per unit), cost (whole batch),
--      ahCostShare (0..1), activeSeconds, priceHours }
-- Returns { p10, p50, p90 (gold per active hour), success (0..1), profit50, drivers = { text, ... }, model }
function ns.SimulateCraft(p)
	local m = ns.ItemModel(p.product)
	local r = rng(p.product * 7919 + p.crafts)
	local units = p.crafts * (p.made or 1)
	local priceSigma = math.sqrt(m.sigma ^ 2 + ageSigma(p.priceHours) ^ 2)
	local costSigma = 0.05 * (p.ahCostShare or 0)
	local rates, profits, wins = {}, {}, 0
	for i = 1, SCENARIOS do
		local sellShare = r.beta(m.alpha, m.beta)
		local sold = units * sellShare + math.sqrt(math.max(0, units * sellShare * (1 - sellShare))) * r.normal()
		sold = math.max(0, math.min(units, math.floor(sold + 0.5)))
		local ratio = math.exp(m.mu + priceSigma * r.normal())
		local revenue = sold * p.net * ratio + (units - sold) * (p.vendor or 0)
		local cost = p.cost * math.exp(costSigma * r.normal())
		local profit = revenue - cost
		profits[i] = profit
		rates[i] = profit * 3600 / math.max(60, p.activeSeconds)
		if profit > 0 then wins = wins + 1 end
	end
	table.sort(rates)
	table.sort(profits)
	-- what widens the range most
	local drivers = {}
	if m.events < 3 then drivers[#drivers + 1] = T("мало даних про продажі цього предмета") end
	if m.group == "gear" then drivers[#drivers + 1] = T("екіпірування: попит і ціна сильно скачуть") end
	if p.priceHours and p.priceHours > 6 then drivers[#drivers + 1] = string.format(T("ціни не свіжі (%s)"), ns.AgeText(p.priceHours)) end
	if p.capped then drivers[#drivers + 1] = string.format(T("ринок бере ~%.0f шт. на день - партію зменшено"), m.demand) end
	return {
		p10 = percentile(rates, 0.1), p50 = percentile(rates, 0.5), p90 = percentile(rates, 0.9),
		profit10 = percentile(profits, 0.1), profit50 = percentile(profits, 0.5), profit90 = percentile(profits, 0.9),
		success = wins / SCENARIOS, drivers = drivers, model = m,
	}
end

---------------------------------------------------------------------------
-- Farm: next session at a spot
---------------------------------------------------------------------------

-- How far checked sessions fell from their forecasts, over all spots: bias and spread of log(actual / forecast),
-- shrunk toward 0 and 0.35 (worth 5 sessions) while there are few.
local function farmSpread()
	local e = ns.EpisodeData and ns.EpisodeData()
	local n, sum, sq = 0, 0, 0
	for _, r in ipairs((e and e.farm) or {}) do
		if r.forecast > 0 and r.actual > 0 then
			local x = math.log(r.actual / r.forecast)
			n, sum, sq = n + 1, sum + x, sq + x * x
		end
	end
	local k0, s0 = 5, 0.35
	if n == 0 then return 0, s0, 0 end
	local mean = sum / n
	local var = math.max(0, sq / n - mean * mean)
	return n * mean / (k0 + n), math.sqrt((k0 * s0 * s0 + n * var) / (k0 + n)), n
end

-- rate: the spot's gold/h from history; hours: tracked hours behind it; priceHours: age of its AH prices
-- (value-weighted); ahShare, gearShare: shares of its value priced on the AH and coming from gear.
-- Returns { p10, p50, p90, success, drivers }.
function ns.FarmRange(rate, hours, priceHours, ahShare, gearShare, gathering)
	local bias, between, checked = farmSpread()
	local sigmaMean = 0.3 / math.sqrt(math.max(hours or 0, 0.17))
	local sigmaPrice = (ahShare or 0) * ageSigma(priceHours) + (gearShare or 0) * 0.4
	local sigma = math.sqrt(between ^ 2 + sigmaMean ^ 2 + sigmaPrice ^ 2)
	local drivers = {}
	if (hours or 0) < 1 then drivers[#drivers + 1] = T("на цьому місці менше години даних") end
	if checked < 3 then drivers[#drivers + 1] = T("мало перевірених сесій фарму") end
	if (gearShare or 0) > 0.3 then drivers[#drivers + 1] = T("багато доходу з екіпірування") end
	if priceHours and priceHours > 6 and (ahShare or 0) > 0.3 then drivers[#drivers + 1] = string.format(T("ціни не свіжі (%s)"), ns.AgeText(priceHours)) end
	local success = phi((bias - math.log(0.5)) / sigma)
	-- gathering on less than an hour of data: nodes respawn and other gatherers compete, so a short sample says
	-- little; the chance shrinks with the missing time (10 minutes of data: about half)
	if gathering and (hours or 0) < 1 then success = success * (0.4 + 0.6 * math.max(hours or 0, 0)) end
	return {
		p10 = rate * math.exp(bias - Z90 * sigma), p50 = rate * math.exp(bias), p90 = rate * math.exp(bias + Z90 * sigma),
		success = success, drivers = drivers, sigma = sigma,
	}
end

-- For tests
ns._model = { rng = rng, phi = phi, GROUPS = GROUPS }
