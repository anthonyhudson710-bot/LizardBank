-- Presentation of retained records, observation evidence and model results.
BankFinancialReport = {}
BankFinancialReport.ENGLISH = {
    lb_finance = "Retained game financial records",
    lb_history = "Lizard Bank observed history",
    lb_forecast = "Seasonal cash scenario",
    lb_credit = "Creditworthiness evidence",
    lb_policy = "Policy",
    lb_policyButton = "Policy: %s",
    lb_mode_standard = "Standard",
    lb_mode_strict = "Strict",
    lb_mode_lenient = "Lenient",
    lb_model = "Model %s | Policy: %s",
    lb_policyMeaning = "Policy changes score thresholds only. Evidence requirements stay the same.",
    lb_score = "Provisional native-data score: %s / 100 | %s",
    lb_scoreScope = "Internal simulation score; not a credit-bureau score, default probability or loan approval.",
    lb_insufficient = "Insufficient history or unresolved evidence; no score assigned.",
    lb_evidenceCount = "Completed, reconciled periods in the latest cycle: %s / 12",
    lb_creditScope = "External liabilities are unverified. No principal repayment schedule is available.",
    lb_noDscr = "Actual accounting profit and debt-service coverage are unavailable.",
    lb_cashGeneration = "Observed operating cash before interest: %s",
    lb_cashPrincipal = "Observed cash after interest, before principal: %s",
    lb_component = "%s: %s | Points: %s / %s",
    lb_componentThreshold = "Weak threshold: %s | Strong threshold: %s",
    lb_operatingCashMargin = "Operating cash margin",
    lb_cashBufferMonths = "Cash buffer (months of observed costs)",
    lb_nativeInterestCoverage = "Native interest coverage (times)",
    lb_nativeDebtToOperatingCash = "Native debt / operating cash (times)",
    lb_band_favorable = "Favorable",
    lb_band_guarded = "Guarded",
    lb_band_strained = "Strained",
    lb_reason = "%s: %s",
    lb_collateral = "Known asset quotes, separate from repayment score: %s",
    lb_collateralWarning = "Partial quotes exclude unverified liens and external debt; assets do not add score points.",
    lb_nativeFinanceWarning = "Native history dates, order, padding and retained window are unverified in FS25.",
    lb_nativeFinanceMeaning = "Raw game records; sign/category semantics are unverified. Treatments below are bank policy.",
    lb_nativeNotTotals = "These records are not dated cash-flow totals and never establish complete observation.",
    lb_financeCount = "Readable figures: %s | Unavailable: %s | Unclassified: %s",
    lb_financeSource = "Source: %s",
    lb_nativeRow = "%s | Native slot %s | %s",
    lb_nativeAmount = "Raw amount: %s | Policy treatment: %s",
    lb_nativeCurrent = "Current candidate",
    lb_nativeHistory = "Retained candidate",
    lb_noNativeFinance = "No readable retained records. Past activity is not reconstructed.",
    lb_class_operating = "Operating",
    lb_class_capital = "Asset transaction",
    lb_class_financing = "Financing",
    lb_class_interest = "Native interest",
    lb_class_unclassified = "Unclassified",
    lb_historyBasis = "Local cycles start at installation; period 1-12 follows the game's seasonal order.",
    lb_historyNotYear = "Cycle numbers are tracking labels, not calendar years. Native archive slots are not imported.",
    lb_historyLimit = "History retains up to %s completed or closed periods per farm.",
    lb_historySave = "History saving is attempted during the game save; reload checks matching evidence.",
    lb_persistence = "Persistence capability: %s",
    lb_persistenceCandidate = "Save integration present; verify in Windows",
    lb_period = "Local cycle %s | Native period %s | %s",
    lb_complete = "Complete and reconciled",
    lb_partialPeriod = "Partial / insufficient evidence",
    lb_currentPeriod = "Current period in progress",
    lb_periodRange = "Observed game days %s to %s | Events: %s",
    lb_periodCash = "Opening cash: %s | Closing observed cash: %s",
    lb_operatingTotals = "Operating receipts: %s | Operating payments: %s",
    lb_interestTotal = "Interest paid: %s",
    lb_capitalTotals = "Asset receipts: %s | Asset payments: %s",
    lb_financingTotals = "Financing receipts: %s | Principal/financing payments: %s",
    lb_unknownTotals = "Unclassified receipts: %s | Unclassified payments: %s",
    lb_categoryTotals = "%s | In: %s | Out: %s",
    lb_historyMissing = "No observed history yet. New and existing saves start with a partial period.",
    lb_historyUnclassified = "Unclassified movements and reconciliation gaps prevent scoring; zero is never substituted.",
    lb_forecastMissing = "Insufficient history: a full comparable, reconciled seasonal cycle is required.",
    lb_forecastMethod = "Scenario repeats the latest observed matching seasonal period; confidence is limited to one cycle.",
    lb_forecastScope = "Next 12 full periods only. Current partial period, capital spending and financing are excluded.",
    lb_forecastNoBalance = "Cash before principal is not a safe loan payment or a forecast closing bank balance.",
    lb_forecastSource = "Baseline: local cycle %s, native period %s",
    lb_forecastNet = "Scenario cash after interest, before principal: %s",
    lb_forecastAnnual = "Scenario total before principal: %s"
}

