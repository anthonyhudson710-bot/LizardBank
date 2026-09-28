-- Typed, bounded XML sidecar. No executable serialization and no native XML edits.
BankHistoryStore = {}
local N = BankHistory.isNumber
local numeric = {"year", "month", "startDay", "startTime", "endDay", "endTime", "openingCash", "closingCash", "events"}
for _, key in ipairs(BankHistory.AMOUNTS) do numeric[#numeric + 1] = key end

local function writeNumber(xml, key, value)
    if N(value) then setXMLString(xml, key, string.format("%.17g", value)) end
end
local function readNumber(xml, key)
    local value = tonumber(getXMLString(xml, key))
    if N(value) then return value end
end
local function integer(value, low, high)
    return N(value) and value == math.floor(value) and value >= low and value <= high
end
local function writePeriod(xml, path, p)
    for _, key in ipairs(numeric) do writeNumber(xml, path .. "#" .. key, p[key]) end
    setXMLString(xml, path .. "#complete", p.complete and "1" or "0")
    setXMLString(xml, path .. "#reconciled", p.reconciled and "1" or "0")
    for i, message in ipairs(p.gaps or {}) do setXMLString(xml, path .. ".gap(" .. i - 1 .. ")#text", message) end
    local keys = {}
    for key in pairs(p.categories or {}) do keys[#keys + 1] = key end
    table.sort(keys)
    for i, key in ipairs(keys) do
        local entry, base = p.categories[key], path .. ".category(" .. i - 1 .. ")"
        setXMLString(xml, base .. "#name", key)
        setXMLString(xml, base .. "#classification", entry.classification)
        writeNumber(xml, base .. "#inflow", entry.inflow)
        writeNumber(xml, base .. "#outflow", entry.outflow)
    end
end
local function readPeriod(xml, path)
    local p = {gaps = {}, categories = {}}
    for _, key in ipairs(numeric) do p[key] = readNumber(xml, path .. "#" .. key) end
    assert(integer(p.year, 0, 1000000) and integer(p.month, 1, 12), "Invalid history period")
    assert(integer(p.startDay, 0, 1e12) and N(p.startTime) and p.startTime >= 0 and p.startTime < 86400000, "Invalid period start")
    if p.endDay ~= nil or p.endTime ~= nil then
        assert(integer(p.endDay, p.startDay, 1e12) and N(p.endTime) and p.endTime >= 0 and p.endTime < 86400000, "Invalid period end")
        assert(p.endDay > p.startDay or p.endTime >= p.startTime, "Period ends before it starts")
    end
    assert(N(p.openingCash) and N(p.closingCash), "Invalid history cash")
    assert(integer(p.events, 0, 1e12), "Invalid history event count")
    local sum = p.openingCash
    for _, key in ipairs(BankHistory.AMOUNTS) do
        assert(N(p[key]) and p[key] >= 0, "Invalid history amount")
        local incoming = key == "operatingRevenue" or key:find("Inflow", 1, true) ~= nil
        sum = sum + (incoming and p[key] or -p[key])
    end
    p.complete = getXMLString(xml, path .. "#complete") == "1"
    p.reconciled = getXMLString(xml, path .. "#reconciled") == "1"
    for i = 0, 15 do
        local message = getXMLString(xml, path .. ".gap(" .. i .. ")#text")
        if message == nil then break end
        p.gaps[#p.gaps + 1] = tostring(message):sub(1, 256)
    end
    if not N(sum) or math.abs(sum - p.closingCash) > 0.01 or #p.gaps > 0 then p.complete, p.reconciled = false, false end
    for i = 0, 128 do
        local base = path .. ".category(" .. i .. ")"
        local name = getXMLString(xml, base .. "#name")
        if name == nil then break end
        assert(#name <= 96 and p.categories[name] == nil, "Invalid history category")
        local incoming, outgoing = readNumber(xml, base .. "#inflow"), readNumber(xml, base .. "#outflow")
        assert(N(incoming) and N(outgoing) and incoming >= 0 and outgoing >= 0, "Invalid category amount")
        local classification = getXMLString(xml, base .. "#classification") or "unclassified"
        assert(classification == "operating" or classification == "interest" or classification == "capital"
            or classification == "financing" or classification == "unclassified", "Invalid category classification")
        p.categories[name] = {inflow = incoming, outflow = outgoing, classification = classification}
    end
    return p
end

function BankHistoryStore.available()
    return type(createXMLFile) == "function" and type(loadXMLFile) == "function"
        and type(setXMLString) == "function" and type(getXMLString) == "function"
        and type(saveXMLFile) == "function" and type(delete) == "function" and type(fileExists) == "function"
end

function BankHistoryStore.write(path, ledger)
    if not BankHistoryStore.available() then return false, "Native XML functions unavailable." end
    local xml
    local ok, err = pcall(function()
        xml = createXMLFile("LizardBankHistory", path, "lizardBankHistory")
        assert(xml ~= nil and xml ~= 0, "Cannot create history XML")
        local root = "lizardBankHistory"
        writeNumber(xml, root .. "#schema", BankHistory.SCHEMA)
        writeNumber(xml, root .. "#farmId", ledger.farmId)
        writeNumber(xml, root .. "#cycle", ledger.cycle)
        writeNumber(xml, root .. "#cash", ledger.balance)
        writeNumber(xml, root .. "#debt", ledger.debt)
        writeNumber(xml, root .. "#day", ledger.last.day)
        writeNumber(xml, root .. "#period", ledger.last.period)
        writeNumber(xml, root .. "#dayTime", ledger.last.dayTime)
        writeNumber(xml, root .. "#daysPerPeriod", ledger.last.daysPerPeriod)
        setXMLString(xml, root .. "#mode", ledger.mode)
        writeNumber(xml, root .. "#count", #ledger.periods)
        writePeriod(xml, root .. ".current", ledger.current)
        for i, p in ipairs(ledger.periods) do writePeriod(xml, root .. ".period(" .. i - 1 .. ")", p) end
        assert(saveXMLFile(xml) == true, "History XML save success was not confirmed")
    end)
    if xml ~= nil and xml ~= 0 then pcall(delete, xml) end
    if ok then return true, nil end
    return false, tostring(err)
end

function BankHistoryStore.read(path)
    if not BankHistoryStore.available() then return nil, "Native XML functions unavailable." end
    if not fileExists(path) then return nil, "No saved Lizard Bank history yet." end
    local xml
    local ok, result = pcall(function()
        xml = loadXMLFile("LizardBankHistory", path)
        assert(xml ~= nil and xml ~= 0, "Cannot load history XML")
        local root = "lizardBankHistory"
        assert(readNumber(xml, root .. "#schema") == BankHistory.SCHEMA, "Unsupported history schema")
        local count = readNumber(xml, root .. "#count")
        assert(integer(count, 0, BankHistory.MAX_PERIODS), "Invalid history count")
        local ledger = {schemaVersion = BankHistory.SCHEMA, farmId = readNumber(xml, root .. "#farmId"),
            cycle = readNumber(xml, root .. "#cycle"), balance = readNumber(xml, root .. "#cash"),
            debt = readNumber(xml, root .. "#debt"), mode = getXMLString(xml, root .. "#mode"),
            last = {day = readNumber(xml, root .. "#day"), period = readNumber(xml, root .. "#period"),
                dayTime = readNumber(xml, root .. "#dayTime"), daysPerPeriod = readNumber(xml, root .. "#daysPerPeriod")},
            periods = {}, current = readPeriod(xml, root .. ".current"),
            source = "observed game money movements", calendarBasis = "Local cycle / native period / monotonic game day"}
        assert(integer(ledger.farmId, 1, 1000000) and integer(ledger.cycle, 0, 1000000), "Invalid ledger identity")
        assert(BankHistory.isCalendar(ledger.last), "Invalid calendar anchor")
        assert(ledger.debt == nil or (N(ledger.debt) and ledger.debt >= 0), "Invalid debt anchor")
        assert(ledger.current.year == ledger.cycle and ledger.current.month == ledger.last.period, "Current period mismatch")
        assert(N(ledger.balance) and math.abs(ledger.balance - ledger.current.closingCash) < 0.01, "Cash anchor mismatch")
        if ledger.mode ~= "strict" and ledger.mode ~= "lenient" then ledger.mode = "standard" end
        local previous = -1
        for i = 0, count - 1 do
            local p = readPeriod(xml, root .. ".period(" .. i .. ")")
            assert(p.endDay ~= nil and p.endTime ~= nil and p.endDay <= ledger.last.day, "Invalid completed period date")
            local index = p.year * 12 + p.month - 1
            assert(index > previous and index < ledger.cycle * 12 + ledger.last.period - 1, "History ordering invalid")
            previous = index
            ledger.periods[#ledger.periods + 1] = p
        end
        return ledger
    end)
    if xml ~= nil and xml ~= 0 then pcall(delete, xml) end
    if ok then return result, nil end
    return nil, tostring(result)
end
