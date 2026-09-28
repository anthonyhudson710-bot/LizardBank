dofile("scripts/BankHistory.lua")
dofile("scripts/BankHistoryRuntime.lua")

local count = 0
local function test(name, fn)
    if _G.test then _G.test("history runtime: " .. name, fn); return end
    fn(); count = count + 1; print("PASS history runtime: " .. name)
end
local function equal(a, b) assert(a == b, "expected " .. tostring(b) .. ", got " .. tostring(a)) end
local function copied(t)
    local result = {}; for k, v in pairs(t) do result[k] = type(v) == "table" and copied(v) or v end; return result
end
local function fixture(fn)
    local names = {"g_farmManager", "g_localPlayer", "BankFinanceDataSource", "MoneyType", "BankHistoryStore"}
    local saved = {}; for _, name in ipairs(names) do saved[name] = _G[name] end
    local selected, store, writes, moneyCalls, loanCalls, saveCalls = 7, {}, {}, 0, 0, 0
    local farms = {[7] = {money = 10000, loan = 2000}, [8] = {money = 20000, loan = 3000}}
    local mission = {environment = {currentMonotonicDay = 1, currentPeriod = 1, dayTime = 1000, daysPerPeriod = 1},
        missionInfo = {savegameDirectory = "savegame1"}, getFarmId = function() return selected end}
    _G.MoneyType = {CROP = 1, EXPENSE = 2, LOAN = 3}
    _G.BankFinanceDataSource = {classifyMoneyType = function(kind)
        if kind == 1 then return "crop", "operating", "mock documented category" end
        if kind == 2 then return "expenses", "operating", "mock documented category" end
        return "unknown", "unclassified", "mock unknown category"
    end}
    mission.addMoney = function(_, amount, id, moneyType, flag)
        moneyCalls = moneyCalls + 1
        farms[id].money = farms[id].money + amount
        return nil, "native-money", flag
    end
    mission.saveSavegame = function()
        saveCalls = saveCalls + 1
        if mission.failSave then return false, "native-failure" end
        mission.missionInfo.savegameDirectory = "tempsavegame"
        return nil, "native-save"
    end
    local function makeFarm(id)
        local farm = farms[id]
        farm.getBalance = function(self) return self.money end
        farm.getLoan = function(self) return self.loan end
        farm.changeLoan = function(self, delta, flag)
            loanCalls = loanCalls + 1
            self.loan = self.loan + delta
            mission:addMoney(delta, id, MoneyType.LOAN, flag)
            return "native-loan", nil, flag
        end
    end
    makeFarm(7); makeFarm(8)
    _G.g_farmManager = {getFarmById = function(_, id) return farms[id] end}
    _G.g_localPlayer = nil
    _G.BankHistoryStore = {available = function() return true end,
        read = function(path) return store[path] and copied(store[path]) or nil, "mock absent" end,
        write = function(path, ledger) writes[#writes + 1] = path; store[path] = copied(ledger); return true end}
    local originals = {money = mission.addMoney, save = mission.saveSavegame, loan7 = farms[7].changeLoan, loan8 = farms[8].changeLoan}
    local runtime = BankHistoryRuntime.new(mission)
    runtime:start()
    local context = {mission = mission, farms = farms, runtime = runtime, store = store, writes = writes, originals = originals,
        selectFarm = function(id) selected = id end,
        counts = function() return moneyCalls, loanCalls, saveCalls end,
        newRuntime = function() return BankHistoryRuntime.new(mission) end,
        replaceFarm = function(id, money, loan) farms[id] = {money = money, loan = loan}; makeFarm(id) end}
    local ok, err = pcall(fn, context)
    runtime:delete()
    for _, name in ipairs(names) do _G[name] = saved[name] end
    if not ok then error(err, 0) end
end

test("money wrapper preserves exact native execution and nil returns", function()
    fixture(function(c)
        local a, b, flag = c.mission:addMoney(500, 7, MoneyType.CROP, 99)
        equal(a, nil); equal(b, "native-money"); equal(flag, 99)
        equal(c.counts(), 1)
        equal(c.farms[7].money, 10500)
        equal(c.runtime.active.current.operatingRevenue, 500)
    end)
end)

test("nested native loan money call is recorded once as financing", function()
    fixture(function(c)
        local a, b, flag = c.farms[7]:changeLoan(1000, 88)
        equal(a, "native-loan"); equal(b, nil); equal(flag, 88)
        local money, loan = c.counts(); equal(money, 1); equal(loan, 1)
        equal(c.runtime.active.current.financingInflow, 1000)
        equal(c.runtime.active.current.operatingRevenue, 0)
        equal(c.runtime.active.current.unclassifiedInflow, 0)
        equal(c.runtime.active.current.events, 1)
        c.runtime:sample()
        equal(#BankHistory.report(c.runtime.active).materialGaps, 0)
    end)
end)

test("loan repayment is financing outflow and never operating expense", function()
    fixture(function(c)
        c.farms[7]:changeLoan(-500)
        equal(c.runtime.active.current.financingOutflow, 500)
        equal(c.runtime.active.current.operatingExpense, 0)
        equal(c.runtime.active.debt, 1500)
    end)
end)

test("unmatched native debt mutation creates an explicit current gap", function()
    fixture(function(c)
        c.farms[7].loan = 9000
        c.runtime:sample()
        local report = c.runtime:report()
        assert(#report.materialGaps > 0)
        equal(c.runtime.active.debt, 9000)
        equal(c.runtime.active.current.financingInflow, 0)
    end)
end)

test("old farm hooks are removed and cannot target the new active farm", function()
    fixture(function(c)
        local old = c.runtime.active
        c.selectFarm(8); c.runtime:sample()
        equal(c.farms[7].changeLoan, c.originals.loan7)
        equal(c.runtime.farmId, 8)
        c.farms[7]:changeLoan(500)
        equal(c.runtime.active.current.events, 0)
        equal(c.runtime.active.balance, 20000)
        assert(old.current.complete == false)
        c.farms[8]:changeLoan(1000)
        equal(c.runtime.active.current.financingInflow, 1000)
        equal(#c.runtime.hooks, 3)
    end)
end)

test("replacement farm object updates observer references", function()
    fixture(function(c)
        local oldFarm = c.farms[7]
        c.replaceFarm(7, 10000, 2000)
        c.runtime:sample()
        equal(c.runtime.farm, c.farms[7])
        equal(oldFarm.changeLoan, c.originals.loan7)
        c.farms[7]:changeLoan(300)
        equal(c.runtime.active.current.financingInflow, 300)
    end)
end)

test("unavailable farm clears stale active report", function()
    fixture(function(c)
        c.selectFarm(0); c.runtime:sample(); c.runtime:sample()
        equal(c.runtime.active, nil)
        equal(c.runtime:report().farmId, nil)
        equal(c.farms[7].changeLoan, c.originals.loan7)
    end)
end)

test("save callback uses current temporary directory and preserves native returns", function()
    fixture(function(c)
        c.mission:addMoney(40, 7, MoneyType.CROP)
        local a, b = c.mission:saveSavegame()
        equal(a, nil); equal(b, "native-save")
        equal(c.writes[1], "tempsavegame/lizardBankHistory_7.xml")
        equal(c.store[c.writes[1]].balance, 10040)
        equal(select(3, c.counts()), 1)
    end)
end)

test("saved exact cash debt and calendar anchor resumes without callback duplication", function()
    fixture(function(c)
        c.mission:addMoney(40, 7, MoneyType.CROP)
        c.mission:saveSavegame()
        c.runtime:delete()
        local resumed = c.newRuntime(); resumed:start()
        equal(resumed.active.current.operatingRevenue, 40)
        equal(#resumed.hooks, 3)
        c.mission:addMoney(10, 7, MoneyType.CROP)
        equal(resumed.active.current.operatingRevenue, 50)
        equal(c.counts(), 2)
        resumed:delete()
    end)
end)

test("stale sidecar cash or debt never imports prior continuity", function()
    fixture(function(c)
        c.mission:addMoney(40, 7, MoneyType.CROP)
        c.mission:saveSavegame(); c.runtime:delete()
        c.farms[7].loan = c.farms[7].loan + 100
        local resumed = c.newRuntime(); resumed:start()
        equal(resumed.active.current.operatingRevenue, 0)
        equal(#resumed.active.periods, 0)
        equal(resumed.active.current.complete, false)
        resumed:delete()
    end)
end)

test("observer failure never swallows or duplicates native transactions", function()
    fixture(function(c)
        BankFinanceDataSource.classifyMoneyType = function() error("classifier failed") end
        local _, result = c.mission:addMoney(50, 7, MoneyType.CROP)
        equal(result, "native-money"); equal(c.farms[7].money, 10050); equal(c.counts(), 1)
        assert(c.runtime.lastError:find("classifier failed", 1, true))
        assert(#c.runtime:report().materialGaps > 0)
    end)
end)

test("teardown preserves another mod's later wrapper and drops bank ownership", function()
    fixture(function(c)
        local bankWrapper = c.mission.addMoney
        local thirdParty = function(target, ...) return bankWrapper(target, ...) end
        c.mission.addMoney = thirdParty
        c.runtime:delete()
        equal(c.mission.addMoney, thirdParty)
        equal(c.mission.saveSavegame, c.originals.save)
        equal(c.farms[7].changeLoan, c.originals.loan7)
        c.mission:addMoney(10, 7, MoneyType.CROP)
        equal(c.farms[7].money, 10010); equal(c.counts(), 1)
        equal(c.runtime.active, nil); equal(c.runtime.mission, nil)
    end)
end)

test("returned diagnostic metadata is detached from live observer tables", function()
    fixture(function(c)
        c.mission:addMoney(1, 7, MoneyType.CROP)
        local report = c.runtime:report()
        report.capabilities.addMoney = false
        report.lastTransaction.classification = "changed"
        equal(c.runtime.capabilities.addMoney, true)
        equal(c.runtime.lastTransaction.classification, "operating")
    end)
end)

test("native transaction failure is rethrown and wrapper state recovers", function()
    fixture(function(c)
        local ok = pcall(c.mission.addMoney, c.mission, "not a number", 7, MoneyType.CROP)
        equal(ok, false)
        equal(c.runtime.depth, 0)
        c.mission:addMoney(20, 7, MoneyType.CROP)
        equal(c.farms[7].money, 10020)
        equal(c.counts(), 2)
        assert(#c.runtime:report().materialGaps > 0)
    end)
end)

test("native save failure never writes an apparently successful sidecar", function()
    fixture(function(c)
        c.mission.failSave = true
        local ok, detail = c.mission:saveSavegame()
        equal(ok, false); equal(detail, "native-failure")
        equal(#c.writes, 0)
        equal(select(3, c.counts()), 1)
    end)
end)

test("day-length setting change invalidates earlier comparable history", function()
    fixture(function(c)
        c.mission.environment.currentMonotonicDay = 2
        c.mission.environment.currentPeriod = 2
        c.mission.environment.dayTime = 0
        c.runtime:sample()
        equal(#c.runtime.active.periods, 1)
        c.mission.environment.daysPerPeriod = 3
        c.runtime:sample()
        equal(#c.runtime.active.periods, 0)
        assert(#c.runtime:report().materialGaps > 0)
    end)
end)

test("late resume does not silently relax the exact calendar anchor", function()
    fixture(function(c)
        c.mission:addMoney(40, 7, MoneyType.CROP)
        c.mission:saveSavegame(); c.runtime:delete()
        c.mission.environment.dayTime = c.mission.environment.dayTime + 16
        local resumed = c.newRuntime(); resumed:start()
        equal(resumed.active.current.operatingRevenue, 0)
        equal(resumed.active.current.complete, false)
        assert(#resumed:report().materialGaps > 0)
        resumed:delete()
    end)
end)

test("native transaction observations drive a complete model and survive save reload", function()
    fixture(function(c)
        dofile("scripts/BankFinanceDataSource.lua")
        dofile("scripts/BankUnderwriting.lua")
        MoneyType.SOLD_PRODUCTS, MoneyType.PURCHASE_FUEL, MoneyType.LOAN_INTEREST = 1, 2, 4
        local function boundary()
            local e = c.mission.environment
            e.currentMonotonicDay = e.currentMonotonicDay + 1
            e.currentPeriod, e.dayTime = e.currentPeriod % 12 + 1, 0
            c.runtime:sample()
        end
        local function snapshot()
            return {farm = {id = 7}, cash = {status = "available", value = c.farms[7].money},
                debt = {status = "available", value = c.farms[7].loan}}
        end
        equal(BankUnderwriting.prepare(snapshot(), c.runtime:report()).assessment.score, nil)
        boundary() -- discard only the installation period from eligibility
        for month = 1, 12 do
            c.mission:addMoney(1000 + month, 7, MoneyType.SOLD_PRODUCTS)
            c.mission:addMoney(-300, 7, MoneyType.PURCHASE_FUEL)
            c.mission:addMoney(-25, 7, MoneyType.LOAN_INTEREST)
            if month == 3 then c.farms[7]:changeLoan(500) end
            if month == 4 then c.farms[7]:changeLoan(-500) end
            boundary()
        end
        local history = c.runtime:report()
        local model = BankUnderwriting.prepare(snapshot(), history, {mode = "standard"})
        equal(model.history.completePeriodCount, 12)
        equal(model.history.totals.operatingRevenue, 12078)
        equal(model.history.totals.operatingExpense, 3600)
        equal(model.history.totals.interestExpense, 300)
        equal(model.history.totals.financingInflow, 500)
        equal(model.history.totals.financingOutflow, 500)
        equal(model.forecast.status, "available")
        equal(#model.forecast.periods, 12)
        equal(model.forecast.annualCashBeforePrincipal, 8178)
        equal(model.assessment.status, "available")
        assert(type(model.assessment.score) == "number")
        c.mission:saveSavegame()
        c.store["savegame1/lizardBankHistory_7.xml"] = copied(c.store["tempsavegame/lizardBankHistory_7.xml"])
        c.mission.missionInfo.savegameDirectory = "savegame1"
        c.runtime:delete()
        local restored = c.newRuntime()
        restored:start()
        local again = BankUnderwriting.prepare(snapshot(), restored:report(), {mode = "standard"})
        equal(again.assessment.score, model.assessment.score)
        equal(again.forecast.annualCashBeforePrincipal, 8178)
        c.farms[7].money = c.farms[7].money + 99 -- unsupported mutation must withhold both
        local broken = BankUnderwriting.prepare(snapshot(), restored:report())
        equal(broken.assessment.score, nil)
        equal(broken.forecast.status, "insufficient_evidence")
        restored:delete()
    end)
end)

if not _G.test then print(tostring(count) .. " history runtime tests passed") end
