dofile("scripts/BankHistory.lua")
dofile("scripts/BankHistoryStore.lua")
dofile("scripts/BankUnderwriting.lua")

local count = 0
local function test(name, fn)
    if _G.test then _G.test("history: " .. name, fn); return end
    fn(); count = count + 1; print("PASS history: " .. name)
end
local function equal(a, b) assert(a == b, "expected " .. tostring(b) .. ", got " .. tostring(a)) end
local function stamp(day, period, time) return {day = day, period = period, dayTime = time or 0, daysPerPeriod = 1} end
local function nextPeriod(ledger)
    local last = ledger.last
    BankHistory.observe(ledger, stamp(last.day + 1, last.period % 12 + 1), ledger.balance)
end
local function completeYear()
    local ledger = BankHistory.new(7, stamp(1, 3, 100), 2000)
    nextPeriod(ledger)
    for _ = 1, 12 do
        BankHistory.record(ledger, ledger.last, ledger.balance, ledger.balance + 1000, "harvest", "operating")
        BankHistory.record(ledger, ledger.last, ledger.balance, ledger.balance - 800, "upkeep", "operating")
        BankHistory.record(ledger, ledger.last, ledger.balance, ledger.balance - 100, "interest", "interest")
        nextPeriod(ledger)
    end
    return ledger
end
local function copied(t)
    local result = {}; for k, v in pairs(t) do result[k] = type(v) == "table" and copied(v) or v end; return result
end
local function withXml(fn)
    local names = {"createXMLFile", "loadXMLFile", "setXMLString", "getXMLString", "saveXMLFile", "delete", "fileExists"}
    local saved, db, released = {}, {}, 0
    for _, name in ipairs(names) do saved[name] = _G[name] end
    _G.createXMLFile = function(_, path) return {path = path, values = {}} end
    _G.loadXMLFile = function(_, path) return {path = path, values = copied(db[path])} end
    _G.setXMLString = function(xml, key, value) assert(type(value) == "string"); xml.values[key] = value end
    _G.getXMLString = function(xml, key) return xml.values[key] end
    _G.saveXMLFile = function(xml) db[xml.path] = copied(xml.values); return true end
    _G.delete = function() released = released + 1 end
    _G.fileExists = function(path) return db[path] ~= nil end
    local ok, err = pcall(fn, db, function() return released end)
    for _, name in ipairs(names) do _G[name] = saved[name] end
    if not ok then error(err, 0) end
end

