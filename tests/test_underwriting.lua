dofile("scripts/BankUnderwriting.lua")

local count = 0
local function test(name, fn)
    if _G.test ~= nil then _G.test("underwriting: " .. name, fn); return end
    fn()
    count = count + 1
    print("PASS underwriting: " .. name)
end
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function near(actual, expected)
    assert(type(actual) == "number" and math.abs(actual - expected) < 0.000001)
end
local function hasReason(result, code)
    for _, list in ipairs({result.assessment.withheldReasons, result.assessment.reasons}) do
        for _, value in ipairs(list) do if value.code == code then return true end end
    end
    return false
end
local function fixture()
    local snapshot = {farm = {id = 7}, cash = {status = "available", value = 2000}, debt = {status = "available", value = 10000},
        land = {status = "available", totalValue = 40000}, equipment = {status = "available", ownedValue = 10000}, buildings = {status = "partial", totalValue = 20000}}
    local history = {farmId = 7, currentYear = 3, currentMonth = 1, periods = {}, materialGaps = {}}
    for month = 1, 12 do
        history.periods[#history.periods + 1] = {year = 2, month = month, complete = true, reconciled = true,
            operatingRevenue = 1000, operatingExpense = 800, interestExpense = 100,
            capitalInflow = 0, capitalOutflow = 0, financingInflow = 0, financingOutflow = 0,
            unclassifiedInflow = 0, unclassifiedOutflow = 0}
    end
    return snapshot, history
end

test("complete native cycle produces transparent bounded score", function()
    local snapshot, history = fixture()
    local result = BankUnderwriting.prepare(snapshot, history)
    equal(result.assessment.status, "available")
    equal(result.assessment.score, 62)
    equal(result.assessment.band, "guarded")
    equal(result.assessment.provisional, true)
    equal(result.assessment.cashBeforePrincipal, 1200)
    equal(result.assessment.operatingCashBeforeInterest, 2400)
    equal(result.assessment.principalCoverage.status, "unavailable")
    equal(result.assessment.profitability.status, "unavailable")
    near(result.assessment.components[1].value, 0.2)
    near(result.assessment.components[2].value, 2000 / 900)
    near(result.assessment.components[3].value, 2)
    near(result.assessment.components[4].value, 10000 / 2400)
    local points = 0
    for _, item in ipairs(result.assessment.components) do points = points + item.points end
    equal(result.assessment.score, math.floor(points + 0.5))
end)

test("new save has insufficient evidence without invented grade", function()
    local snapshot, history = fixture()
    history.periods = {}
    local result = BankUnderwriting.prepare(snapshot, history)
    equal(result.assessment.score, nil)
    equal(result.assessment.band, nil)
    equal(result.history.totals, nil)
    equal(result.forecast.status, "insufficient_evidence")
    assert(hasReason(result, "INSUFFICIENT_HISTORY"))
end)

