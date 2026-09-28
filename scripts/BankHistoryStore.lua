-- Typed, bounded XML sidecar. No executable serialization and no native XML edits.
BankHistoryStore = {}
local N = BankHistory.isNumber
local numeric = {"year", "month", "startDay", "startTime", "endDay", "endTime", "openingCash", "closingCash", "events"}
for _, key in ipairs(BankHistory.AMOUNTS) do numeric[#numeric + 1] = key end
local function diagnostic(method, ...) BankHistory.diagnostic(method, ...) end
local function filename(path)
    return type(path) == "string" and path:gsub("\\", "/"):match("([^/]+)/?$") or nil
end
local function clock()
    if type(os) == "table" and type(os.clock) == "function" then
        local ok, value = pcall(os.clock)
        if ok and N(value) then return value end
    end
end

local function releaseHandle(xml, path, operation)
    if xml == nil or xml == 0 then return nil end
    -- Observe the existing single release attempt without changing persistence
    -- results or retrying an engine handle whose state is now unknown.
    local ok, err = pcall(delete, xml)
    local proof = {filename = filename(path), operation = operation, attempted = true, callSucceeded = ok,
        scope = "Native delete call returned without throwing; handle destruction is not independently verified"}
    if not ok then
        proof.error = type(err) == "string" and err:sub(1, 256) or ("Non-string release error: " .. type(err))
    end
    diagnostic("emit", "history.xml.release", proof)
    diagnostic("check", "HISTORY_XML_RELEASE", ok and "PASS" or "FAIL", proof)
    return ok
end

-- Compare the serialized contract only. Source labels and session diagnostics
-- are deliberately not persisted and therefore cannot prove XML integrity.
local function verifyReadback(expected, actual)
    local differences, checked = {}, 0
    local function field(path, before, after)
        checked = checked + 1
        if before ~= after then differences[#differences + 1] = path end
    end
    for _, key in ipairs({"schemaVersion", "farmId", "cycle", "balance", "debt", "mode"}) do field(key, expected[key], actual[key]) end
    for _, key in ipairs({"day", "period", "dayTime", "daysPerPeriod"}) do field("last." .. key, expected.last[key], actual.last[key]) end
    local function period(path, before, after)
        if type(after) ~= "table" then field(path, "period", nil); return end
        for _, key in ipairs(numeric) do field(path .. "." .. key, before[key], after[key]) end
        for _, key in ipairs({"complete", "reconciled"}) do field(path .. "." .. key, before[key], after[key]) end
        field(path .. ".gapCount", #(before.gaps or {}), #(after.gaps or {}))
        for i, value in ipairs(before.gaps or {}) do field(path .. ".gap" .. i, value, (after.gaps or {})[i]) end
        local beforeCount, afterCount = 0, 0
        for name, entry in pairs(before.categories or {}) do
            beforeCount = beforeCount + 1
            local saved = (after.categories or {})[name] or {}
            for _, key in ipairs({"classification", "inflow", "outflow"}) do field(path .. ".category." .. name .. "." .. key, entry[key], saved[key]) end
        end
        for _ in pairs(after.categories or {}) do afterCount = afterCount + 1 end
        field(path .. ".categoryCount", beforeCount, afterCount)
    end
    period("current", expected.current, actual.current)
    field("periodCount", #expected.periods, #actual.periods)
    for i, value in ipairs(expected.periods) do period("period" .. i, value, actual.periods[i]) end
    local first = {}
    for i = 1, math.min(12, #differences) do first[i] = differences[i] end
    return {fieldsCompared = checked, mismatchCount = #differences, firstMismatches = first}
end

local function debugReadback(path, ledger)
    if not BankHistory.diagnosticsEnabled() then return end
    -- Debug verification must neither alter the writer's result nor leak a
    -- failed/missing reader into the native save callback.
    local before = clock()
    local called, saved = pcall(BankHistoryStore.read, path)
    local elapsed = clock()
    local proof = {filename = filename(path), farmId = ledger.farmId, readInvoked = true,
        readSucceeded = called and type(saved) == "table", scope = "Bank sidecar fields only; native save promotion not proven"}
    if before and elapsed then proof.elapsedCpuSeconds = math.max(0, elapsed - before)
    else proof.timing = "unavailable" end
    local outcome = "UNAVAILABLE"
    if proof.readSucceeded then
        local compared, result = pcall(verifyReadback, ledger, saved)
        if compared then
            for key, value in pairs(result) do proof[key] = value end
            outcome = result.mismatchCount == 0 and "PASS" or "FAIL"
        else proof.reason = "Readback comparison could not run" end
    else proof.reason = "Saved sidecar could not be decoded by the normal bounded reader" end
    diagnostic("emit", "history.xml.readback", proof)
    diagnostic("check", "HISTORY_XML_READBACK", outcome, proof)
end

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
    if not BankHistoryStore.available() then
        diagnostic("check", "HISTORY_XML_WRITE", "UNAVAILABLE", {filename = filename(path), reason = "Native XML functions unavailable"})
        return false, "Native XML functions unavailable."
    end
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
        local saved = saveXMLFile(xml)
        diagnostic("read", "history", "saveXMLFile", saved == true, saved, {filename = filename(path), stage = "sidecar_write_acknowledgement"})
        assert(saved == true, "History XML save success was not confirmed")
    end)
    local released = releaseHandle(xml, path, "write")
    diagnostic("emit", "history.xml.write", {filename = filename(path), succeeded = ok,
        handleReleaseAttempted = xml ~= nil and xml ~= 0, handleReleaseCallSucceeded = released})
    diagnostic("check", "HISTORY_XML_WRITE", ok and "PASS" or "FAIL", {filename = filename(path), acknowledged = ok, scope = "Bank sidecar write only"})
    if ok then
        if BankHistory.diagnosticsEnabled() then pcall(debugReadback, path, ledger) end
        return true, nil
    end
    return false, tostring(err)
end

function BankHistoryStore.read(path)
    if not BankHistoryStore.available() then
        diagnostic("emit", "history.xml.read", {filename = filename(path), succeeded = false, reason = "Native XML functions unavailable"})
        return nil, "Native XML functions unavailable."
    end
    if not fileExists(path) then
        diagnostic("emit", "history.xml.read", {filename = filename(path), succeeded = false, reason = "Sidecar absent"})
        return nil, "No saved Lizard Bank history yet."
    end
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
    local released = releaseHandle(xml, path, "read")
    diagnostic("emit", "history.xml.read", {filename = filename(path), succeeded = ok,
        handleReleaseAttempted = xml ~= nil and xml ~= 0, handleReleaseCallSucceeded = released, farmId = ok and result.farmId or nil,
        retainedPeriods = ok and #result.periods or nil, reason = not ok and "Bounded XML decode rejected sidecar" or nil})
    if ok then return result, nil end
    return nil, tostring(result)
end