local function number(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function BankFinancialReport.sections(snapshot, t, money, known)
    if BankDiagnostics ~= nil and BankDiagnostics.isEnabled() then
        BankDiagnostics.emit("report.finance.begin", {nativeStatus = snapshot.finance and snapshot.finance.status,
            historyFarmId = snapshot.history and snapshot.history.farmId,
            modelStatus = snapshot.underwriting and snapshot.underwriting.assessment and snapshot.underwriting.assessment.status})
    end
    local sections = {}
    local function section(title, lines) sections[#sections + 1] = {title = title, lines = lines} end
    local function decimal(value)
        return number(value) and string.format("%.2f", value) or t("lb_unavailable")
    end
    local model, history, finance = snapshot.underwriting or {}, snapshot.history or {}, snapshot.finance or {}
    local assessment, evidence = model.assessment or {}, model.history or {}
    local mode = model.mode or history.mode or "standard"
    local credit = {t("lb_model", known(model.modelVersion), t("lb_mode_" .. mode)),
        t("lb_evidenceCount", known(evidence.completePeriodCount)), t("lb_policyMeaning"), ""}
    if assessment.status == "available" and number(assessment.score) then
        credit[#credit + 1] = t("lb_score", known(assessment.score), t("lb_band_" .. (assessment.band or "guarded")))
    else credit[#credit + 1] = t("lb_insufficient") end
    credit[#credit + 1] = t("lb_scoreScope")
    credit[#credit + 1] = t("lb_creditScope")
    credit[#credit + 1] = t("lb_noDscr")
    local totals = evidence.totals or {}
    credit[#credit + 1] = t("lb_cashGeneration", money(totals.operatingCashBeforeInterest))
    credit[#credit + 1] = t("lb_cashPrincipal", money(totals.cashBeforePrincipal))
    for _, component in ipairs(assessment.components or {}) do
        credit[#credit + 1] = ""
        credit[#credit + 1] = t("lb_component", t("lb_" .. component.name), decimal(component.value), decimal(component.points), known(component.weight))
        credit[#credit + 1] = known(component.formula)
        credit[#credit + 1] = t("lb_componentThreshold", decimal(component.weakThreshold), decimal(component.strongThreshold))
        if component.status ~= "available" then credit[#credit + 1] = known(component.status) end
    end
    for _, list in ipairs({assessment.withheldReasons or {}, assessment.reasons or {}}) do
        for _, reason in ipairs(list) do
            credit[#credit + 1] = ""
            credit[#credit + 1] = t("lb_reason", known(reason.code), known(reason.detail))
        end
    end
    credit[#credit + 1] = ""
    credit[#credit + 1] = t("lb_collateral", money((model.collateral or {}).knownAssetQuotes))
    credit[#credit + 1] = t("lb_collateralWarning")
    section("lb_credit", credit)

    local retained = {t("lb_nativeFinanceWarning"), t("lb_nativeFinanceMeaning"), t("lb_nativeNotTotals"),
        t("lb_financeSource", known(finance.source)),
        t("lb_financeCount", known(finance.knownValueCount), known(finance.unknownValueCount), known(finance.unclassifiedCount)), ""}
    if #(finance.records or {}) == 0 then retained[#retained + 1] = t("lb_noNativeFinance") end
    for _, record in ipairs(finance.records or {}) do
        retained[#retained + 1] = t("lb_nativeRow", t(record.bucketKind == "currentCandidate" and "lb_nativeCurrent" or "lb_nativeHistory"),
            known(record.periodKey), known(record.label or record.categoryKey))
        retained[#retained + 1] = t("lb_nativeAmount", money(record.rawSignedValue), t("lb_class_" .. (record.classification or "unclassified")))
        retained[#retained + 1] = ""
    end
    section("lb_finance", retained)

    local tracked = {t("lb_historyBasis"), t("lb_historyNotYear"), t("lb_historyLimit", known(history.retainedLimit)),
        t("lb_historySave"), t("lb_persistence", t(history.persistence == "save_callback_candidate" and "lb_persistenceCandidate" or "lb_unavailable")), t("lb_historyUnclassified"), ""}
    for _, gap in ipairs(history.materialGaps or {}) do tracked[#tracked + 1] = known(gap) end
    if history.loadNote then tracked[#tracked + 1] = known(history.loadNote) end
    local periods = {}
    for _, period in ipairs(history.periods or {}) do periods[#periods + 1] = period end
    if history.current then periods[#periods + 1] = history.current end
    if #periods == 0 then tracked[#tracked + 1] = t("lb_historyMissing") end
    for _, p in ipairs(periods) do
        local label = p == history.current and "lb_currentPeriod" or (p.complete and p.reconciled and "lb_complete" or "lb_partialPeriod")
        tracked[#tracked + 1] = t("lb_period", known(p.year), known(p.month), t(label))
        tracked[#tracked + 1] = t("lb_periodRange", known(p.startDay), known(p.endDay or (history.anchor or {}).day), known(p.events))
        tracked[#tracked + 1] = t("lb_periodCash", money(p.openingCash), money(p.closingCash))
        tracked[#tracked + 1] = t("lb_operatingTotals", money(p.operatingRevenue), money(p.operatingExpense))
        tracked[#tracked + 1] = t("lb_interestTotal", money(p.interestExpense))
        tracked[#tracked + 1] = t("lb_capitalTotals", money(p.capitalInflow), money(p.capitalOutflow))
        tracked[#tracked + 1] = t("lb_financingTotals", money(p.financingInflow), money(p.financingOutflow))
        tracked[#tracked + 1] = t("lb_unknownTotals", money(p.unclassifiedInflow), money(p.unclassifiedOutflow))
        local keys = {}
        for key in pairs(p.categories or {}) do keys[#keys + 1] = key end
        table.sort(keys)
        for _, key in ipairs(keys) do
            local entry = p.categories[key]
            tracked[#tracked + 1] = t("lb_categoryTotals", known(key), money(entry.inflow), money(entry.outflow))
        end
        for _, message in ipairs(p.gaps or {}) do tracked[#tracked + 1] = known(message) end
        tracked[#tracked + 1] = ""
    end
    section("lb_history", tracked)

    local forecast = model.forecast or {}
    local lines = {t("lb_forecastMethod"), t("lb_forecastScope"), t("lb_forecastNoBalance"), ""}
    if forecast.status ~= "available" then lines[#lines + 1] = t("lb_forecastMissing")
    else
        lines[#lines + 1] = t("lb_forecastAnnual", money(forecast.annualCashBeforePrincipal))
        for _, p in ipairs(forecast.periods or {}) do
            lines[#lines + 1] = t("lb_period", known(p.year), known(p.month), t("lb_forecast"))
            lines[#lines + 1] = t("lb_forecastSource", known(p.sourceYear), known(p.sourceMonth))
            lines[#lines + 1] = t("lb_operatingTotals", money(p.operatingRevenue), money(p.operatingExpense))
            lines[#lines + 1] = t("lb_interestTotal", money(p.interestExpense))
            lines[#lines + 1] = t("lb_forecastNet", money(p.cashBeforePrincipal))
            lines[#lines + 1] = ""
        end
    end
    section("lb_forecast", lines)
    if BankDiagnostics ~= nil and BankDiagnostics.isEnabled() then
        for _, entry in ipairs(sections) do BankDiagnostics.emit("report.finance.section", {titleKey = entry.title, logicalLines = #entry.lines}) end
    end
    return sections
end
