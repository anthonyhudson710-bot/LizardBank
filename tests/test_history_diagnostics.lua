dofile("scripts/BankHistory.lua")
dofile("scripts/BankHistoryStore.lua")
dofile("scripts/BankHistoryRuntime.lua")
dofile("scripts/BankUnderwriting.lua")

local count = 0
local function test(name, fn)
    if _G.test then _G.test("history diagnostics: " .. name, fn); return end
    fn(); count = count + 1; print("PASS history diagnostics: " .. name)
end
local function equal(a, b) assert(a == b, "expected " .. tostring(b) .. ", got " .. tostring(a)) end
local function copy(value)
    if type(value) ~= "table" then return value end
    assert(getmetatable(value) == nil, "diagnostic DTO has a live metatable")
    local result = {}
    for key, item in pairs(value) do
        assert(type(key) == "string" or type(key) == "number")
        assert(type(item) ~= "function" and type(item) ~= "userdata" and type(item) ~= "thread")
        if type(item) == "number" then assert(item == item and math.abs(item) ~= math.huge) end
        result[key] = copy(item)
    end
    return result
end
local function same(a, b)
    equal(type(a), type(b))
    if type(a) ~= "table" then equal(a, b); return end
    for key, value in pairs(a) do same(value, b[key]) end
    for key in pairs(b) do assert(a[key] ~= nil, "unexpected field " .. tostring(key)) end
end
local function globals(values, fn)
    local previous = {}
    for name, value in pairs(values) do previous[name] = _G[name]; _G[name] = value end
    local ok, err = pcall(fn)
    for name in pairs(values) do _G[name] = previous[name] end
    if not ok then error(err, 0) end
