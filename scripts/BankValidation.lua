-- Independent invariants over detached snapshots. These establish named
-- consistency properties, not that an undocumented native accessor is correct.
BankValidation = {}
local function finite(v) return type(v) == "number" and v == v and math.abs(v) < math.huge end
local function close(a, b) return finite(a) and finite(b) and math.abs(a - b) <= 0.01 + math.max(math.abs(a), math.abs(b)) * 1e-10 end
local function integer(v) return finite(v) and v == math.floor(v) end
local function tableOr(v) return type(v) == "table" and v or {} end
local function key(v) return type(v) .. ":" .. tostring(v) end
local flows = {operatingRevenue = 1, operatingExpense = -1, interestExpense = -1, capitalInflow = 1,
    capitalOutflow = -1, financingInflow = 1, financingOutflow = -1, unclassifiedInflow = 1, unclassifiedOutflow = -1}

function BankValidation.evaluate(snapshot, previous, output)
    local results = {}
    local function check(id, outcome, evidence)
        local row = {id = "AUTO_" .. id, outcome = outcome, evidence = evidence or {}}
        results[#results + 1] = row
        if output then output(row.id, row.outcome, row.evidence) end
    end
    local function test(id, condition, evidence) check(id, condition and "PASS" or "FAIL", evidence) end
    snapshot = tableOr(snapshot)
    local farm, history = tableOr(snapshot.farm), tableOr(snapshot.history)
    if farm.id == nil then check("FARM_ID", "UNAVAILABLE", {reason = "No resolved active farm"})
    else test("FARM_ID", integer(farm.id) and farm.id > 0, {farmId = farm.id, oracle = "positive whole identifier; does not prove active-player attribution"}) end
    for _, name in ipairs({"cash", "debt"}) do
        local record = tableOr(snapshot[name])
        if record.status == "available" then
            test(name:upper() .. "_FINITE", finite(record.value) and (name == "cash" or record.value >= 0), {value = record.value, source = record.source})
        else
            check(name:upper() .. "_FINITE", "UNAVAILABLE", {status = record.status, source = record.source})
            test(name:upper() .. "_UNKNOWN_NOT_ZERO", record.value == nil, {value = record.value})
        end
    end
    local function items(name, field, totalField, predicate)
        local section = tableOr(snapshot[name])
        if section.status == nil or section.status == "unavailable" then
            check(name:upper() .. "_SUM", "UNAVAILABLE", {status = section.status}); return
        end
        local sum, count, seen, duplicates, invalid = 0, 0, {}, 0, 0
        for i, item in ipairs(section.items or {}) do
            if item.id ~= nil then
                local id = key(item.id)
                if seen[id] then duplicates = duplicates + 1 end
                seen[id] = true
            else check(name:upper() .. "_ITEM_ID", "UNAVAILABLE", {row = i}) end
            if predicate == nil or predicate(item) then
                if finite(item[field]) and item[field] >= 0 then sum, count = sum + item[field], count + 1
                elseif item[field] ~= nil then invalid = invalid + 1 end
            elseif item[field] ~= nil then
                check(name:upper() .. "_EXCLUDED_VALUE", "FAIL", {id = item.id, ownership = item.ownership, value = item[field]})
            end
        end
        test(name:upper() .. "_UNIQUE_IDS", duplicates == 0, {duplicates = duplicates, items = #(section.items or {})})
        test(name:upper() .. "_VALUE_RANGE", invalid == 0, {invalid = invalid})
        local total = section[totalField]
        if total == nil then check(name:upper() .. "_SUM", "UNAVAILABLE", {knownItems = count, sum = sum})
        else test(name:upper() .. "_SUM", close(total, sum), {actual = total, recomputed = sum, knownItems = count, basis = field}) end
    end
    items("land", "value", "totalValue")
    items("equipment", "value", "ownedValue", function(item) return item.ownership == "owned" end)
    items("buildings", "value", "totalValue")
    items("animals", "value", "totalValue")
    local land = tableOr(snapshot.land)
    if land.totalAreaHa ~= nil then
        local sum = 0
        for _, item in ipairs(land.items or {}) do if finite(item.areaHa) and item.areaHa >= 0 then sum = sum + item.areaHa end end
        test("LAND_AREA_SUM", close(sum, land.totalAreaHa), {actual = land.totalAreaHa, recomputed = sum, unit = "ha"})
    else check("LAND_AREA_SUM", "UNAVAILABLE") end
    local equipment = tableOr(snapshot.equipment)
    local counts = {owned = 0, leased = 0, borrowed = 0, unknown = 0}
    for _, item in ipairs(equipment.items or {}) do counts[item.ownership or "unknown"] = (counts[item.ownership or "unknown"] or 0) + 1 end
    for _, pair in ipairs({{"owned", "ownedCount"}, {"leased", "leasedCount"}, {"borrowed", "borrowedCount"}}) do
        if equipment[pair[2]] ~= nil then test("EQUIPMENT_" .. pair[1]:upper() .. "_COUNT", equipment[pair[2]] == counts[pair[1]], {actual = equipment[pair[2]], counted = counts[pair[1]]}) end
    end
    local animals, animalCount, countKnown = tableOr(snapshot.animals), 0, 0
    for _, row in ipairs(animals.items or {}) do
        if row.count ~= nil then
            test("ANIMAL_COUNT_RANGE", integer(row.count) and row.count >= 0, {id = row.id, count = row.count})
            if finite(row.count) then animalCount, countKnown = animalCount + row.count, countKnown + 1 end
        end
        if row.value ~= nil then test("ANIMAL_QUOTE_PRODUCT", finite(row.count) and finite(row.unitValue) and close(row.value, row.count * row.unitValue), {id = row.id, count = row.count, unitValue = row.unitValue, groupValue = row.value}) end
        if row.healthPercent ~= nil then test("ANIMAL_HEALTH_RANGE", finite(row.healthPercent) and row.healthPercent >= 0 and row.healthPercent <= 100, {id = row.id, value = row.healthPercent}) end
        test("ANIMAL_UNVERIFIED_UNITS", row.ageMonths == nil and row.reproductionPercent == nil, {id = row.id, ageRaw = row.ageRaw, reproductionRaw = row.reproductionRaw})
    end
    if animals.totalCount ~= nil then test("ANIMAL_COUNT_SUM", close(animals.totalCount, animalCount), {actual = animals.totalCount, recomputed = animalCount, knownGroups = countKnown}) end
    local inventory, ids = tableOr(snapshot.inventory), {}
    for _, row in ipairs(inventory.items or {}) do
        if row.id ~= nil then
            local id = key(row.id)
            test("INVENTORY_UNIQUE_ROWS", not ids[id], {id = row.id, kind = row.kind})
            ids[id] = true
        end
        if row.quantityStatus == "available" then
            test("INVENTORY_QUANTITY", finite(row.quantity) and row.quantity >= 0, {id = row.id, value = row.quantity, unit = row.unit, kind = row.kind})
        else check("INVENTORY_QUANTITY", "UNAVAILABLE", {id = row.id, status = row.quantityStatus, kind = row.kind}) end
        if row.fermentationProgress ~= nil then test("BALE_FERMENTATION_RANGE", finite(row.fermentationProgress) and row.fermentationProgress >= 0 and row.fermentationProgress <= 1, {id = row.id, progress = row.fermentationProgress}) end
    end
    local finance = tableOr(snapshot.finance)
    test("NATIVE_HISTORY_NOT_VERIFIED", finance.verification ~= "verified" and finance.windowStatus ~= "verified", {verification = finance.verification, windowStatus = finance.windowStatus})
    local retainedKnown, retainedUnknown, unclassified = 0, 0, 0
    for _, row in ipairs(finance.records or {}) do
        if row.status == "available" then
            retainedKnown = retainedKnown + 1
            test("FINANCE_FINITE_SIGNED", finite(row.rawSignedValue), {category = row.categoryKey, slot = row.periodKey, value = row.rawSignedValue})
        else retainedUnknown = retainedUnknown + 1 end
        if row.classification == "unclassified" then unclassified = unclassified + 1 end
    end
    for _, pair in ipairs({{"knownValueCount", retainedKnown}, {"unknownValueCount", retainedUnknown}, {"unclassifiedCount", unclassified}}) do
        if finance[pair[1]] ~= nil then test("FINANCE_" .. pair[1]:upper(), finance[pair[1]] == pair[2], {actual = finance[pair[1]], counted = pair[2]}) end
    end
    if history.farmId ~= nil then test("HISTORY_FARM_MATCH", history.farmId == farm.id, {historyFarm = history.farmId, snapshotFarm = farm.id})
    else check("HISTORY_FARM_MATCH", "UNAVAILABLE") end
    local function ledgerPeriod(period, isCurrent)
        local sum, valid = period.openingCash, finite(period.openingCash)
        for field, sign in pairs(flows) do
            if not finite(period[field]) or period[field] < 0 then valid = false
            elseif finite(sum) then sum = sum + sign * period[field] end
        end
        local reconciles = valid and close(sum, period.closingCash)
        local outcome = reconciles and "PASS" or (period.reconciled == true and "FAIL" or "WARN")
        check("LEDGER_CASH_EQUATION", outcome, {year = period.year, period = period.month, isCurrent = isCurrent,
            openingCash = period.openingCash, closingCash = period.closingCash, calculated = sum, declaredReconciled = period.reconciled})
        if period.complete == true then test("COMPLETE_PERIOD_RECONCILED", period.reconciled == true and reconciles, {year = period.year, period = period.month}) end
    end
    local periodIndices, invalidHistory = {}, false
    for _, period in ipairs(history.periods or {}) do
        ledgerPeriod(period, false)
        if integer(period.year) and period.year >= 0 and integer(period.month) and period.month >= 1 and period.month <= 12 then
            local index = period.year * 12 + period.month
            test("HISTORY_UNIQUE_PERIODS", not periodIndices[index], {index = index})
            if periodIndices[index] then invalidHistory = true end
            periodIndices[index] = period
        else invalidHistory = true; check("HISTORY_UNIQUE_PERIODS", "FAIL", {reason = "invalid date"}) end
    end
    if history.current then ledgerPeriod(history.current, true) end
    if history.farmId == farm.id and history.current and finite(tableOr(snapshot.cash).value) and finite(history.current.closingCash) then
        test("CAPTURE_CASH_CONSISTENCY", close(snapshot.cash.value, history.current.closingCash),
            {snapshotCash = snapshot.cash.value, observedCash = history.current.closingCash,
                oracle = "Balance reads surrounding the capture agree; does not prove unknown native side effects absent."})
    end
    local model = tableOr(snapshot.underwriting)
    local assessment, forecast = tableOr(model.assessment), tableOr(model.forecast)
    if assessment.status == "available" or forecast.status == "available" then
        local valid, reasons = true, {}
        local current = integer(history.currentYear) and integer(history.currentMonth) and (history.currentYear * 12 + history.currentMonth) or nil
        if not integer(farm.id) or farm.id <= 0 or history.farmId ~= farm.id or current == nil
            or history.currentYear < 0 or history.currentMonth < 1 or history.currentMonth > 12
            or type(history.materialGaps) ~= "table" or next(history.materialGaps) ~= nil or invalidHistory then valid = false; reasons[#reasons + 1] = "identity/calendar/gaps/duplicate" end
        if current then
            for i = current - 12, current - 1 do
                local p = periodIndices[i]
                if not p or p.complete ~= true or p.reconciled ~= true or p.unclassifiedInflow ~= 0 or p.unclassifiedOutflow ~= 0 then
                    valid = false; reasons[#reasons + 1] = "missing/partial/unclassified:" .. i
                else for field in pairs(flows) do if not finite(p[field]) or p[field] < 0 then valid = false end end end
            end
        end
        test("MODEL_EVIDENCE_GATE", valid, {reasons = reasons, assessment = assessment.status, forecast = forecast.status})
    else
        test("MODEL_WITHHELD_NO_SCORE", assessment.score == nil and assessment.band == nil, {status = assessment.status, score = assessment.score})
        test("FORECAST_WITHHELD_NO_ROWS", #(forecast.periods or {}) == 0, {status = forecast.status, rows = #(forecast.periods or {})})
    end
    if assessment.status == "available" then
        local sum, maxWeight = 0, 0
        for _, component in ipairs(assessment.components or {}) do
            test("SCORE_COMPONENT_BOUNDS", finite(component.points) and finite(component.weight) and component.points >= 0 and component.points <= component.weight,
                {component = component.name, points = component.points, weight = component.weight})
            sum = sum + (finite(component.points) and component.points or 0)
            maxWeight = maxWeight + (finite(component.weight) and component.weight or 0)
        end
        test("SCORE_SUM", maxWeight == 100 and integer(assessment.score) and assessment.score == math.floor(sum + 0.5) and assessment.score >= 0 and assessment.score <= 100,
            {score = assessment.score, componentSum = sum, totalWeight = maxWeight})
        local expected = (assessment.score or -1) >= 75 and "favorable" or ((assessment.score or -1) >= 50 and "guarded" or "strained")
        test("SCORE_BAND", assessment.band == expected, {actual = assessment.band, expected = expected})
    else check("SCORE_SUM", "NOT_EXERCISED", {reason = "No eligible assessment; no synthetic live score generated."}) end
    test("COLLATERAL_SEPARATE", tableOr(model.collateral).includedInScore ~= true, {includedInScore = tableOr(model.collateral).includedInScore})
    test("NO_PROFIT_OR_DSCR_CLAIM", tableOr(assessment.principalCoverage).status ~= "available" and tableOr(assessment.profitability).status ~= "available")
    if forecast.status == "available" then
        test("FORECAST_COUNT", #(forecast.periods or {}) == 12, {count = #(forecast.periods or {})})
        local annual, valid = 0, true
        for i, row in ipairs(forecast.periods or {}) do
            local current = integer(history.currentYear) and integer(history.currentMonth) and (history.currentYear * 12 + history.currentMonth) or nil
            test("FORECAST_FUTURE_SEQUENCE", current ~= nil and integer(row.year) and integer(row.month) and row.year * 12 + row.month == current + i,
                {row = i, year = row.year, period = row.month, currentYear = history.currentYear, currentPeriod = history.currentMonth})
            local source = integer(row.sourceYear) and integer(row.sourceMonth) and periodIndices[row.sourceYear * 12 + row.sourceMonth] or nil
            local matches = source and source.month == row.month and close(source.operatingRevenue, row.operatingRevenue)
                and close(source.operatingExpense, row.operatingExpense) and close(source.interestExpense, row.interestExpense)
            test("FORECAST_SOURCE_MATCH", matches == true, {row = i, year = row.year, period = row.month, sourceYear = row.sourceYear, sourcePeriod = row.sourceMonth})
            if finite(row.operatingRevenue) and finite(row.operatingExpense) and finite(row.interestExpense) and finite(row.cashBeforePrincipal) then
                test("FORECAST_NET", close(row.cashBeforePrincipal, row.operatingRevenue - row.operatingExpense - row.interestExpense), {row = i, net = row.cashBeforePrincipal})
                annual = annual + row.cashBeforePrincipal
            else valid = false end
            test("FORECAST_NO_CLOSING_BALANCE", row.closingCash == nil and row.endingCash == nil, {row = i})
        end
        test("FORECAST_ANNUAL_SUM", valid and close(annual, forecast.annualCashBeforePrincipal), {actual = forecast.annualCashBeforePrincipal, recomputed = annual})
    else check("FORECAST_SOURCE_MATCH", "NOT_EXERCISED", {reason = "No eligible seasonal cycle."}) end
    if previous and tableOr(previous.farm).id == farm.id then
        for _, name in ipairs({"land", "equipment", "buildings", "inventory", "animals"}) do
            local before, after = {}, {}
            for _, row in ipairs(tableOr(previous[name]).items or {}) do if row.id ~= nil then before[key(row.id)] = row end end
            for _, row in ipairs(tableOr(snapshot[name]).items or {}) do if row.id ~= nil then after[key(row.id)] = row end end
            for id, row in pairs(after) do
                if before[id] == nil then check("DELTA_" .. name:upper(), "WARN", {change = "added", id = row.id, name = row.name}) end
            end
            for id, row in pairs(before) do
                if after[id] == nil then check("DELTA_" .. name:upper(), "WARN", {change = "removed", id = row.id, name = row.name}) end
            end
        end
        local oldHistory = tableOr(previous.history)
        local current, old = history.current, oldHistory.current
        if current and old and current.year == old.year and current.month == old.month then
            local function nativeRows(fin)
                local values = {}
                for _, row in ipairs(tableOr(fin).records or {}) do
                    if row.bucketKind == "currentCandidate" and finite(row.rawSignedValue) then values[key(row.categoryKey)] = row.rawSignedValue end
                end
                return values
            end
            local beforeNative, afterNative = nativeRows(previous.finance), nativeRows(finance)
            for category, totals in pairs(current.categories or {}) do
                local earlier = tableOr(tableOr(old.categories)[category])
                local incoming = totals.inflow - (earlier.inflow or 0)
                local outgoing = totals.outflow - (earlier.outflow or 0)
                if incoming ~= 0 or outgoing ~= 0 then
                    local beforeValue, afterValue = beforeNative[key(category)], afterNative[key(category)]
                    if beforeValue ~= nil and afterValue ~= nil then
                        local rawChange, observedChange = afterValue - beforeValue, incoming - outgoing
                        check("NATIVE_FINANCE_DELTA_MAGNITUDE", close(math.abs(rawChange), math.abs(observedChange)) and "PASS" or "WARN",
                            {category = category, rawBefore = beforeValue, rawAfter = afterValue, nativeChange = rawChange,
                                observedInflow = incoming, observedOutflow = outgoing, observedNet = observedChange,
                                oracle = "magnitude comparison only; native signs/category/window remain unverified"})
                    else check("NATIVE_FINANCE_DELTA_MAGNITUDE", "UNAVAILABLE", {category = category, reason = "No matched readable current native category at both checkpoints"}) end
                end
            end
        end
    end
    return results
end

function BankValidation.pages(pages, lineLimit, output)
    local ok = type(pages) == "table" and #pages > 0
    for i, page in ipairs(pages or {}) do
        local _, breaks = tostring(page.text or ""):gsub("\n", "")
        local valid = type(page.title) == "string" and type(page.text) == "string" and breaks + 1 <= lineLimit
        if not valid then ok = false end
        output("AUTO_GUI_PAGE_LINES", valid and "PASS" or "FAIL", {page = i, lines = breaks + 1, maximum = lineLimit})
        local titlePresent = type(page.title) == "string" and page.title:find("%S") ~= nil
        local textPresent = type(page.text) == "string" and page.text:find("%S") ~= nil
        if not titlePresent or not textPresent then ok = false end
        output("AUTO_GUI_PAGE_TEXT", titlePresent and textPresent and "PASS" or "FAIL",
            {page = i, titlePresent = titlePresent, textPresent = textPresent})
    end
    output("AUTO_GUI_REPORT_PAGES", ok and "PASS" or "FAIL", {count = type(pages) == "table" and #pages or nil})
end
