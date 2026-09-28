-- Pure, bounded observation ledger. Native archive slots are never imported.
BankHistory = {}
BankHistory.SCHEMA = 1
BankHistory.MAX_PERIODS = 36
BankHistory.AMOUNTS = {"operatingRevenue", "operatingExpense", "interestExpense", "capitalInflow", "capitalOutflow", "financingInflow", "financingOutflow", "unclassifiedInflow", "unclassifiedOutflow"}

local function number(v)
    return type(v) == "number" and v == v and math.abs(v) < 1e15
end
BankHistory.isNumber = number

local function copy(t)
    local result = {}
    for k, v in pairs(t or {}) do result[k] = type(v) == "table" and copy(v) or v end
    return result
end

local function calendar(t)
    return type(t) == "table" and number(t.day) and t.day >= 0 and t.day == math.floor(t.day)
        and number(t.period) and t.period >= 1 and t.period <= 12 and t.period == math.floor(t.period)
        and number(t.dayTime) and t.dayTime >= 0 and t.dayTime < 86400000
end
BankHistory.isCalendar = calendar

local function gap(period, reason)
    period.complete, period.reconciled = false, false
    period.gaps = period.gaps or {}
    for _, existing in ipairs(period.gaps) do if existing == reason then return end end
    if #period.gaps < 16 then period.gaps[#period.gaps + 1] = reason end
end

local function newPeriod(stamp, cycle, balance, full)
    local p = {year = cycle, month = stamp.period, startDay = stamp.day, startTime = stamp.dayTime,
        openingCash = balance, closingCash = balance, complete = full, reconciled = true,
        events = 0, gaps = {}, categories = {}}
    for _, key in ipairs(BankHistory.AMOUNTS) do p[key] = 0 end
    if not full then gap(p, "Tracking began during this period; earlier activity is unknown.") end
    return p
end

function BankHistory.new(farmId, stamp, cash)
    if not calendar(stamp) or not number(cash) or not number(farmId) or farmId <= 0 or farmId ~= math.floor(farmId) then return nil end
    return {schemaVersion = BankHistory.SCHEMA, farmId = farmId, cycle = 0, periods = {},
        current = newPeriod(stamp, 0, cash, false), last = copy(stamp), balance = cash,
        mode = "standard", source = "observed game money movements", calendarBasis = "Local cycle / native period / monotonic game day"}
end

function BankHistory.markGap(ledger, reason)
    if ledger and ledger.current then gap(ledger.current, reason) end
end

