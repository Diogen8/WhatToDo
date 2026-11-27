-- Model 2 (stage 3 of the trust model): logistic regression on your own closed outcomes, and the calibration
-- check of both models. Model 1 (Model.lua) starts from priors; model 2 learns how model 1's numbers actually
-- turned out for you, so it switches on only with enough outcomes (MIN_OUTCOMES per kind).
--   recraft: success = batch in profit; features: model 1's chance (logit), price age, gear or not, batch size.
--   farming: success = at least half the forecast; features: hours behind the forecast, gathering or mobs.
-- Recraft suggestions show model 2's chance (it already holds model 1's); farming shows the mean of the two.
-- /wtd results also prints the calibration: predicted chance vs what happened, and both models' error on the
-- newest 30% of outcomes after learning from the older 70%.
local _, ns = ...
local T = function(s) return ns.T(s) end

local MIN_OUTCOMES = 50
local LAMBDA = 1 -- L2 penalty: keeps the weights small while outcomes are few

local function clamp(p) return math.min(math.max(p, 0.02), 0.98) end
local function logit(p) p = clamp(p) return math.log(p / (1 - p)) end
local function sigmoid(z) return 1 / (1 + math.exp(-z)) end

-- Solve A x = b (small, dense) by Gaussian elimination with partial pivoting.
local function solve(A, b)
	local n = #b
	local M = {}
	for i = 1, n do
		M[i] = {}
		for j = 1, n do M[i][j] = A[i][j] end
		M[i][n + 1] = b[i]
	end
	for c = 1, n do
		local piv = c
		for r = c + 1, n do if math.abs(M[r][c]) > math.abs(M[piv][c]) then piv = r end end
		M[c], M[piv] = M[piv], M[c]
		if math.abs(M[c][c]) < 1e-12 then return nil end
		for r = c + 1, n do
			local f = M[r][c] / M[c][c]
			for k = c, n + 1 do M[r][k] = M[r][k] - f * M[c][k] end
		end
	end
	local x = {}
	for i = n, 1, -1 do
		local s = M[i][n + 1]
		for k = i + 1, n do s = s - M[i][k] * x[k] end
		x[i] = s / M[i][i]
	end
	return x
end

-- Newton's method for L2-penalised logistic regression (the intercept isn't penalised).
local function fit(rows)
	local d = #rows[1].x
	local w = {}
	for j = 1, d do w[j] = 0 end
	for _ = 1, 25 do
		local g, H = {}, {}
		for j = 1, d do
			g[j] = (j > 1) and -LAMBDA * w[j] or 0
			H[j] = {}
			for k = 1, d do H[j][k] = (j == k and j > 1) and LAMBDA or 0 end
		end
		for _, r in ipairs(rows) do
			local z = 0
			for j = 1, d do z = z + w[j] * r.x[j] end
			local p = sigmoid(z)
			local s = p * (1 - p)
			for j = 1, d do
				g[j] = g[j] + (r.y - p) * r.x[j]
				for k = 1, d do H[j][k] = H[j][k] + s * r.x[j] * r.x[k] end
			end
		end
		local step = solve(H, g)
		if not step then break end
		local size = 0
		for j = 1, d do w[j] = w[j] + step[j]; size = size + math.abs(step[j]) end
		if size < 1e-6 then break end
	end
	return w
end

local function predict(w, x)
	local z = 0
	for j = 1, #w do z = z + w[j] * x[j] end
	return sigmoid(z)
end

---------------------------------------------------------------------------
-- Features
---------------------------------------------------------------------------

local function craftFeatures(p1, priceHours, product, crafts)
	local gear = (ns.ItemGroup and ns.ItemGroup(product) == "gear") and 1 or 0
	return { 1, logit(p1), math.log(1 + math.min(priceHours or 24, 72)), gear, math.log(math.max(crafts or 1, 1)) }
end

local function farmFeatures(historyHours, gathering)
	return { 1, math.log(math.max(historyHours, 0.17)), gathering and 1 or 0 }
end

local function farmModel1(r)
	local gathering = r.cat ~= "farm"
	local range = ns.FarmRange and ns.FarmRange(r.forecast, (r.historySeconds or 3600) / 3600, nil, 0, 0, gathering)
	return range and range.success or 0.5
end

