-- Isolated logger fixtures; no global debug state leaks into native API stubs.
local function fixture(config)
    local lines = {}
    local env = setmetatable({BankDebugConfig = config or {enabled = true, traceReads = true}, g_time = 100,
        BankValidationCatalog = {checks = {{id = "CASE-1", group = "fixture", description = "Unplayed case", evidence = "manual", oracle = "native UI"}}},
        print = function(line) lines[#lines + 1] = line end}, {__index = _G})
    local chunk = assert(loadfile("scripts/BankDiagnostics.lua")); setfenv(chunk, env); chunk()
    return env.BankDiagnostics, lines, env
end

test("diagnostics off performs no native serialization or writes", function()
    local d, lines = fixture({enabled = false})
    local hostile = setmetatable({}, {__index = function() error("accessed") end, __tostring = function() error("stringified") end})
    d.emit("off", hostile); d.read("off", "getter", true, hostile); d.check("OFF", "PASS", hostile); d.dump("off", hostile)
    assertEqual(#lines, 0)
    assertEqual(d.health().loggerErrors, 0)
end)

test("diagnostics JSON escapes strings and marks unsupported numeric values", function()
    local d, lines = fixture()
    d.emit("escaping", {text = "quote\" slash\\ newline\n nul\0", missing = 0 / 0, infinite = math.huge, zero = 0})
    local text = lines[1]
    assertContains(text, '\\"'); assertContains(text, '\\n'); assertContains(text, '\\u0000')
    assertContains(text, '"_unavailable":"nonfinite"'); assertContains(text, '"zero":0')
    assertFalse(text:find("\n", 1, true) ~= nil)
end)

test("diagnostics native table reads never execute metamethods or recurse into native graph", function()
    local d, lines = fixture()
    local native = setmetatable({scalar = 3, nested = {}}, {__index = function() error("native index") end, __tostring = function() error("native tostring") end})
    native.nested.parent = native
    d.read("farm", "getter", true, native, {basis = "fixture"})
    assertEqual(d.health().loggerErrors, 0)
    assertContains(lines[1], "shallow raw shape only")
    assertFalse(lines[1]:find("native index", 1, true) ~= nil)
    native.scalar = 999
    assertFalse(lines[1]:find("999", 1, true) ~= nil)
end)

test("diagnostics cycles line limits and truncation are explicit rather than crashes", function()
    local d, lines = fixture({enabled = true, maxLineBytes = 512})
    local t = {}; t.self = t
    d.emit("cycle", t)
    assertContains(lines[1], '"evidenceTruncated":true')
    d.emit("large", {long = string.rep("X", 9000)})
    assertContains(lines[2], "line_limit")
    assertTrue(d.health().truncated >= 2)
    assertEqual(d.health().loggerErrors, 0)
end)

test("diagnostics budget exhaustion still writes an explicit incomplete summary", function()
    local d, lines = fixture({enabled = true, maxEvents = 10})
    for i = 1, 25 do d.emit("event", {i = i}) end
    d.check("AFTER_LIMIT", "FAIL", {})
    d.summary("final")
    assertTrue(d.health().dropped > 0)
    local text = table.concat(lines, "\n")
    assertContains(text, '"event":"log.limit"')
    assertContains(text, '"event":"summary.end"')
    assertContains(text, '"evidenceComplete":false')
    assertContains(text, '"AFTER_LIMIT":{"FAIL":1}')
    assertContains(text, '"FAIL":1')
    for _ = 1, 100 do d.summary("repeated") end
    assertTrue(#lines <= 26, "Emergency summary reserve must also be bounded")
end)

test("diagnostics outcomes are counted independently and never overwrite failures", function()
    local d, lines = fixture()
    d.check("CHECK", "FAIL", {expected = 2, actual = 3})
    d.check("CHECK", "PASS", {expected = 2, actual = 2})
    d.summary("test")
    local text = table.concat(lines, "\n")
    assertContains(text, '"FAIL":1'); assertContains(text, '"PASS":1')
    assertContains(text, '"id":"CASE-1"'); assertContains(text, '"outcome":"NOT_EXERCISED"')
end)

test("diagnostic automatic captures coalesce and occur only after settling outside callbacks", function()
    local d = fixture()
    d.beginMission({})
    assertEqual(d.tick(1000, true), nil)
    assertEqual(d.tick(1000, true), "initial_ready")
    d.beginCapture("initial"); d.endCapture({})
    for i = 1, 100 do d.emit("history.transaction.end", {transactionId = i}) end
    assertEqual(d.tick(2000, true), nil)
    assertEqual(d.tick(13000, true), "history.transaction.end")
    d.beginCapture("money"); d.endCapture({})
    assertEqual(d.tick(1000, false), nil)
end)

test("synthetic checks are labeled and never schedule a native asset capture", function()
    local d, lines = fixture()
    d.beginMission({}); d.beginCapture("baseline"); d.endCapture({})
    local ok = d.withSynthetic(function()
        d.check("GATE", "PASS", {})
        d.emit("history.transaction.end", {})
    end)
    assertTrue(ok)
    assertEqual(d.tick(16000, true), nil)
    d.emit("real", {})
    local text = table.concat(lines, "\n")
    assertContains(text, '"id":"SYNTHETIC_GATE"')
    assertContains(text, '"origin":"synthetic"')
    assertContains(lines[#lines], '"origin":"runtime"')
end)

test("logger sink failure and recursive logging cannot interrupt the game", function()
    local d, _, env = fixture()
    env.print = function() error("sink failed") end
    assertTrue(pcall(d.emit, "event", {}))
    assertEqual(d.health().loggerErrors, 1)
    env.print = function() d.emit("recursive", {}) end
    assertTrue(pcall(d.emit, "outer", {}))
    assertEqual(d.health().loggerErrors, 1)
end)

test("snapshot dumps retain empty collections and distinct number/string identifiers", function()
    local d, lines = fixture()
    d.dump("snapshot", {items = {}, ids = {[1] = "numeric", ["1"] = "string"}})
    local text = table.concat(lines, "\n")
    assertContains(text, '"event":"dump.container"')
    assertContains(text, '[1]')
    assertContains(text, '[\\"1\\"]')
    assertContains(text, '"complete":true')
end)

test("failed capture-end logging and abandoned missions never stall later automatic captures", function()
    local d, _, env = fixture()
    d.beginMission({}); d.beginCapture("baseline")
    local sink = env.print
    env.print = function() error("end capture sink failure") end
    d.endCapture({ok = true})
    env.print = sink
    d.emit("history.transaction.end", {})
    assertEqual(d.tick(16000, true), "history.transaction.end")
    d.beginCapture("abandoned")
    d.beginMission({})
    assertEqual(d.tick(2000, true), "initial_ready")
    assertEqual(d.health().loggerErrors, 1)
end)

test("pure validation probes run in host without touching game globals", function()
    local d, lines, env = fixture()
    env.g_currentMission = setmetatable({}, {__index = function() error("probe touched mission") end})
    env.g_farmManager = setmetatable({}, {__index = function() error("probe touched farm manager") end})
    for _, path in ipairs({"scripts/BankHistory.lua", "scripts/BankUnderwriting.lua", "scripts/BankValidationProbes.lua"}) do
        local chunk = assert(loadfile(path)); setfenv(chunk, env); chunk()
    end
    assertTrue(env.BankValidationProbes.run())
    local text = table.concat(lines, "\n")
    assertContains(text, '"id":"SYNTHETIC_MODEL_KNOWN_ANSWER"')
    assertFalse(text:find('"outcome":"FAIL"', 1, true) ~= nil)
    assertContains(text, '"event":"probe.end"')
    assertEqual(d.health().loggerErrors, 0)
end)
