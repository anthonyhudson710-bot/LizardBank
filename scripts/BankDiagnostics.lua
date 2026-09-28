-- Nonthrowing, bounded evidence transport. No engine mutation, file IO, RNG or
-- native object retention. JSON lines are consumed by tools/analyze_log.py.
BankDiagnostics = {}
local D = BankDiagnostics
local config = BankDebugConfig or {}
local function setting(key, default, minimum, maximum)
    local value = config[key]
    if type(value) ~= "number" or value ~= value or value < minimum or value > maximum then return default end
    return math.floor(value)
end
D.enabled = config.enabled == true
D.traceReads = config.traceReads == true
D.limits = {maxEvents = setting("maxEvents", 120000, 10, 1000000),
    maxBytes = setting("maxBytes", 67108864, 2048, 268435456),
    maxLineBytes = setting("maxLineBytes", 12000, 512, 65536)}
D.timing = {summary = setting("summaryIntervalMs", 60000, 1000, 600000),
    interval = setting("autoCaptureIntervalMs", 60000, 5000, 600000),
    minimum = setting("minimumCaptureIntervalMs", 15000, 1000, 600000),
    settle = setting("settleDelayMs", 2000, 0, 60000)}
local S = {sequence = 0, mission = 0, capture = 0, checks = {}, events = {}, reads = {}, bytes = 0,
    written = 0, dropped = 0, limited = false, loggerErrors = 0, depth = 0, elapsed = 0}
local outcomes = {PASS = true, FAIL = true, WARN = true, UNAVAILABLE = true, NOT_EXERCISED = true}
local prefix = "[LizardBank:VALIDATION] "