-- Outcomes as { x, y, p1 }, oldest first.
local function craftRows()
	local e = ns.EpisodeData and ns.EpisodeData()
	local rows = {}
	for _, o in ipairs((e and e.closed) or {}) do
		local f = o.forecast
		local p1 = f and (f.p1 or f.trust) -- model 1's own chance (older batches kept only the shown one)
		-- every batch teaches, suggested or crafted on your own; only those costed by the pre-0.22 purchase
		-- overcount don't
		if p1 and not o.untrusted then
			rows[#rows + 1] = { x = craftFeatures(p1, f.priceHours, o.product, f.crafts), y = o.success and 1 or 0, p1 = p1 }
		end
	end
	return rows
end

local function farmRows()
	local e = ns.EpisodeData and ns.EpisodeData()
	local rows = {}
	for _, r in ipairs((e and e.farm) or {}) do
		rows[#rows + 1] = { x = farmFeatures((r.historySeconds or 3600) / 3600, r.cat ~= "farm"), y = r.success and 1 or 0, p1 = farmModel1(r) }
	end
	return rows
end

-- Fitted weights, refitted when the number of outcomes changes.
local cache = {}
local function weights(kind)
	local e = ns.EpisodeData and ns.EpisodeData()
	local list = e and ((kind == "craft") and e.closed or e.farm) or {}
	-- the newest outcome's identity too: the lists are capped, so their length alone can stay the same
	local last = list[#list]
	local key = #list .. ":" .. tostring(last and (last.id or last.t) or "")
	local c = cache[kind]
	if c and c.key == key then return c.w, c.n end
	local rows = (kind == "craft") and craftRows() or farmRows()
	local w = (#rows >= MIN_OUTCOMES) and fit(rows) or nil
	cache[kind] = { key = key, n = #rows, w = w }
	return w, #rows
end

-- Model 2's chance for a recraft, or nil while there are too few outcomes.
function ns.Model2Craft(p1, priceHours, product, crafts)
	local w, n = weights("craft")
	if not w then return nil, n end
	return predict(w, craftFeatures(p1, priceHours, product, crafts)), n
end

function ns.Model2Farm(historyHours, gathering)
	local w, n = weights("farm")
	if not w then return nil, n end
	return predict(w, farmFeatures(historyHours, gathering)), n
end

ns.MODEL2_MIN = MIN_OUTCOMES

---------------------------------------------------------------------------
-- Calibration
---------------------------------------------------------------------------

local BINS = { { 0, 0.4 }, { 0.4, 0.6 }, { 0.6, 0.8 }, { 0.8, 1.01 } }

local function calibration(label, rows, p2of)
	if #rows == 0 then return end
	ns.Out(string.format(T("калібрування, %s (%d результатів):"), label, #rows))
	for _, b in ipairs(BINS) do
		local n, pred, hit = 0, 0, 0
		for _, r in ipairs(rows) do
			if r.p1 >= b[1] and r.p1 < b[2] then n, pred, hit = n + 1, pred + r.p1, hit + r.y end
		end
		if n > 0 then
			print(string.format(T("  модель 1 казала %d-%d%%: %d разів, у середньому %d%%, справдилось %d%%"),
				b[1] * 100, math.min(b[2], 1) * 100, n, math.floor(pred / n * 100 + 0.5), math.floor(hit / n * 100 + 0.5)))
		end
	end
	if #rows < MIN_OUTCOMES then
		print(string.format(T("  модель 2 увімкнеться з %d результатів (зараз %d)"), MIN_OUTCOMES, #rows))
		return
	end
	-- honest check: learn on the older 70%, score both models on the newest 30% (Brier: lower is better)
	local cut = math.floor(#rows * 0.7)
	local train, test = {}, {}
	for i, r in ipairs(rows) do if i <= cut then train[#train + 1] = r else test[#test + 1] = r end end
	local w = fit(train)
	local b1, b2 = 0, 0
	for _, r in ipairs(test) do
		local p2 = p2of(predict(w, r.x), r)
		b1 = b1 + (r.p1 - r.y) ^ 2
		b2 = b2 + (p2 - r.y) ^ 2
	end
	print(string.format(T("  похибка на новіших %d (менше - краще): модель 1 %.3f, модель 2 %.3f"), #test, b1 / #test, b2 / #test))
end

function ns.CalibrationReport()
	calibration(T("рекрафт"), craftRows(), function(p) return p end)
	calibration(T("фарм"), farmRows(), function(p, r) return (p + r.p1) / 2 end)
end