test("shorter observations are summed without annualization", function()
    local snapshot, history = fixture()
    for index = 1, 9 do history.periods[index] = nil end
    local result = BankUnderwriting.prepare(snapshot, history)
    equal(result.history.observedPeriodCount, 3)
    equal(result.history.totals.operatingRevenue, 3000)
    equal(result.assessment.score, nil)
    equal(#result.forecast.periods, 0)
end)

test("partial first month cannot impersonate a complete year", function()
    local snapshot, history = fixture()
    history.periods[1].complete = false
    local result = BankUnderwriting.prepare(snapshot, history)
    equal(result.history.completePeriodCount, 11)
    equal(result.assessment.score, nil)
    assert(hasReason(result, "INCOMPLETE_PERIOD"))
end)

test("failed cash reconciliation blocks scoring and seasonality", function()
    local snapshot, history = fixture()
    history.periods[6].reconciled = false
    local result = BankUnderwriting.prepare(snapshot, history)
    equal(result.assessment.score, nil)
    equal(result.forecast.status, "insufficient_evidence")
end)

test("unclassified inflows and outflows cannot cancel their uncertainty", function()
    local snapshot, history = fixture()
    history.periods[4].unclassifiedInflow = 500
    history.periods[4].unclassifiedOutflow = 500
    local result = BankUnderwriting.prepare(snapshot, history)
    equal(result.assessment.score, nil)
    assert(hasReason(result, "UNCLASSIFIED_ACTIVITY"))
end)

test("missing cost is unavailable and never zero", function()
    local snapshot, history = fixture()
    history.periods[6].operatingExpense = nil
    local result = BankUnderwriting.prepare(snapshot, history)
    equal(result.assessment.score, nil)
    equal(result.history.totals.operatingRevenue, 11000)
    assert(hasReason(result, "INVALID_PERIOD_AMOUNTS"))
end)

test("negative or nonfinite gross amounts invalidate a period", function()
    for _, invalid in ipairs({-1, 0 / 0, math.huge, -math.huge}) do
        local snapshot, history = fixture()
        history.periods[6].operatingExpense = invalid
        local result = BankUnderwriting.prepare(snapshot, history)
        equal(result.assessment.score, nil)
        assert(hasReason(result, "INVALID_PERIOD_AMOUNTS"))
    end
end)

test("duplicate dated months are never summed twice", function()
    local snapshot, history = fixture()
    history.periods[13] = history.periods[3]
    local result = BankUnderwriting.prepare(snapshot, history)
    equal(result.history.totals.operatingRevenue, 11000)
    equal(result.assessment.score, nil)
    assert(hasReason(result, "DUPLICATE_PERIOD"))
end)

test("old duplicate records do not invalidate a clean current window", function()
    local snapshot, history = fixture()
    history.periods[13] = {year = 0, month = 1}
    history.periods[14] = {year = 0, month = 1}
    equal(BankUnderwriting.prepare(snapshot, history).assessment.score, 62)
end)

test("calendar gaps remain gaps despite twelve records", function()
    local snapshot, history = fixture()
    history.periods[1].year = 1
    local result = BankUnderwriting.prepare(snapshot, history)
    equal(result.history.observedPeriodCount, 11)
    equal(result.assessment.score, nil)
end)

test("unverified or malformed date prevents invented chronology", function()
    local snapshot, history = fixture()
    history.currentMonth = nil
    local result = BankUnderwriting.prepare(snapshot, history)
    assert(hasReason(result, "CURRENT_CALENDAR_UNAVAILABLE"))
    equal(result.assessment.score, nil)
    history.currentMonth = 1
    history.periods[5].month = 13
    result = BankUnderwriting.prepare(snapshot, history)
    assert(hasReason(result, "MALFORMED_HISTORY"))
end)

test("seasonal scenario matches seasonal slot and omits partial current month", function()
    local snapshot, history = fixture()
    for index, period in ipairs(history.periods) do period.operatingRevenue = index * 1000 end
    local result = BankUnderwriting.prepare(snapshot, history)
    equal(result.forecast.status, "available")
    equal(result.forecast.confidence, "limited_single_cycle")
    equal(#result.forecast.periods, 12)
    equal(result.forecast.periods[1].year, 3)
    equal(result.forecast.periods[1].month, 2)
    equal(result.forecast.periods[1].sourceYear, 2)
    equal(result.forecast.periods[1].operatingRevenue, 2000)
    equal(result.forecast.periods[12].year, 4)
    equal(result.forecast.periods[12].month, 1)
    equal(result.forecast.periods[12].operatingRevenue, 1000)
    equal(result.forecast.annualOperatingRevenue, 78000)
    equal(result.forecast.closingCash, nil)
end)

test("capital sales borrowing and asset prices never create operating income", function()
    local snapshot, history = fixture()
    local before = BankUnderwriting.prepare(snapshot, history)
    snapshot.land.totalValue = 90000000
    snapshot.equipment.ownedValue = 90000000
    history.periods[1].capitalInflow = 9000000
    history.periods[1].financingInflow = 7000000
    history.periods[1].financingOutflow = 200000
    history.periods[1].capitalOutflow = 300000
    local after = BankUnderwriting.prepare(snapshot, history)
    equal(after.assessment.score, before.assessment.score)
    equal(after.forecast.annualCashBeforePrincipal, before.forecast.annualCashBeforePrincipal)
    assert(after.collateral.knownAssetQuotes > before.collateral.knownAssetQuotes)
    equal(after.collateral.includedInScore, false)
    equal(after.history.totals.classifiedNetCash, 15501200)
end)

test("mode thresholds are monotonic and independently copied", function()
    local snapshot, history = fixture()
    local lenient = BankUnderwriting.prepare(snapshot, history, {mode = "lenient"})
    local standard = BankUnderwriting.prepare(snapshot, history, {mode = "standard"})
    local strict = BankUnderwriting.prepare(snapshot, history, {mode = "strict"})
    assert(lenient.assessment.score >= standard.assessment.score)
    assert(standard.assessment.score >= strict.assessment.score)
    standard.assessment.thresholds.marginLow = 1000
    equal(BankUnderwriting.prepare(snapshot, history).assessment.score, 62)
    equal(BankUnderwriting.prepare(snapshot, history, {mode = "invalid"}).mode, "standard")
end)

test("complete inactive year remains startup evidence not failed grade", function()
    local snapshot, history = fixture()
    snapshot.debt.value = 0
    for _, period in ipairs(history.periods) do
        period.operatingRevenue, period.operatingExpense, period.interestExpense = 0, 0, 0
    end
    local result = BankUnderwriting.prepare(snapshot, history)
    equal(result.assessment.score, nil)
    assert(hasReason(result, "NO_OPERATING_ACTIVITY"))
    equal(result.forecast.annualCashBeforePrincipal, 0)
end)

test("unknown cash and native debt cannot produce a score", function()
    local snapshot, history = fixture()
    snapshot.cash.status = "partial"
    snapshot.debt.value = nil
    local result = BankUnderwriting.prepare(snapshot, history)
    equal(result.assessment.score, nil)
    assert(hasReason(result, "CASH_UNAVAILABLE"))
    assert(hasReason(result, "NATIVE_DEBT_UNAVAILABLE"))
end)

test("native debt without observed interest withholds cost-based assessment", function()
    local snapshot, history = fixture()
    for _, period in ipairs(history.periods) do period.interestExpense = 0 end
    local result = BankUnderwriting.prepare(snapshot, history)
    equal(result.assessment.score, nil)
    assert(hasReason(result, "NATIVE_INTEREST_UNOBSERVED"))
    snapshot.debt.value = 0
    result = BankUnderwriting.prepare(snapshot, history)
    equal(result.assessment.status, "available")
    equal(result.assessment.components[3].value, nil)
    equal(result.assessment.components[3].status, "no_native_interest_obligation_observed")
end)

test("material gaps and suspected external debt gate a score", function()
    local snapshot, history = fixture()
    history.materialGaps = {"Unresolved money source"}
    local result = BankUnderwriting.prepare(snapshot, history)
    assert(hasReason(result, "MATERIAL_DATA_GAP"))
    equal(result.assessment.score, nil)
    equal(result.forecast.status, "insufficient_evidence")
    equal(result.forecast.withheldReason, "MATERIAL_DATA_GAP")
    equal(#result.forecast.periods, 0)
    history.materialGaps = {}
    result = BankUnderwriting.prepare(snapshot, history, {materialExternalLiabilityUnknown = true})
    assert(hasReason(result, "MATERIAL_EXTERNAL_LIABILITY_UNKNOWN"))
    equal(result.assessment.score, nil)
    equal(result.forecast.status, "available")
    result = BankUnderwriting.prepare(snapshot, history, {externalLiabilitiesKnown = true})
    equal(result.assessment.provisional, false)
    equal(result.assessment.score, 62)
end)

test("missing or invalid farm identity cannot authorize a score or seasonal scenario", function()
    for _, invalid in ipairs({false, "7", 0, -1, 1.5, math.huge, 0/0}) do
        local snapshot, history = fixture()
        history.farmId = invalid
        local result = BankUnderwriting.prepare(snapshot, history)
        equal(result.assessment.score, nil)
        equal(result.forecast.status, "insufficient_evidence")
        assert(hasReason(result, "HISTORY_FARM_UNAVAILABLE"))
    end
    for _, target in ipairs({"snapshot", "history"}) do
        local snapshot, history = fixture()
        if target == "snapshot" then snapshot.farm = nil else history.farmId = nil end
        local result = BankUnderwriting.prepare(snapshot, history)
        equal(result.assessment.score, nil)
        equal(result.forecast.withheldReason, "HISTORY_FARM_UNAVAILABLE")
        equal(#result.forecast.periods, 0)
    end
end)

test("unverified material coverage also withholds a seasonal scenario", function()
    local snapshot, history = fixture()
    history.materialGaps = nil
    local result = BankUnderwriting.prepare(snapshot, history)
    equal(result.assessment.score, nil)
    equal(result.forecast.status, "insufficient_evidence")
    equal(result.forecast.withheldReason, "MATERIAL_COVERAGE_UNKNOWN")
    equal(#result.forecast.periods, 0)
end)

test("history from another farm cannot be rated", function()
    local snapshot, history = fixture()
    history.farmId = 8
    local result = BankUnderwriting.prepare(snapshot, history)
    assert(hasReason(result, "HISTORY_FARM_MISMATCH"))
    equal(result.assessment.score, nil)
    equal(result.forecast.status, "insufficient_evidence")
    equal(#result.forecast.periods, 0)
end)

test("negative cash and operating loss are explicit not infinities", function()
    local snapshot, history = fixture()
    snapshot.cash.value = -100
    for _, period in ipairs(history.periods) do period.operatingRevenue = 500 end
    local result = BankUnderwriting.prepare(snapshot, history)
    equal(result.assessment.status, "available")
    equal(result.assessment.score, 0)
    equal(result.assessment.band, "strained")
    assert(hasReason(result, "NEGATIVE_CASH"))
    assert(hasReason(result, "OPERATING_CASH_SHORTFALL"))
    assert(hasReason(result, "INTEREST_NOT_COVERED"))
    equal(result.assessment.components[4].value, nil)
end)

test("overflow is unavailable not a fabricated bounded score", function()
    local snapshot, history = fixture()
    for _, period in ipairs(history.periods) do period.operatingRevenue = 1e308 end
    local result = BankUnderwriting.prepare(snapshot, history)
    equal(result.assessment.score, nil)
    equal(result.history.totals, nil)
    assert(hasReason(result, "HISTORY_OVERFLOW"))
end)

test("returned observations have no live references to supplied history", function()
    local snapshot, history = fixture()
    local result = BankUnderwriting.prepare(snapshot, history)
    result.history.periods[1].operatingRevenue = 0
    result.history.totals.operatingRevenue = 0
    result.collateral.components.land = 0
    equal(history.periods[1].operatingRevenue, 1000)
    equal(snapshot.land.totalValue, 40000)
    equal(BankUnderwriting.prepare(snapshot, history).assessment.score, 62)
end)

test("unavailable collateral figures are not resurrected from stale numbers", function()
    local snapshot, history = fixture()
    snapshot.land.status = "unavailable"
    local result = BankUnderwriting.prepare(snapshot, history)
    equal(result.collateral.knownAssetQuotes, 30000)
    equal(result.collateral.components.land, nil)
    equal(result.assessment.score, 62)
end)

test("conflicting duplicate rows never choose a financial winner", function()
    local snapshot, history = fixture()
    history.periods[13] = {year = 2, month = 3, operatingRevenue = 90000}
    local result = BankUnderwriting.prepare(snapshot, history)
    equal(result.history.periods[3].operatingRevenue, nil)
    equal(result.history.periods[3].duplicate, true)
    equal(result.history.totals.operatingRevenue, 11000)
    equal(result.assessment.score, nil)
end)

if _G.test == nil then print(tostring(count) .. " underwriting tests passed") end