end
local function logger(enabled, fn)
    local events, checks, reads = {}, {}, {}
    globals({BankDiagnostics = {
        isEnabled = function() return enabled end,
        emit = function(name, data) events[#events + 1] = {name = name, data = copy(data)} end,
        check = function(id, outcome, data) checks[#checks + 1] = {id = id, outcome = outcome, data = copy(data)} end,
        read = function(section, accessor, ok, value, details)
            reads[#reads + 1] = {section = section, accessor = accessor, ok = ok, valueType = type(value), details = copy(details)}
        end
    }}, function() fn(events, checks, reads) end)
end
local function find(rows, key, value, outcome)
    for i = #rows, 1, -1 do
        if rows[i][key] == value and (outcome == nil or rows[i].outcome == outcome) then return rows[i] end
    end
end
local function occurrences(rows, name)
    local n = 0; for _, row in ipairs(rows) do if row.name == name then n = n + 1 end end; return n
end
local function stamp(day, period, time) return {day = day, period = period, dayTime = time or 0, daysPerPeriod = 1} end
local function nextPeriod(ledger)
    BankHistory.observe(ledger, stamp(ledger.last.day + 1, ledger.last.period % 12 + 1), ledger.balance)
end
local function fullYear()
    local ledger = BankHistory.new(7, stamp(1, 1, 1000), 10000); ledger.debt = 2000
    nextPeriod(ledger)
    for i = 1, 12 do
        BankHistory.record(ledger, ledger.last, ledger.balance, ledger.balance + 1000 + i, "crops", "operating")
        BankHistory.record(ledger, ledger.last, ledger.balance, ledger.balance - 300, "fuel", "operating")
        BankHistory.record(ledger, ledger.last, ledger.balance, ledger.balance - 25, "interest", "interest")
        nextPeriod(ledger)
    end
    return ledger
end
local function xmlFixture(fn)
    local db, stats = {}, {writes = 0, reads = 0, released = 0}
    globals({
        createXMLFile = function(_, path) return {path = path, values = {}} end,
        loadXMLFile = function(_, path)
            stats.reads = stats.reads + 1
            if stats.throwRead then error("debug read failure") end
            return {values = copy(db[path])}
        end,
        setXMLString = function(xml, key, value) xml.values[key] = value end,
        getXMLString = function(xml, key) return xml.values[key] end,
        saveXMLFile = function(xml)
            stats.writes = stats.writes + 1; db[xml.path] = copy(xml.values)
            if stats.corrupt then db[xml.path]["lizardBankHistory#mode"] = "strict" end
            return stats.acknowledge ~= false
        end,
        delete = function() stats.released = stats.released + 1 end,
        fileExists = function(path) return db[path] ~= nil end
    }, function() fn(stats, db) end)
end
local function runtimeFixture(fn)
    local selected = 7
    local stats = {money = 0, loan = 0, save = 0, writes = 0}
    local farms = {[7] = {id = 7, money = 10000, loan = 2000}, [8] = {id = 8, money = 9000, loan = 1000}}
    local mission = {environment = {currentMonotonicDay = 1, currentPeriod = 1, dayTime = 1000, daysPerPeriod = 1},
        missionInfo = {savegameDirectory = "/private/person/savegame1"}, getFarmId = function() return selected end}
    mission.addMoney = function(_, amount, id, kind, tail)
        stats.money = stats.money + 1
        if amount == "fail" then error("native-money-failure", 0) end
        farms[id].money = farms[id].money + amount
        return nil, "native-money", tail, nil
    end
    mission.saveSavegame = function()
        stats.save = stats.save + 1
        if stats.failSave then error("native-save-failure", 0) end
        mission.missionInfo.savegameDirectory = "/private/person/tempsavegame"
        return nil, "native-save", nil
    end
    for _, farm in pairs(farms) do
        farm.getBalance = function(self) return self.money end
        farm.getLoan = function(self) return self.loan end
        farm.changeLoan = function(self, amount, tail)
            stats.loan = stats.loan + 1; self.loan = self.loan + amount
            mission:addMoney(amount, self.id, 3, tail)
            return "native-loan", nil, tail
        end
    end
    globals({g_farmManager = {getFarmById = function(_, id) return farms[id] end},
        g_localPlayer = false, MoneyType = {CROP = 1, COST = 2, LOAN = 3},
        BankFinanceDataSource = {classifyMoneyType = function(kind)
            return kind == 1 and "crop" or "expense", "operating", "fixture category"
        end},
        BankHistoryStore = {available = function() return true end, read = function() return nil end,
            write = function() stats.writes = stats.writes + 1; return true end}
    }, function()
        local runtime = BankHistoryRuntime.new(mission); runtime:start()
        local ok, err = pcall(fn, {runtime = runtime, mission = mission, farms = farms, stats = stats,
            selectFarm = function(id) selected = id end})
        runtime:delete()
        if not ok then error(err, 0) end
    end)
end

test("logging changes neither economic calls nor exact return slots", function()
    local function run(enabled)
        local result
        logger(enabled, function(events)
            runtimeFixture(function(c)
                local returns = {n = 0}
                local function packed(...) return {n = select("#", ...), ...} end
                returns.money = packed(c.mission:addMoney(25, 7, 1, 77))
                returns.loan = packed(c.farms[7]:changeLoan(100, 88))
                returns.save = packed(c.mission:saveSavegame())
                result = {ledger = copy(c.runtime.active), stats = copy(c.stats), returns = returns,
                    cash = c.farms[7].money, debt = c.farms[7].loan}
                if not enabled then equal(#events, 0) end
            end)
        end)
        return result
    end
    local disabled, enabled = run(false), run(true)
    same(disabled, enabled)
    equal(enabled.stats.money, 2); equal(enabled.stats.loan, 1); equal(enabled.stats.save, 1)
    equal(enabled.returns.money.n, 4); equal(enabled.returns.save.n, 3)
end)

test("nested nonactive and unreadable calls have distinct honest trace paths", function()
    logger(true, function(events, checks)
        runtimeFixture(function(c)
            c.farms[7]:changeLoan(50)
            local outer = find(events, "name", "history.transaction.end")
            equal(outer.data.kind, "loan"); equal(outer.data.cashAfter - outer.data.cashBefore, 50)
            local nested
            for _, event in ipairs(events) do
                if event.name == "history.transaction.end" and event.data.path == "nested_accounted_by_parent" then nested = event.data end
            end
            assert(nested); equal(nested.parentTransactionId, outer.data.transactionId); equal(nested.observed, false)
            equal(find(checks, "id", "HISTORY_FINANCING_DELTA_MATCH").outcome, "PASS")
            c.mission:addMoney(10, 8, 1)
            equal(find(events, "name", "history.transaction.end").data.observed, false)
            c.farms[7].changeLoan(c.farms[8], 15)
            local foreign = find(events, "name", "history.transaction.end").data
            equal(foreign.path, "nonactive_loan_target"); equal(foreign.farmId, nil)
            c.selectFarm(0); c.mission:addMoney(10, 7, 1)
            equal(find(events, "name", "history.transaction.end").data.observed, false)
            assert(find(events, "name", "history.readiness"))
        end)
    end)
end)

test("native errors retain exact errors and observers recover", function()
    logger(true, function(events, checks)
        runtimeFixture(function(c)
            local ok, err = pcall(c.mission.addMoney, c.mission, "fail", 7, 1)
            equal(ok, false); equal(err, "native-money-failure"); equal(c.stats.money, 1)
            equal(c.runtime.depth, 0); assert(find(events, "name", "history.native.error"))
            equal(find(checks, "id", "HISTORY_TRANSACTION_NATIVE_ONCE").data.nativeCallCount, 1)
            c.mission:addMoney(5, 7, 1); equal(c.farms[7].money, 10005)
            c.stats.failSave = true
            ok, err = pcall(c.mission.saveSavegame, c.mission)
            equal(ok, false); equal(err, "native-save-failure"); equal(c.stats.writes, 0)
            equal(find(events, "name", "history.save.end").data.stage, "native_callback_error")
        end)
    end)
end)

test("throwing diagnostic methods cannot stop native transactions", function()
    for _, failedMethod in ipairs({"isEnabled", "emit", "read", "check"}) do
        local bad = {isEnabled = function() return true end}
        bad[failedMethod] = function() error("logger failed") end
        globals({BankDiagnostics = bad}, function()
            runtimeFixture(function(c)
                c.mission:addMoney(5, 7, 1); c.farms[7]:changeLoan(20)
                equal(c.farms[7].money, 10025); equal(c.stats.money, 2); equal(c.stats.loan, 1)
                equal(c.runtime.active.current.operatingRevenue, 5)
                equal(c.runtime.active.current.financingInflow, 20)
            end)
        end)
    end
end)

test("sample trace excludes ticking time but captures material state changes", function()
    logger(true, function(events)
        runtimeFixture(function(c)
            local initial = occurrences(events, "history.sample.changed")
            for i = 1, 50 do c.mission.environment.dayTime = 1000 + i; c.runtime:sample() end
            equal(occurrences(events, "history.sample.changed"), initial)
            c.farms[7].money = c.farms[7].money + 1; c.runtime:sample()
            equal(occurrences(events, "history.sample.changed"), initial + 1)
            assert(find(events, "name", "history.gap"))
        end)
    end)
end)

test("save traces expose stages and basenames without promising native completion", function()
    logger(true, function(events)
        runtimeFixture(function(c)
            c.mission:saveSavegame()
            local start = find(events, "name", "history.save.begin").data
            equal(start.directoryBefore, "savegame1")
            local sidecar = find(events, "name", "history.save.sidecar.begin").data
            equal(sidecar.directory, "tempsavegame"); equal(sidecar.filename, "lizardBankHistory_7.xml")
            equal(sidecar.transactionId, start.transactionId)
            equal(find(events, "name", "history.save.end").data.stage, "native_callback_returned")
        end)
    end)
end)

test("XML verification reads only in debug and checks full persisted contract", function()
    for _, enabled in ipairs({false, true}) do
        logger(enabled, function(_, checks)
            xmlFixture(function(stats)
                local ledger = fullYear()
                local ok, err = BankHistoryStore.write("/private/person/history.xml", ledger)
                equal(ok, true); equal(err, nil); equal(stats.writes, 1)
                equal(stats.reads, enabled and 1 or 0); equal(stats.released, enabled and 2 or 1)
                local check = find(checks, "id", "HISTORY_XML_READBACK")
                if enabled then equal(check.outcome, "PASS"); assert(check.data.fieldsCompared > 250)
                else equal(check, nil) end
            end)
        end)
    end
end)

test("failed readback never changes acknowledged write result", function()
    logger(true, function(_, checks)
        xmlFixture(function(stats)
            stats.corrupt = true
            local ok, err = BankHistoryStore.write("history.xml", fullYear())
            equal(ok, true); equal(err, nil); equal(stats.writes, 1)
            local check = find(checks, "id", "HISTORY_XML_READBACK")
            equal(check.outcome, "FAIL"); equal(check.data.firstMismatches[1], "mode")
            stats.corrupt, stats.throwRead = false, true
            ok, err = BankHistoryStore.write("history.xml", fullYear())
            equal(ok, true); equal(err, nil); equal(stats.writes, 2)
            equal(find(checks, "id", "HISTORY_XML_READBACK").outcome, "UNAVAILABLE")
        end)
    end)
end)

test("unacknowledged XML write cannot emit passing readback", function()
    logger(true, function(_, checks)
        xmlFixture(function(stats)
            stats.acknowledge = false
            equal(BankHistoryStore.write("history.xml", fullYear()), false)
            equal(stats.reads, 0)
            equal(find(checks, "id", "HISTORY_XML_WRITE").outcome, "FAIL")
            equal(find(checks, "id", "HISTORY_XML_READBACK"), nil)
        end)
    end)
end)

test("period and resume checks distinguish complete partial and unexercised", function()
    logger(true, function(events, checks)
        runtimeFixture(function()
            equal(find(checks, "id", "HISTORY_RESUME_ANCHOR").outcome, "NOT_EXERCISED")
        end)
        local ledger = BankHistory.new(7, stamp(1, 1, 100), 500)
        nextPeriod(ledger); equal(find(checks, "id", "HISTORY_PERIOD_RECONCILIATION").outcome, "WARN")
        BankHistory.record(ledger, ledger.last, 500, 600, "crop", "operating")
        nextPeriod(ledger)
        local period = find(events, "name", "history.period.close").data
        equal(period.difference, 0); equal(find(checks, "id", "HISTORY_PERIOD_RECONCILIATION").outcome, "PASS")
        local _, resumed = BankHistory.resume(ledger, 7, ledger.last, ledger.balance)
        equal(resumed, true); equal(find(checks, "id", "HISTORY_RESUME_ANCHOR").outcome, "PASS")
        local later = copy(ledger.last); later.dayTime = later.dayTime + 16
        _, resumed = BankHistory.resume(ledger, 7, later, ledger.balance)
        equal(resumed, false); equal(find(checks, "id", "HISTORY_RESUME_ANCHOR").outcome, "WARN")
        equal(find(events, "name", "history.resume").data.rejectionReasons[1], "time_anchor")
    end)
end)

test("withheld models never claim executed scoring or supported seasonality", function()
    logger(true, function(events, checks)
        local snapshot = {farm = {id = 7}, cash = {status = "available", value = 10000}, debt = {status = "available", value = 2000}}
        local ledger = BankHistory.new(7, stamp(1, 1), 10000)
        local model = BankUnderwriting.prepare(snapshot, BankHistory.report(ledger))
        equal(model.assessment.score, nil)
        equal(find(checks, "id", "UNDERWRITING_EVIDENCE_GATE").outcome, "UNAVAILABLE")
        equal(find(checks, "id", "UNDERWRITING_FORECAST_SOURCES").outcome, "UNAVAILABLE")
        equal(find(checks, "id", "UNDERWRITING_SCORE_ARITHMETIC"), nil)
        ledger = fullYear()
        snapshot.cash.value = ledger.balance
        model = BankUnderwriting.prepare(snapshot, BankHistory.report(ledger))
        equal(find(checks, "id", "UNDERWRITING_EVIDENCE_GATE").outcome, "PASS")
        equal(find(checks, "id", "UNDERWRITING_SCORE_ARITHMETIC").outcome, "PASS")
        local forecast = find(events, "name", "underwriting.forecast").data
        equal(#forecast.sources, 12); equal(forecast.allSourcesMatched, true)
        equal(find(checks, "id", "UNDERWRITING_FORECAST_SOURCES").outcome, "PASS")
        local enabled = copy(model)
        globals({BankDiagnostics = {isEnabled = function() return false end}}, function()
            same(enabled, BankUnderwriting.prepare(snapshot, BankHistory.report(ledger)))
        end)
    end)
end)

test("teardown proves owned restoration while preserving newer wrappers", function()
    logger(true, function(_, checks)
        runtimeFixture(function(c)
            local bank = c.mission.addMoney
            local newer = function(...) return bank(...) end
            c.mission.addMoney = newer
            c.runtime:delete(); equal(c.mission.addMoney, newer)
            local warning = find(checks, "id", "HISTORY_HOOK_RESTORE", "WARN")
            assert(warning); equal(warning.data.otherWrapperPreserved, true)
            c.mission:addMoney(1, 7, 1); equal(c.stats.money, 1)
        end)
    end)
end)

if not _G.test then print(tostring(count) .. " history diagnostics tests passed") end