function BankHistory.observe(ledger, stamp, cash)
    if not ledger then return false end
    if not calendar(stamp) or not number(cash) then
        BankHistory.markGap(ledger, "Calendar or cash unavailable during observation.")
        return false
    end
    local last, p = ledger.last, ledger.current
    if math.abs(cash - ledger.balance) > 0.01 then
        gap(p, "Cash changed outside classified observation; reconciliation failed.")
    end
    local backwards = stamp.day < last.day or (stamp.day == last.day and stamp.dayTime + 1 < last.dayTime)
    local skipped = stamp.day - last.day > 1
    local changedPeriod = stamp.period ~= last.period
    local adjacent = changedPeriod and stamp.period == last.period % 12 + 1 and stamp.day - last.day == 1
    local calendarJump = skipped or (changedPeriod and not adjacent)
    if backwards then
        -- A rollback invalidates this chain. Never retain future periods as evidence.
        ledger.periods, ledger.cycle = {}, 0
        ledger.current = newPeriod(stamp, 0, cash, false)
        gap(ledger.current, "Calendar moved backwards; history chain was restarted.")
    elseif calendarJump then
        -- The same seasonal slot can recur after one or several unobserved
        -- years. Do not compress that absence into an adjacent local cycle.
        ledger.periods, ledger.cycle = {}, 0
        ledger.current = newPeriod(stamp, 0, cash, false)
        gap(ledger.current, "Calendar continuity was lost; history chain was restarted.")
    elseif changedPeriod then
        p.endDay, p.endTime, p.closingCash = last.day, last.dayTime, ledger.balance
        if not adjacent then gap(p, "Unobserved seasonal boundary or skipped game days.") end
        ledger.periods[#ledger.periods + 1] = p
        if #ledger.periods > BankHistory.MAX_PERIODS then table.remove(ledger.periods, 1) end
        if stamp.period <= last.period then ledger.cycle = ledger.cycle + 1 end
        ledger.current = newPeriod(stamp, ledger.cycle, cash, adjacent and stamp.dayTime <= 60000)
        if stamp.dayTime > 60000 then gap(ledger.current, "Seasonal boundary was first observed after its opening minute.") end
    end
    ledger.balance, ledger.last = cash, copy(stamp)
    ledger.current.closingCash = cash
    return true
end

function BankHistory.record(ledger, stamp, before, after, category, classification)
    if not BankHistory.observe(ledger, stamp, before) or not number(after) then
        BankHistory.markGap(ledger, "Transaction balance could not be read.")
        return
    end
    local delta, p = after - before, ledger.current
    if math.abs(delta) < 0.000001 then return end
    if classification ~= "operating" and classification ~= "interest" and classification ~= "capital" and classification ~= "financing" then classification = "unclassified" end
    if classification == "interest" and delta > 0 then classification = "unclassified" end
    category = type(category) == "string" and category ~= "" and category:sub(1, 96) or "unknown"
    local entry = p.categories[category]
    if entry == nil then
        local count = 0
        for _ in pairs(p.categories) do count = count + 1 end
        if count >= 128 then
            category, classification = "other_unclassified", "unclassified"
            gap(p, "Category limit reached; additional movements are unclassified.")
        end
        entry = p.categories[category] or {inflow = 0, outflow = 0, classification = classification}
        p.categories[category] = entry
    elseif entry.classification ~= classification then
        classification, entry.classification = "unclassified", "unclassified"
        gap(p, "A money category changed classification within the period.")
    end
    local field
    if classification == "operating" then field = delta > 0 and "operatingRevenue" or "operatingExpense"
    elseif classification == "interest" and delta < 0 then field = "interestExpense"
    elseif classification == "capital" then field = delta > 0 and "capitalInflow" or "capitalOutflow"
    elseif classification == "financing" then field = delta > 0 and "financingInflow" or "financingOutflow"
    else field = delta > 0 and "unclassifiedInflow" or "unclassifiedOutflow" end
    local amount = math.abs(delta)
    if not number(amount) or not number(p[field] + amount) then
        gap(p, "Amount exceeds supported numeric range.")
        ledger.balance, p.closingCash = after, after
        return
    end
    p[field] = p[field] + amount
    p.events = p.events + 1
    local direction = delta > 0 and "inflow" or "outflow"
    if number(entry[direction] + amount) then entry[direction] = entry[direction] + amount
    else gap(p, "Category total exceeds supported numeric range.") end
    ledger.balance, p.closingCash = after, after
    if not number(p[field]) then gap(p, "Amount exceeds supported numeric range.") end
end

-- A saved ledger resumes only against the exact observation anchor. A detached
-- sidecar, disabled mod, rollback, different farm or failed native save is partial.
function BankHistory.resume(saved, farmId, stamp, cash)
    if type(saved) ~= "table" or saved.schemaVersion ~= BankHistory.SCHEMA or saved.farmId ~= farmId
        or type(saved.current) ~= "table" or type(saved.periods) ~= "table" or not calendar(saved.last)
        or not number(saved.cycle) or saved.cycle < 0 or saved.cycle ~= math.floor(saved.cycle)
        or saved.current.year ~= saved.cycle or saved.current.month ~= (saved.last and saved.last.period)
        or not calendar(stamp) or not number(saved.balance)
        or not number(cash) or saved.last.day ~= stamp.day or saved.last.period ~= stamp.period
        or saved.last.daysPerPeriod ~= stamp.daysPerPeriod
        or math.abs(saved.last.dayTime - stamp.dayTime) > 1 or math.abs(saved.balance - cash) > 0.01 then
        local fresh = BankHistory.new(farmId, stamp, cash)
        BankHistory.markGap(fresh, "Saved history anchor does not match this save; prior continuity is unverified.")
        return fresh, false
    end
    local result = copy(saved)
    return result, true
end

function BankHistory.report(ledger, issues)
    if not ledger then return {periods = {}, materialGaps = issues or {"Tracking unavailable."}} end
    local gaps = copy(issues or {})
    for _, message in ipairs(ledger.current.gaps or {}) do
        if message ~= "Tracking began during this period; earlier activity is unknown." then gaps[#gaps + 1] = message end
    end
    if ledger.current.unclassifiedInflow > 0 or ledger.current.unclassifiedOutflow > 0 then
        gaps[#gaps + 1] = "Current-period cash movements include unclassified activity."
    end
    table.sort(gaps)
    return {farmId = ledger.farmId, periods = copy(ledger.periods), current = copy(ledger.current),
        currentYear = ledger.cycle, currentMonth = ledger.last.period, materialGaps = gaps,
        calendarBasis = ledger.calendarBasis, source = ledger.source, retainedLimit = BankHistory.MAX_PERIODS,
        anchor = copy(ledger.last), mode = ledger.mode}
end