test("first partial month does not fabricate earlier activity", function()
    local ledger = BankHistory.new(7, stamp(4, 7, 43200000), 100)
    equal(ledger.current.complete, false)
    equal(ledger.current.reconciled, false)
    equal(#ledger.periods, 0)
    local report = BankHistory.report(ledger)
    equal(report.farmId, 7)
    equal(#report.materialGaps, 0)
    equal(report.current.operatingRevenue, 0)
end)

test("verified events keep operating capital financing and interest separate", function()
    local ledger = BankHistory.new(7, stamp(1, 1), 1000)
    nextPeriod(ledger)
    for _, row in ipairs({{500, "harvest", "operating"}, {-100, "fuel", "operating"}, {-10, "interest", "interest"},
        {300, "machineSale", "capital"}, {-200, "land", "capital"}, {1000, "loan", "financing"}, {-400, "repay", "financing"}}) do
        BankHistory.record(ledger, ledger.last, ledger.balance, ledger.balance + row[1], row[2], row[3])
    end
    local p = ledger.current
    equal(p.operatingRevenue, 500); equal(p.operatingExpense, 100); equal(p.interestExpense, 10)
    equal(p.capitalInflow, 300); equal(p.capitalOutflow, 200)
    equal(p.financingInflow, 1000); equal(p.financingOutflow, 400)
    equal(p.closingCash, 2090); equal(p.reconciled, true)
    equal(p.categories.harvest.inflow, 500)
end)

test("current unknown cash movements gate current assessment", function()
    local ledger = completeYear()
    BankHistory.record(ledger, ledger.last, ledger.balance, ledger.balance + 100, "unknown", "unclassified")
    local report = BankHistory.report(ledger)
    assert(#report.materialGaps > 0)
    local snapshot = {farm = {id = 7}, cash = {status = "available", value = ledger.balance}, debt = {status = "available", value = 10000}}
    equal(BankUnderwriting.prepare(snapshot, report).assessment.score, nil)
end)

test("cash mutation outside observer breaks reconciliation", function()
    local ledger = completeYear()
    BankHistory.observe(ledger, ledger.last, ledger.balance + 40)
    equal(ledger.current.reconciled, false)
    assert(#BankHistory.report(ledger).materialGaps > 0)
end)

test("twelve full observed periods become model evidence across cycle rollover", function()
    local ledger = completeYear()
    equal(ledger.cycle, 1)
    equal(ledger.current.month, 4)
    equal(#ledger.periods, 13)
    equal(ledger.periods[1].complete, false)
    local snapshot = {farm = {id = 7}, cash = {status = "available", value = ledger.balance}, debt = {status = "available", value = 10000}}
    local model = BankUnderwriting.prepare(snapshot, BankHistory.report(ledger))
    equal(model.history.completePeriodCount, 12)
    equal(model.history.totals.operatingRevenue, 12000)
    equal(model.assessment.status, "available")
end)

test("same seasonal slot after an unobserved year never compresses history", function()
    local ledger = completeYear()
    BankHistory.observe(ledger, stamp(ledger.last.day + 12, ledger.last.period), ledger.balance)
    equal(#ledger.periods, 0)
    equal(ledger.cycle, 0)
    equal(ledger.current.complete, false)
    assert(#BankHistory.report(ledger).materialGaps > 0)
end)

test("rollback and skipped seasonal boundary restart calendar chain", function()
    for _, target in ipairs({stamp(1, 2), stamp(15, 8)}) do
        local ledger = completeYear()
        BankHistory.observe(ledger, target, ledger.balance)
        equal(#ledger.periods, 0)
        equal(ledger.current.complete, false)
    end
end)

test("late boundary observation cannot claim a full current period", function()
    local ledger = BankHistory.new(7, stamp(1, 1), 100)
    BankHistory.observe(ledger, stamp(2, 2, 120000), 100)
    equal(ledger.current.complete, false)
    assert(#BankHistory.report(ledger).materialGaps > 0)
end)

test("bounded retention keeps at most thirty-six closed periods", function()
    local ledger = BankHistory.new(7, stamp(1, 1), 100)
    for _ = 1, 45 do nextPeriod(ledger) end
    equal(#ledger.periods, 36)
end)

test("resume requires exact farm cash calendar and day-length anchor", function()
    local ledger = completeYear()
    local resumed, ok = BankHistory.resume(ledger, 7, ledger.last, ledger.balance)
    equal(ok, true); equal(#resumed.periods, 13)
    resumed.current.operatingRevenue = 900
    equal(ledger.current.operatingRevenue, 0)
    local changed = copied(ledger.last); changed.daysPerPeriod = 3
    for _, row in ipairs({{8, ledger.last, ledger.balance}, {7, ledger.last, ledger.balance + 1}, {7, changed, ledger.balance}}) do
        local fresh, valid = BankHistory.resume(ledger, row[1], row[2], row[3])
        equal(valid, false); equal(#fresh.periods, 0)
    end
end)

test("typed XML round trip preserves exact anchor and complete evidence", function()
    withXml(function(_, released)
        local ledger = completeYear(); ledger.debt = 10000
        local ok = BankHistoryStore.write("save/history.xml", ledger)
        equal(ok, true)
        local loaded, err = BankHistoryStore.read("save/history.xml")
        assert(loaded, err); equal(released(), 2)
        equal(loaded.balance, ledger.balance); equal(loaded.debt, 10000)
        equal(loaded.periods[2].reconciled, true)
        equal(loaded.periods[2].operatingRevenue, 1000)
        equal(loaded.current.complete, true)
        equal(select(2, BankHistory.resume(loaded, 7, ledger.last, ledger.balance)), true)
    end)
end)

test("corrupted XML cannot manufacture reconciled cash evidence", function()
    withXml(function(db)
        local ledger = completeYear(); BankHistoryStore.write("history.xml", ledger)
        db["history.xml"]["lizardBankHistory.period(1)#closingCash"] = "9999"
        local loaded = BankHistoryStore.read("history.xml")
        assert(loaded)
        equal(loaded.periods[2].complete, false)
        equal(loaded.periods[2].reconciled, false)
        db["history.xml"]["lizardBankHistory#count"] = "1000000"
        equal(BankHistoryStore.read("history.xml"), nil)
    end)
end)

test("failed XML save releases its handle and reports failure", function()
    withXml(function(_, released)
        _G.saveXMLFile = function() error("disk unavailable") end
        local ok, err = BankHistoryStore.write("history.xml", completeYear())
        equal(ok, false); assert(err:find("disk unavailable", 1, true)); equal(released(), 1)
    end)
end)

test("invalid cash deltas stay partial without storing nonfinite amounts", function()
    local ledger = BankHistory.new(7, stamp(1, 1), -9e14)
    BankHistory.record(ledger, ledger.last, -9e14, 9e14, "overflow", "operating")
    equal(ledger.current.operatingRevenue, 0)
    equal(ledger.current.complete, false)
    equal(ledger.balance, 9e14)
end)

test("bounded category overflow is unclassified in details and totals", function()
    local ledger = BankHistory.new(7, stamp(1, 1), 1000)
    nextPeriod(ledger)
    for i = 1, 130 do BankHistory.record(ledger, ledger.last, ledger.balance, ledger.balance + 1, "category" .. i, "operating") end
    local categories = 0; for _ in pairs(ledger.current.categories) do categories = categories + 1 end
    equal(categories, 129)
    equal(ledger.current.operatingRevenue, 128)
    equal(ledger.current.unclassifiedInflow, 2)
    equal(ledger.current.categories.other_unclassified.inflow, 2)
    equal(ledger.current.complete, false)
end)

test("invalid classifications and interest refunds remain explicit unknown flows", function()
    local ledger = BankHistory.new(7, stamp(1, 1), 1000)
    BankHistory.record(ledger, ledger.last, ledger.balance, ledger.balance + 10, "bad", "nonexistent")
    BankHistory.record(ledger, ledger.last, ledger.balance, ledger.balance + 20, "refund", "interest")
    equal(ledger.current.unclassifiedInflow, 30)
    equal(ledger.current.interestExpense, 0)
    equal(ledger.current.categories.bad.classification, "unclassified")
end)

test("XML success has no error text and missing write acknowledgement fails closed", function()
    withXml(function()
        local ledger = completeYear()
        ledger.debt = 0
        local ok, message = BankHistoryStore.write("history.xml", ledger)
        equal(ok, true); equal(message, nil)
        local loaded, loadError = BankHistoryStore.read("history.xml")
        assert(loaded ~= nil); equal(loadError, nil)
        _G.saveXMLFile = function() return nil end
        local saved, err = BankHistoryStore.write("history.xml", ledger)
        equal(saved, false); assert(type(err) == "string")
    end)
end)

if not _G.test then print(tostring(count) .. " history tests passed") end
