-- Pure, versioned cash-flow assessment. No game state, persistence or money changes.
-- Amounts and calendar slots must be normalized by the collector/tracker first.
BankUnderwriting = {}

local VERSION = "1.0.0"
local AMOUNTS = {"operatingRevenue", "operatingExpense", "interestExpense", "capitalInflow", "capitalOutflow", "financingInflow", "financingOutflow", "unclassifiedInflow", "unclassifiedOutflow"}
local MODES = {
    lenient = {marginLow = 0.02, marginStrong = 0.15, bufferLow = 0.5, bufferStrong = 3, interestLow = 1, interestStrong = 2, debtStrong = 2, debtHigh = 8},
    standard = {marginLow = 0.05, marginStrong = 0.20, bufferLow = 1, bufferStrong = 4, interestLow = 1.25, interestStrong = 3, debtStrong = 1.5, debtHigh = 6},
    strict = {marginLow = 0.08, marginStrong = 0.25, bufferLow = 2, bufferStrong = 6, interestLow = 1.5, interestStrong = 4, debtStrong = 1, debtHigh = 4}
}

local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function nonnegative(value)
    return finite(value) and value >= 0
end

local function tableOrEmpty(value)
    return type(value) == "table" and value or {}
end

local function copyScalars(value)
    local result = {}
    for key, item in pairs(value) do
        if type(item) == "number" or type(item) == "string" or type(item) == "boolean" then result[key] = item end
    end
    return result
end

local function dateIndex(year, month)
    if nonnegative(year) and year == math.floor(year) and year <= 1000000
        and finite(month) and month == math.floor(month) and month >= 1 and month <= 12 then
        return year * 12 + month - 1
    end
    return nil
end

local function dateFromIndex(index)
    return math.floor(index / 12), index % 12 + 1
end

