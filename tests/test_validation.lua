dofile("scripts/BankValidation.lua")
local function base()
    return {farm = {id = 7}, cash = {status = "available", value = 100}, debt = {status = "available", value = 0},
        land = {status = "available", items = {{id = 1, value = 50, areaHa = 1}}, totalValue = 50, totalAreaHa = 1},
        equipment = {status = "available", items = {{id = "A", ownership = "owned", value = 30}, {id = "B", ownership = "leased"}}, ownedValue = 30, ownedCount = 1, leasedCount = 1, borrowedCount = 0},
        buildings = {status = "available", items = {}, totalValue = 0},
        animals = {status = "available", items = {}, totalValue = 0, totalCount = 0},
        inventory = {items = {{id = "fill", quantityStatus = "available", quantity = 0, unit = "l"}}},
        finance = {verification = "unverified", windowStatus = "unverified", records = {}, knownValueCount = 0, unknownValueCount = 0, unclassifiedCount = 0},
        history = {farmId = 7, periods = {}, materialGaps = {}},
        underwriting = {assessment = {status = "insufficient_evidence"}, forecast = {status = "insufficient_evidence", periods = {}}, collateral = {includedInScore = false}}}
end
local function outcome(rows, id, wanted)
    for _, r in ipairs(rows) do if r.id == "AUTO_" .. id and r.outcome == wanted then return true end end
    return false
end

test("snapshot invariants accept valid partial evidence without claiming complete underwriting", function()
    local rows = BankValidation.evaluate(base())
    for _, row in ipairs(rows) do assertFalse(row.outcome == "FAIL", row.id) end
    assertTrue(outcome(rows, "SCORE_SUM", "NOT_EXERCISED"))
    assertTrue(outcome(rows, "MODEL_WITHHELD_NO_SCORE", "PASS"))
end)

test("independent asset sums catch duplicate identifiers incorrect subtotals and leased valuation", function()
    local s = base()
    s.land.totalValue = 500
    s.land.items[2] = {id = 1, value = 5, areaHa = 0}
    s.equipment.items[2].value = 99
    local rows = BankValidation.evaluate(s)
    assertTrue(outcome(rows, "LAND_SUM", "FAIL"))
    assertTrue(outcome(rows, "LAND_UNIQUE_IDS", "FAIL"))
    assertTrue(outcome(rows, "EQUIPMENT_EXCLUDED_VALUE", "FAIL"))
end)

test("unknown financial readings never silently pass as verified zero", function()
    local s = base(); s.cash = {status = "unavailable", value = 0}
    local rows = BankValidation.evaluate(s)
    assertTrue(outcome(rows, "CASH_UNKNOWN_NOT_ZERO", "FAIL"))
    assertTrue(outcome(rows, "CASH_FINITE", "UNAVAILABLE"))
end)

test("animal quote math and unknown units are checked separately", function()
    local s = base()
    s.animals.items = {{id = "cow", count = 5, unitValue = 100, value = 600, healthPercent = 101, ageMonths = 24}}
    s.animals.totalCount, s.animals.totalValue = 6, 600
    local rows = BankValidation.evaluate(s)
    assertTrue(outcome(rows, "ANIMAL_QUOTE_PRODUCT", "FAIL"))
    assertTrue(outcome(rows, "ANIMAL_HEALTH_RANGE", "FAIL"))
    assertTrue(outcome(rows, "ANIMAL_COUNT_SUM", "FAIL"))
    assertTrue(outcome(rows, "ANIMAL_UNVERIFIED_UNITS", "FAIL"))
end)

test("ledger arithmetic distinguishes disclosed gaps from false reconciliation", function()
    local s = base()
    s.history.current = {year = 1, month = 1, openingCash = 100, closingCash = 500,
        operatingRevenue = 20, operatingExpense = 0, interestExpense = 0, capitalInflow = 0, capitalOutflow = 0,
        financingInflow = 0, financingOutflow = 0, unclassifiedInflow = 0, unclassifiedOutflow = 0, reconciled = false}
    assertTrue(outcome(BankValidation.evaluate(s), "LEDGER_CASH_EQUATION", "WARN"))
    s.history.current.reconciled = true
    assertTrue(outcome(BankValidation.evaluate(s), "LEDGER_CASH_EQUATION", "FAIL"))
end)

test("fabricated eligible result without dated history fails independent model gate", function()
    local s = base()
    s.underwriting.assessment = {status = "available", score = 90, band = "favorable", components = {}}
    local rows = BankValidation.evaluate(s)
    assertTrue(outcome(rows, "MODEL_EVIDENCE_GATE", "FAIL"))
    assertTrue(outcome(rows, "SCORE_SUM", "FAIL"))
end)

test("snapshot delta logs added and removed assets without inventing a sale amount", function()
    local before, after = base(), base()
    after.equipment.items[1].id = "C"
    local rows = BankValidation.evaluate(after, before)
    assertTrue(outcome(rows, "DELTA_EQUIPMENT", "WARN"))
    for _, row in ipairs(rows) do if row.id == "AUTO_DELTA_EQUIPMENT" then assertEqual(row.evidence.salePrice, nil) end end
end)

test("report pages verify physical line limits but cannot prove visual clipping", function()
    local outcomes = {}
    BankValidation.pages({{title = "Page", text = string.rep("line\n", 14)}}, 14, function(id, result) outcomes[id] = result end)
    assertEqual(outcomes.AUTO_GUI_PAGE_LINES, "FAIL")
    assertEqual(outcomes.AUTO_GUI_REPORT_PAGES, "FAIL")
end)

test("unknown farm identity is unavailable while a malformed positive fraction is a failure", function()
    local s = base(); s.farm.id = nil
    assertTrue(outcome(BankValidation.evaluate(s), "FARM_ID", "UNAVAILABLE"))
    s.farm.id = 2.5
    assertTrue(outcome(BankValidation.evaluate(s), "FARM_ID", "FAIL"))
end)

test("native category delta comparison discloses sign uncertainty and catches magnitude mismatches", function()
    local before, after = base(), base()
    local function period(inflow)
        return {year = 0, month = 2, categories = {soldMilk = {inflow = inflow, outflow = 0}}, openingCash = 100,
            closingCash = 100 + inflow, operatingRevenue = inflow, operatingExpense = 0, interestExpense = 0,
            capitalInflow = 0, capitalOutflow = 0, financingInflow = 0, financingOutflow = 0,
            unclassifiedInflow = 0, unclassifiedOutflow = 0, complete = false, reconciled = true}
    end
    before.history.current, after.history.current = period(10), period(30)
    before.finance.records = {{bucketKind = "currentCandidate", categoryKey = "soldMilk", rawSignedValue = -10}}
    after.finance.records = {{bucketKind = "currentCandidate", categoryKey = "soldMilk", rawSignedValue = -30}}
    local rows = BankValidation.evaluate(after, before)
    assertTrue(outcome(rows, "NATIVE_FINANCE_DELTA_MAGNITUDE", "PASS"))
    after.finance.records[1].rawSignedValue = -50
    assertTrue(outcome(BankValidation.evaluate(after, before), "NATIVE_FINANCE_DELTA_MAGNITUDE", "WARN"))
end)
