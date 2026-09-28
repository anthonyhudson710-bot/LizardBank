-- Safe synthetic checks in the actual Lua host. No mission access, RNG, files,
-- native hooks or economic mutations. Never evidence of an in-game seasonal run.
BankValidationProbes = {}
function BankValidationProbes.run()
    if BankDiagnostics == nil or not BankDiagnostics.isEnabled() then return end
    return BankDiagnostics.withSynthetic(function()
        local function verify(id, condition, data)
            BankDiagnostics.check(id, condition and "PASS" or "FAIL", data or {})
        end
        local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.00001 end
        local function fixture()
            local snapshot = {farm = {id = 7}, cash = {status = "available", value = 2000},
                debt = {status = "available", value = 10000}, land = {status = "available", totalValue = 40000}}
            local history = {farmId = 7, currentYear = 3, currentMonth = 1, materialGaps = {}, periods = {}}
            for month = 1, 12 do
                history.periods[month] = {year = 2, month = month, complete = true, reconciled = true,
                    operatingRevenue = 1000, operatingExpense = 800, interestExpense = 100,
                    capitalInflow = 0, capitalOutflow = 0, financingInflow = 0, financingOutflow = 0,
                    unclassifiedInflow = 0, unclassifiedOutflow = 0}
            end
            return snapshot, history
        end
        BankDiagnostics.emit("probe.begin", {scope = "synthetic_math_and_ledger_only", nativeRuntimeCoverage = false})
        local snapshot, history = fixture()
        local baseline = BankUnderwriting.prepare(snapshot, history, {mode = "standard"})
        verify("MODEL_KNOWN_ANSWER", baseline.assessment.score == 62 and near(baseline.forecast.annualCashBeforePrincipal, 1200),
            {score = baseline.assessment.score, expectedScore = 62, annual = baseline.forecast.annualCashBeforePrincipal, expectedAnnual = 1200})
        local lenient = BankUnderwriting.prepare(snapshot, history, {mode = "lenient"})
        local strict = BankUnderwriting.prepare(snapshot, history, {mode = "strict"})
        verify("POLICY_MONOTONIC", lenient.assessment.score >= baseline.assessment.score and baseline.assessment.score >= strict.assessment.score)
        snapshot.land.totalValue = 1e12
        history.periods[1].capitalInflow, history.periods[1].financingInflow = 1e9, 1e9
        local changed = BankUnderwriting.prepare(snapshot, history)
        verify("ASSET_BORROWING_NO_SCORE_INFLATION", changed.assessment.score == baseline.assessment.score and changed.forecast.annualCashBeforePrincipal == baseline.forecast.annualCashBeforePrincipal)
        local variations = {
            {"NEW_SAVE", function(_, h) h.periods = {} end},
            {"PARTIAL_PERIOD", function(_, h) h.periods[1].complete = false end},
            {"RECONCILIATION_FAILURE", function(_, h) h.periods[1].reconciled = false end},
            {"UNKNOWN_OFFSETTING_FLOWS", function(_, h) h.periods[1].unclassifiedInflow = 99; h.periods[1].unclassifiedOutflow = 99 end},
            {"MISSING_COST", function(_, h) h.periods[1].operatingExpense = nil end},
            {"NONFINITE", function(_, h) h.periods[1].operatingRevenue = math.huge end},
            {"WRONG_FARM", function(_, h) h.farmId = 8 end},
            {"MATERIAL_GAP", function(_, h) h.materialGaps = {"fixture gap"} end},
            {"DUPLICATE_PERIOD", function(_, h) h.periods[13] = h.periods[1] end}
        }
        for _, case in ipairs(variations) do
            local s, h = fixture(); case[2](s, h)
            local result = BankUnderwriting.prepare(s, h)
            verify(case[1] .. "_WITHHOLDS", result.assessment.score == nil and result.forecast.status ~= "available",
                {score = result.assessment.score, forecast = result.forecast.status})
        end
        local ledger = BankHistory.new(7, {day = 1, period = 1, dayTime = 0, daysPerPeriod = 1}, 1000)
        BankHistory.record(ledger, ledger.last, 1000, 1300, "fixture_sale", "operating")
        BankHistory.record(ledger, ledger.last, 1300, 1200, "fixture_input", "operating")
        BankHistory.record(ledger, ledger.last, 1200, 2200, "fixture_loan", "financing")
        verify("GROSS_FLOWS", ledger.current.operatingRevenue == 300 and ledger.current.operatingExpense == 100 and ledger.current.financingInflow == 1000 and ledger.balance == 2200)
        verify("FIRST_PERIOD_PARTIAL", ledger.current.complete == false and #ledger.periods == 0)
        BankHistory.observe(ledger, {day = 2, period = 2, dayTime = 0, daysPerPeriod = 1}, 2200)
        verify("BOUNDARY", #ledger.periods == 1 and ledger.current.month == 2 and ledger.current.complete == true)
        local restored, matches = BankHistory.resume(ledger, 7, ledger.last, 2200)
        verify("RESUME_MATCH", matches == true and restored ~= ledger and restored.balance == 2200)
        local broken, accepted = BankHistory.resume(ledger, 7, ledger.last, 2201)
        verify("RESUME_MISMATCH", accepted == false and broken.current.complete == false and #broken.periods == 0)
        BankHistory.observe(ledger, {day = 1, period = 1, dayTime = 0, daysPerPeriod = 1}, 2200)
        verify("ROLLBACK", #ledger.periods == 0 and ledger.current.complete == false)
        BankDiagnostics.emit("probe.end", {scope = "synthetic_math_and_ledger_only", nativeRuntimeCoverage = false})
    end)
end