local function finite(v) return type(v) == "number" and v == v and math.abs(v) < math.huge end
local function quote(value)
    return '"' .. value:gsub('[%z\1-\31\\"]', function(c)
        local escapes = {['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t'}
        return escapes[c] or string.format("\\u%04x", string.byte(c))
    end) .. '"'
end

-- DTO serializer intentionally ignores metatables and marks every truncation.
local function encode(value, seen, depth, budget)
    local kind = type(value)
    if kind == "nil" then return "null" end
    if kind == "boolean" then return value and "true" or "false" end
    if kind == "number" then return finite(value) and string.format("%.17g", value) or '{"_unavailable":"nonfinite"}' end
    if kind == "string" then
        if #value > 2048 then budget.truncated = true; value = value:sub(1, 2048) .. "<truncated>" end
        return quote(value)
    end
    if kind ~= "table" then return '{"_type":' .. quote(kind) .. '}' end
    if seen[value] then budget.truncated = true; return '{"_unavailable":"cycle"}' end
    if depth > 8 or budget.remaining <= 0 then budget.truncated = true; return '{"_unavailable":"serialization_limit"}' end
    seen[value] = true
    local fields, visited, key = {}, 0, nil
    while true do
        key = next(value, key)
        if key == nil then break end
        visited = visited + 1
        if visited > 128 or budget.remaining <= 0 then budget.truncated = true; fields[#fields + 1] = '"_truncated":true'; break end
        budget.remaining = budget.remaining - 1
        local keyKind = type(key)
        if keyKind == "string" or (keyKind == "number" and finite(key)) then
            fields[#fields + 1] = quote(tostring(key)) .. ":" .. encode(rawget(value, key), seen, depth + 1, budget)
        else budget.truncated = true end
    end
    seen[value] = nil
    table.sort(fields)
    return "{" .. table.concat(fields, ",") .. "}"
end

local function rawWrite(event, data, force)
    S.sequence = S.sequence + 1
    local record = {schema = 1, seq = S.sequence, mission = S.mission, capture = S.capture, origin = S.origin or "runtime",
        event = event, gameTime = finite(g_time) and g_time or nil, data = data}
    local budget = {remaining = 700, truncated = false}
    local encoded = encode(record, {}, 0, budget)
    if #encoded > D.limits.maxLineBytes then
        budget.truncated = true
        record.data = {omitted = true, reason = "line_limit", originalBytes = #encoded}
        encoded = encode(record, {}, 0, {remaining = 100})
    end
    if budget.truncated then
        S.truncated = (S.truncated or 0) + 1
        -- A root flag survives even when the nested field that triggered the cap
        -- was replaced by the line-size fallback.
        encoded = encoded:sub(1, -2) .. ',"evidenceTruncated":true}'
    end
    local overBudget = S.written >= D.limits.maxEvents or S.bytes + #encoded > D.limits.maxBytes
    if not force and overBudget then
        S.dropped = S.dropped + 1
        if not S.limited then
            S.limited = true
            rawWrite("log.limit", {reason = "event_or_byte_budget", dropped = S.dropped,
                message = "Evidence is incomplete after this point; no all-clear may be inferred."}, true)
        end
        return
    end
    if force and overBudget then
        if (S.reserveWritten or 0) >= 16 or (S.reserveBytes or 0) + #encoded > 65536 then S.dropped = S.dropped + 1; return end
        S.reserveWritten, S.reserveBytes = (S.reserveWritten or 0) + 1, (S.reserveBytes or 0) + #encoded
    end
    print(prefix .. encoded)
    S.bytes, S.written = S.bytes + #encoded, S.written + 1
end

local function safe(fn, ...)
    if S.depth > 0 then return nil end
    S.depth = S.depth + 1
    local ok, value = pcall(fn, ...)
    S.depth = S.depth - 1
    if not ok then S.loggerErrors = S.loggerErrors + 1 end
    return ok and value or nil
end

function D.isEnabled() return D.enabled == true end

function D.emit(event, data)
    if not D.isEnabled() then return end
    return safe(function()
        event = type(event) == "string" and event:sub(1, 128) or "invalid_event"
        S.events[event] = (S.events[event] or 0) + 1
        if S.origin ~= "synthetic" and (event == "history.transaction.end" or event == "history.save.end" or event == "history.period.close" or event == "history.resume") then
            S.pending = S.pending or event
            S.settle = 0
        end
        rawWrite(event, data, false)
    end)
end

function D.check(id, outcome, evidence)
    if not D.isEnabled() then return end
    return safe(function()
        id = type(id) == "string" and id:sub(1, 128) or "INVALID_CHECK_ID"
        if S.origin == "synthetic" then id = "SYNTHETIC_" .. id end
        outcome = outcomes[outcome] and outcome or "UNAVAILABLE"
        local state = S.checks[id] or {observations = 0, counts = {}}
        S.checks[id] = state
        state.observations, state.latest = state.observations + 1, outcome
        state.counts[outcome] = (state.counts[outcome] or 0) + 1
        rawWrite("check", {id = id, outcome = outcome, evidence = evidence,
            oracle = "internal_consistency_unless_explicitly_stated"}, false)
    end)
end

local function shape(value)
    local kind = type(value)
    if kind ~= "table" then return {valueType = kind, value = value} end
    local result = {valueType = "table", interpretation = "shallow raw shape only", entries = {}}
    local key, count = nil, 0
    while true do
        key = next(value, key)
        if key == nil then break end
        count = count + 1
        if count > 24 then result.shapeTruncated = true; break end
        local item, keyKind = rawget(value, key), type(key)
        result.entries[count] = {key = (keyKind == "string" or keyKind == "number") and key or nil,
            keyType = keyKind, valueType = type(item),
            value = (type(item) == "number" or type(item) == "string" or type(item) == "boolean") and item or nil}
    end
    return result
end

function D.read(section, accessor, ok, value, details)
    if not D.isEnabled() then return end
    return safe(function()
        local id = (S.origin or "runtime") .. ":" .. tostring(section) .. ":" .. tostring(accessor)
        local row = S.reads[id] or {calls = 0, errors = 0, nils = 0}
        S.reads[id] = row
        row.calls = row.calls + 1
        if ok == false then row.errors = row.errors + 1 end
        if value == nil then row.nils = row.nils + 1 end
        if D.traceReads or ok == false then
            rawWrite("read", {section = section, accessor = accessor, ok = ok, result = shape(value), details = details}, false)
        end
    end)
end

function D.beginMission(meta)
    if not D.isEnabled() then return end
    safe(function()
        S.mission, S.capture, S.checks, S.events, S.reads = S.mission + 1, 0, {}, {}, {}
        S.capturing = false
        S.pending, S.settle, S.sinceCapture, S.sinceSummary = "initial_ready", 0, 0, 0
        rawWrite("mission.begin", {meta = meta, limits = D.limits, traceReads = D.traceReads,
            scope = "validation evidence; prior user success reports are not relied upon"}, true)
    end)
end

function D.beginCapture(reason)
    if not D.isEnabled() then return end
    safe(function()
        S.capture = S.capture + 1
        S.capturing, S.pending, S.sinceCapture = true, nil, 0
        rawWrite("capture.begin", {reason = reason or "unspecified"}, false)
    end)
end

function D.endCapture(meta)
    S.capturing = false -- a failed log sink must never stall later captures
    if not D.isEnabled() then return end
    safe(function() rawWrite("capture.end", meta, false) end)
end

function D.dump(name, value)
    if not D.isEnabled() then return end
    safe(function()
        local seen, nodes, truncated = {}, 0, false
        rawWrite("dump.begin", {name = name}, false)
        local function visit(path, item, depth)
            nodes = nodes + 1
            if nodes > 50000 or depth > 14 or S.limited then truncated = true; return end
            if type(item) ~= "table" then
                rawWrite("dump.value", {path = path, value = item, valueType = type(item)}, false)
                return
            end
            if seen[item] then truncated = true; rawWrite("dump.omitted", {path = path, reason = "cycle"}, false); return end
            seen[item] = true
            rawWrite("dump.container", {path = path}, false)
            local keys = {}
            for k in next, item do
                if type(k) == "string" or (type(k) == "number" and finite(k)) then keys[#keys + 1] = k else truncated = true end
                if #keys > 20000 then truncated = true; break end
            end
            table.sort(keys, function(a, b) if type(a) == type(b) then return a < b end; return type(a) < type(b) end)
            for _, k in ipairs(keys) do
                if S.limited or nodes > 50000 then truncated = true; break end
                visit(path .. "[" .. (type(k) == "number" and tostring(k) or quote(k)) .. "]", rawget(item, k), depth + 1)
            end
            seen[item] = nil
        end
        visit(name, value, 0)
        rawWrite("dump.end", {name = name, nodes = nodes, complete = not truncated}, false)
        if truncated then rawWrite("dump.incomplete", {name = name, nodes = nodes}, true) end
    end)
end

function D.summary(reason)
    if not D.isEnabled() then return end
    safe(function()
        local failures, failureCount = {}, 0
        for id, row in pairs(S.checks) do
            if (row.counts.FAIL or 0) > 0 then
                failureCount = failureCount + 1
                if failureCount <= 12 then failures[id] = {FAIL = row.counts.FAIL} end
            end
        end
        rawWrite("summary.begin", {reason = reason, bytes = S.bytes, written = S.written, dropped = S.dropped,
            truncated = S.truncated or 0, loggerErrors = S.loggerErrors,
            failureIds = failures, totalFailedChecks = failureCount, failureListTruncated = failureCount > 12,
            warning = "PASS establishes only its named oracle; missing cases remain NOT_EXERCISED."}, true)
        local keys = {}
        for id in pairs(S.checks) do keys[#keys + 1] = id end
        table.sort(keys)
        for _, id in ipairs(keys) do rawWrite("summary.check", {id = id, state = S.checks[id]}, false) end
        for _, row in ipairs((BankValidationCatalog or {}).checks or {}) do
            if S.checks[row.id] == nil then
                rawWrite("summary.coverage", {id = row.id, group = row.group, description = row.description,
                    evidence = row.evidence, outcome = "NOT_EXERCISED", oracle = row.oracle}, false)
            end
        end
        for name, counts in pairs(S.reads) do rawWrite("summary.read", {name = name, counts = counts}, false) end
        rawWrite("summary.end", {reason = reason, mission = S.mission, capture = S.capture, dropped = S.dropped,
            loggerErrors = S.loggerErrors, evidenceComplete = S.dropped == 0 and (S.truncated or 0) == 0 and S.loggerErrors == 0}, true)
    end)
end

function D.finishMission(meta)
    if not D.isEnabled() then return end
    D.emit("mission.end", meta)
    D.summary("mission_end")
end

function D.setMode(mode)
    if mode == "off" then
        if D.isEnabled() then D.emit("debug.off", {}); D.summary("debug_off") end
        D.enabled = false
        return true
    end
    if mode ~= "on" and mode ~= "trace" then return false end
    D.enabled, D.traceReads = true, mode == "trace"
    D.emit("debug.mode", {mode = mode, budgetsReset = false})
    return true
end

-- Only schedules work. The caller performs collection outside native money/save
-- callbacks. Requests coalesce; event bursts cannot cause unbounded asset scans.
function D.tick(dt, ready)
    if not D.isEnabled() or not finite(dt) or dt < 0 then return nil end
    S.sinceCapture = (S.sinceCapture or 0) + dt
    S.sinceSummary = (S.sinceSummary or 0) + dt
    S.settle = (S.settle or 0) + dt
    if not S.limited and S.sinceSummary >= D.timing.summary then S.sinceSummary = 0; D.summary("periodic") end
    if not ready or S.capturing or S.limited then return nil end
    if S.pending and S.settle >= D.timing.settle and (S.capture == 0 or S.sinceCapture >= D.timing.minimum) then return S.pending end
    if S.sinceCapture >= D.timing.interval then return "periodic" end
    return nil
end

function D.health()
    return {enabled = D.isEnabled(), traceReads = D.traceReads, mission = S.mission, capture = S.capture,
        dropped = S.dropped, loggerErrors = S.loggerErrors, truncated = S.truncated or 0, limited = S.limited}
end

function D.withSynthetic(callback)
    if not D.isEnabled() or type(callback) ~= "function" then return false end
    local previous = S.origin
    S.origin = "synthetic"
    local ok, result = pcall(callback)
    if not ok then D.check("PROBE_EXCEPTION", "FAIL", {error = tostring(result)}) end
    S.origin = previous
    return ok, result
end