local function reason(list, code, detail)
    list[#list + 1] = {code = code, detail = detail}
end

local function availableFigure(section, key, allowNegative)
    section = tableOrEmpty(section)
    local value = section[key]
    if section.status == "available" and finite(value) and (allowNegative or value >= 0) then return value end
    return nil
end

local function normalizedPeriod(raw)
    if type(raw) ~= "table" then return nil end
    local index = dateIndex(raw.year, raw.month)
    if index == nil then return nil end
    local period = {year = raw.year, month = raw.month, index = index, complete = raw.complete == true,
        reconciled = raw.reconciled == true, validAmounts = true}
    for _, key in ipairs(AMOUNTS) do
        if nonnegative(raw[key]) then period[key] = raw[key] else period.validAmounts = false end
    end
    return period
end

local function newTotals()
    local result = {}
    for _, key in ipairs(AMOUNTS) do result[key] = 0 end
    return result
end

local function finishTotals(totals)
    for _, key in ipairs(AMOUNTS) do if not finite(totals[key]) then return false end end
    totals.operatingCashBeforeInterest = totals.operatingRevenue - totals.operatingExpense
    totals.cashBeforePrincipal = totals.operatingCashBeforeInterest - totals.interestExpense
    totals.classifiedNetCash = totals.cashBeforePrincipal + totals.capitalInflow - totals.capitalOutflow
        + totals.financingInflow - totals.financingOutflow
    for _, key in ipairs({"operatingCashBeforeInterest", "cashBeforePrincipal", "classifiedNetCash"}) do
        if not finite(totals[key]) then return false end
    end
    return true
end

local function historyEvidence(history, withheld)
    local evidence = {status = "unavailable", periods = {}, observedPeriodCount = 0, completePeriodCount = 0,
        requiredPeriodCount = 12, source = "normalized completed monthly ledger", seasonalityStatus = "insufficient_evidence"}
    local currentIndex = dateIndex(history.currentYear, history.currentMonth)
    if currentIndex == nil then
        reason(withheld, "CURRENT_CALENDAR_UNAVAILABLE", "The current year and seasonal month have not been verified.")
        return evidence
    end
    evidence.currentYear, evidence.currentMonth = history.currentYear, history.currentMonth
    if type(history.periods) ~= "table" then
        reason(withheld, "HISTORY_UNAVAILABLE", "No normalized completed monthly history is available.")
        return evidence
    end
    local indexed, malformed, duplicate = {}, false, false
    for _, raw in pairs(history.periods) do
        local period = normalizedPeriod(raw)
        if period == nil then
            malformed = true
        elseif indexed[period.index] ~= nil then
            -- Neither conflicting row wins based on enumeration order.
            indexed[period.index] = {year = period.year, month = period.month, index = period.index,
                duplicate = true, complete = false, reconciled = false, validAmounts = false}
            if period.index >= currentIndex - 12 and period.index < currentIndex then duplicate = true end
        else
            indexed[period.index] = period
        end
    end
    local totals, validObserved = newTotals(), 0
    local missing, incomplete, invalid, unclassified = false, false, false, false
    for index = currentIndex - 12, currentIndex - 1 do
        local period = indexed[index]
        if period == nil then
            local year, month = dateFromIndex(index)
            evidence.periods[#evidence.periods + 1] = {year = year, month = month, status = "missing"}
            missing = true
        else
            local row = copyScalars(period)
            row.status = "partial"
            evidence.periods[#evidence.periods + 1] = row
            evidence.observedPeriodCount = evidence.observedPeriodCount + 1
            if period.validAmounts and not period.duplicate then
                validObserved = validObserved + 1
                for _, key in ipairs(AMOUNTS) do totals[key] = totals[key] + period[key] end
            else invalid = true end
            if not period.complete or not period.reconciled then incomplete = true end
            if (period.unclassifiedInflow or 0) > 0 or (period.unclassifiedOutflow or 0) > 0 then unclassified = true end
            if period.validAmounts and period.complete and period.reconciled and not period.duplicate
                and period.unclassifiedInflow == 0 and period.unclassifiedOutflow == 0 then
                evidence.completePeriodCount = evidence.completePeriodCount + 1
                row.status = "available"
            end
        end
    end
    if malformed then reason(withheld, "MALFORMED_HISTORY", "At least one history record has no valid monthly date.") end
    if duplicate then reason(withheld, "DUPLICATE_PERIOD", "Duplicate dated records must be reconciled before assessment.") end
    if missing then reason(withheld, "INSUFFICIENT_HISTORY", "Twelve consecutive completed monthly periods ending before the current month are required.") end
    if incomplete then reason(withheld, "INCOMPLETE_PERIOD", "A period is partially observed or has not reconciled with recorded cash movements.") end
    if invalid then reason(withheld, "INVALID_PERIOD_AMOUNTS", "Missing, negative, nonfinite or duplicate category amounts cannot be assumed zero.") end
    if unclassified then reason(withheld, "UNCLASSIFIED_ACTIVITY", "Unclassified money movements prevent reliable operating cash analysis.") end
    if validObserved > 0 and finishTotals(totals) then
        evidence.totals = totals
        evidence.status = "partial"
    elseif validObserved > 0 then
        reason(withheld, "HISTORY_OVERFLOW", "Historical totals exceed the supported numeric range.")
    end
    evidence.complete = evidence.completePeriodCount == 12 and not malformed and not duplicate and evidence.totals ~= nil
    if evidence.complete then
        evidence.status = "available"
        evidence.seasonalityStatus = "one_cycle_baseline"
    end
    return evidence
end

local function seasonalForecast(evidence)
    local result = {status = "insufficient_evidence", periods = {}, method = "repeat_latest_completed_same_seasonal_month",
        confidence = "not_established", cashBasis = "operating cash before principal payments and capital spending"}
    if not evidence.complete then return result end
    local byMonth = {}
    for _, period in ipairs(evidence.periods) do byMonth[period.month] = period end
    local currentIndex = dateIndex(evidence.currentYear, evidence.currentMonth)
    for offset = 1, 12 do
        local year, month = dateFromIndex(currentIndex + offset)
        local baseline = byMonth[month]
        result.periods[#result.periods + 1] = {
            year = year, month = month, sourceYear = baseline.year, sourceMonth = baseline.month,
            operatingRevenue = baseline.operatingRevenue, operatingExpense = baseline.operatingExpense,
            interestExpense = baseline.interestExpense,
            cashBeforePrincipal = baseline.operatingRevenue - baseline.operatingExpense - baseline.interestExpense
        }
    end
    result.status = "available"
    result.confidence = "limited_single_cycle"
    result.annualOperatingRevenue = evidence.totals.operatingRevenue
    result.annualOperatingExpense = evidence.totals.operatingExpense
    result.annualInterestExpense = evidence.totals.interestExpense
    result.annualCashBeforePrincipal = evidence.totals.cashBeforePrincipal
    result.excludesCurrentPartialMonth = true
    result.assumptions = {
        "This is a repeat-of-observed-month scenario, not a prediction with established statistical confidence.",
        "Operating activity, sale timing, prices, costs and interest repeat the latest observed matching seasonal month.",
        "The current partially elapsed month, capital transactions and financing movements are not forecast.",
        "No crop yield, stock liquidation, asset appreciation or historical repayment behavior is invented.",
        "No closing cash balance is projected because the intervening partial month and principal schedule are unknown."
    }
    return result
end

local function collateral(snapshot)
    local result = {status = "partial", includedInScore = false, source = "existing partial asset quotes", components = {}}
    local fields = {{"land", "totalValue"}, {"equipment", "ownedValue"}, {"buildings", "totalValue"}}
    local total, count = 0, 0
    for _, pair in ipairs(fields) do
        local source = tableOrEmpty(snapshot[pair[1]])
        if (source.status == "available" or source.status == "partial") and nonnegative(source[pair[2]]) then
            result.components[pair[1]] = source[pair[2]]
            total, count = total + source[pair[2]], count + 1
        end
    end
    if count > 0 and finite(total) then result.knownAssetQuotes = total end
    local debt = availableFigure(snapshot.debt, "value", false)
    if debt ~= nil and result.knownAssetQuotes ~= nil and result.knownAssetQuotes > 0 then
        local ratio = debt / result.knownAssetQuotes
        if finite(ratio) then result.nativeDebtToKnownAssetQuotes = ratio end
    end
    result.limitations = "Partial game quotes are not independently appraised collateral or realizable net sale proceeds. Inventory and separate animal references are not added; liens and external debt are not verified."
    return result
end

local function rising(value, low, strong)
    return math.max(0, math.min(1, (value - low) / (strong - low)))
end

local function component(assessment, name, value, status, weight, factor, formula, low, strong)
    local item = {name = name, value = value, status = status, weight = weight, formula = formula,
        weakThreshold = low, strongThreshold = strong}
    if factor ~= nil then item.points = weight * factor end
    assessment.components[#assessment.components + 1] = item
    return item
end

function BankUnderwriting.prepare(snapshot, history, options)
    snapshot, history, options = tableOrEmpty(snapshot), tableOrEmpty(history), tableOrEmpty(options)
    local mode = MODES[options.mode] and options.mode or "standard"
    local thresholds = MODES[mode]
    local assessment = {status = "insufficient_evidence", withheldReasons = {}, reasons = {}, components = {},
        scoreScale = "internal simulation eligibility 0..100", thresholds = copyScalars(thresholds),
        scope = "native_game_cash_and_debt", provisional = options.externalLiabilitiesKnown ~= true,
        principalCoverage = {status = "unavailable", reason = "No contractual principal repayment schedule is supplied; this is not DSCR."},
        profitability = {status = "unavailable", reason = "Cash movements do not establish accrual profit, depreciation or inventory cost of sales."}}
    local result = {modelVersion = VERSION, mode = mode, assessment = assessment, collateral = collateral(snapshot),
        assumptions = {
            "Assessment covers the recorded farm's native game cash and debt only; it is neither a real credit score nor lending approval.",
            "Capital gains, new borrowing, land sales and equipment sales are excluded from operating cash generation.",
            "Unknown external financing and principal schedules are not modeled; verify them before making a lending decision.",
            "A new or inactive farm receives insufficient evidence, never an invented poor payment history."
        }}
    local withheld = assessment.withheldReasons
    local farmId = tableOrEmpty(snapshot.farm).id
    local farmIdentityUnavailable = not finite(history.farmId) or history.farmId <= 0
        or history.farmId ~= math.floor(history.farmId) or not finite(farmId) or farmId <= 0 or farmId ~= math.floor(farmId)
    local farmMismatch = not farmIdentityUnavailable and history.farmId ~= farmId
    local forecastBlock
    if farmIdentityUnavailable then
        forecastBlock = "HISTORY_FARM_UNAVAILABLE"
        reason(withheld, forecastBlock, "Valid matching farm identities are required for the current snapshot and financial history.")
    elseif farmMismatch then
        forecastBlock = "HISTORY_FARM_MISMATCH"
        reason(withheld, "HISTORY_FARM_MISMATCH", "The financial history does not belong to the currently reported farm.")
    end
    if options.materialExternalLiabilityUnknown == true then
        reason(withheld, "MATERIAL_EXTERNAL_LIABILITY_UNKNOWN", "A material external liability is suspected but its balance or payment obligations are unavailable.")
    end
    if assessment.provisional then
        reason(assessment.reasons, "EXTERNAL_LIABILITIES_UNVERIFIED", "Any score is provisional for native game data; completeness of external liabilities is unverified.")
    end
    local evidence = historyEvidence(history, withheld)
    result.history = evidence
    result.forecast = seasonalForecast(evidence)
    if type(history.materialGaps) ~= "table" then
        forecastBlock = forecastBlock or "MATERIAL_COVERAGE_UNKNOWN"
        reason(withheld, "MATERIAL_COVERAGE_UNKNOWN", "Financial data coverage has not been explicitly checked.")
    else
        local gaps = {}
        for _, gap in pairs(history.materialGaps) do
            gaps[#gaps + 1] = type(gap) == "string" and gap or "An unresolved material financial data gap exists."
        end
        table.sort(gaps)
        for _, gap in ipairs(gaps) do
            forecastBlock = forecastBlock or "MATERIAL_DATA_GAP"
            reason(withheld, "MATERIAL_DATA_GAP", gap)
        end
    end
    if forecastBlock ~= nil then
        result.forecast = seasonalForecast({complete = false})
        result.forecast.withheldReason = forecastBlock
    end
    local cash = availableFigure(snapshot.cash, "value", true)
    local debt = availableFigure(snapshot.debt, "value", false)
    assessment.cash, assessment.nativeDebt = cash, debt
    if cash == nil then reason(withheld, "CASH_UNAVAILABLE", "Current cash is not verified.") end
    if debt == nil then reason(withheld, "NATIVE_DEBT_UNAVAILABLE", "Current native debt is not verified.") end
    local totals = evidence.totals
    if totals == nil then return result end
    if totals.operatingRevenue == 0 and totals.operatingExpense == 0 and totals.interestExpense == 0 then
        reason(withheld, "NO_OPERATING_ACTIVITY", "No operating activity is recorded; startup or dormant status is not a failed credit grade.")
    end
    if debt ~= nil and debt > 0 and totals.interestExpense == 0 then
        reason(withheld, "NATIVE_INTEREST_UNOBSERVED", "Native debt exists but its interest cost has not been observed in the assessment window.")
    end
    if #withheld > 0 then return result end

    local margin, marginFactor
    if totals.operatingRevenue > 0 then
        margin = totals.operatingCashBeforeInterest / totals.operatingRevenue
        marginFactor = rising(margin, thresholds.marginLow, thresholds.marginStrong)
    else marginFactor = 0 end
    component(assessment, "operatingCashMargin", margin, margin ~= nil and "available" or "no_revenue", 35, marginFactor,
        "(operating revenue - operating expense excluding interest) / operating revenue", thresholds.marginLow, thresholds.marginStrong)

    local monthlyCost = totals.operatingExpense / 12 + totals.interestExpense / 12
    local buffer, bufferFactor, bufferStatus
    if monthlyCost > 0 then
        buffer, bufferStatus = cash / monthlyCost, "available"
        bufferFactor = rising(buffer, thresholds.bufferLow, thresholds.bufferStrong)
    else
        bufferStatus = "no_observed_cash_cost"
        bufferFactor = cash >= 0 and 1 or 0
    end
    component(assessment, "cashBufferMonths", buffer, bufferStatus, 30, bufferFactor,
        "current cash / ((12-month operating expense + interest) / 12)", thresholds.bufferLow, thresholds.bufferStrong)

    local interestCoverage, interestFactor, interestStatus
    if totals.interestExpense > 0 then
        interestCoverage = totals.operatingCashBeforeInterest / totals.interestExpense
        interestStatus = "available"
        interestFactor = rising(interestCoverage, thresholds.interestLow, thresholds.interestStrong)
    else interestStatus, interestFactor = "no_native_interest_obligation_observed", 1 end
    component(assessment, "nativeInterestCoverage", interestCoverage, interestStatus, 20, interestFactor,
        "operating cash before interest / observed native interest expense (excludes principal)", thresholds.interestLow, thresholds.interestStrong)

    local leverage, leverageFactor, leverageStatus
    if debt == 0 then
        leverage, leverageFactor, leverageStatus = 0, 1, "no_native_debt"
    elseif totals.operatingCashBeforeInterest > 0 then
        leverage = debt / totals.operatingCashBeforeInterest
        leverageStatus = "available"
        leverageFactor = 1 - rising(leverage, thresholds.debtStrong, thresholds.debtHigh)
    else leverageStatus, leverageFactor = "no_positive_operating_cash", 0 end
    component(assessment, "nativeDebtToOperatingCash", leverage, leverageStatus, 15, leverageFactor,
        "current native debt / 12-month operating cash before interest", thresholds.debtHigh, thresholds.debtStrong)

    local score = 0
    for _, item in ipairs(assessment.components) do
        if (item.value ~= nil and not finite(item.value)) or not finite(item.points) then
            item.value, item.points = nil, nil
            reason(withheld, "ASSESSMENT_OVERFLOW", "A ratio exceeds the supported numeric range.")
        else score = score + item.points end
    end
    if #withheld > 0 then return result end
    assessment.status = "available"
    assessment.score = math.floor(score + 0.5)
    assessment.band = assessment.score >= 75 and "favorable" or (assessment.score >= 50 and "guarded" or "strained")
    assessment.cashBeforePrincipal = totals.cashBeforePrincipal
    assessment.operatingCashBeforeInterest = totals.operatingCashBeforeInterest
    reason(assessment.reasons, "COMPLETE_OBSERVED_CYCLE", "Assessment uses twelve completed, reconciled monthly periods with no unclassified movements.")
    reason(assessment.reasons, "POLICY_MODE", "Thresholds are the explicit " .. mode .. " simulation policy; they are not calibrated default probabilities.")
    if totals.cashBeforePrincipal <= 0 then reason(assessment.reasons, "OPERATING_CASH_SHORTFALL", "Recorded operating cash after interest does not leave positive cash for principal payments.") end
    if cash < 0 then reason(assessment.reasons, "NEGATIVE_CASH", "Current cash is below zero.") end
    if debt > 0 and interestCoverage ~= nil and interestCoverage < 1 then reason(assessment.reasons, "INTEREST_NOT_COVERED", "Recorded operating cash before interest is less than recorded interest expense.") end
    reason(assessment.reasons, "PRINCIPAL_CAPACITY_UNPROVEN", "Principal repayment capacity is not established without a repayment schedule and verified additional obligations.")
    return result
end
