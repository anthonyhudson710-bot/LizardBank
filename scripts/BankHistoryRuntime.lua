-- Narrow capability-checked observers. Native calls run once with their exact
-- arguments/returns. Failures in bank observation never stop native transactions.
BankHistoryRuntime = {}
local mt = {__index = BankHistoryRuntime}
local N = BankHistory.isNumber
local function pack(...) return {n = select("#", ...), ...} end
local function diagnostic(method, ...) BankHistory.diagnostic(method, ...) end
local function label(path)
    return type(path) == "string" and path:gsub("\\", "/"):match("([^/]+)/?$") or nil
end
local function scalar(value)
    if N(value) or type(value) == "boolean" then return value end
    if type(value) == "string" then return value:sub(1, 256) end
    return nil
end
local function call(object, name, ...)
    if object and type(object[name]) == "function" then
        local ok, value = pcall(object[name], object, ...)
        if ok then return value end
        diagnostic("read", "history", name, false, nil, {errorType = type(value), error = scalar(value)})
    end
end
local function cash(farm, trace)
    local value = call(farm, "getBalance")
    local source = "farm:getBalance()"
    if not N(value) then value = farm and farm.money; source = "farm.money" end
    if trace then diagnostic("read", "history", source, N(value), value, trace) end
    return N(value) and value or nil
end
local function debt(farm, trace)
    local value = call(farm, "getLoan")
    local source = "farm:getLoan()"
    if not N(value) then value = farm and farm.loan; source = "farm.loan" end
    if trace then diagnostic("read", "history", source, N(value) and value >= 0, value, trace) end
    return N(value) and value >= 0 and value or nil
end
local function copied(t)
    if type(t) ~= "table" then return t end
    local result = {}
    for k, v in pairs(t) do result[k] = type(v) == "table" and copied(v) or v end
    return result
end
local function moneyIdentity(value)
    local description = {valueType = type(value)}
    if N(value) or type(value) == "string" then description.raw = type(value) == "string" and value:sub(1, 96) or value end
    local names, visited = {}, 0
    for name, entry in pairs(type(MoneyType) == "table" and MoneyType or {}) do
        visited = visited + 1
        if visited > 512 then break end
        if type(name) == "string" and value ~= nil and rawequal(value, entry) then names[#names + 1] = name:sub(1, 96) end
    end
    table.sort(names)
    description.nativeNames = table.concat(names, ", "):sub(1, 512)
    return description
end

function BankHistoryRuntime.new(mission)
    return setmetatable({mission = mission, ledgers = {}, hooks = {}, issues = {}, elapsed = 0,
        capabilities = {}, enabled = true, depth = 0}, mt)
end

function BankHistoryRuntime:issue(message)
    self.issues[message] = true
end

function BankHistoryRuntime:safe(method, ...)
    local ok, result = pcall(method, self, ...)
    if not ok then
        self:issue("History observer encountered an error; inspect lbSnapshot diagnostics.")
        self.lastError = tostring(result)
        BankHistory.markGap(self.active, "History observation failed.")
        diagnostic("emit", "history.observer.error", {transactionId = self.diagnosticTransactionId, errorType = type(result), error = scalar(result), farmId = self.farmId})
    end
    return ok and result or nil
end

function BankHistoryRuntime:stamp()
    local env = self.mission and self.mission.environment
    if type(env) ~= "table" then return nil end
    return {day = env.currentMonotonicDay, period = env.currentPeriod, dayTime = env.dayTime,
        daysPerPeriod = env.daysPerPeriod}
end

function BankHistoryRuntime:resolveFarm(id)
    id = id or call(self.mission, "getFarmId") or call(g_localPlayer, "getFarmId")
    if not N(id) or id <= 0 or id ~= math.floor(id) or g_farmManager == nil then return nil end
    return call(g_farmManager, "getFarmById", id), id
end

local function pathFor(mission, id)
    local dir = mission and mission.missionInfo and mission.missionInfo.savegameDirectory
    if type(dir) ~= "string" or dir == "" then return nil end
    return dir .. (dir:sub(-1) == "/" and "" or "/") .. "lizardBankHistory_" .. tostring(id) .. ".xml"
end

local transactionSequence = 0
local function traceStart(owner, method, kind, args, path)
    if not BankHistory.diagnosticsEnabled() then return nil end
    transactionSequence = transactionSequence + 1
    local trace = {transactionId = transactionSequence, parentTransactionId = owner and owner.diagnosticTransactionId,
        method = method, kind = kind, path = path, argumentCount = args.n,
        farmId = kind == "loan" and owner and owner.farmId or scalar(args[2]), requestedAmount = scalar(args[1])}
    if kind == "loan" and path == "nonactive_loan_target" then trace.farmId = nil; trace.farmIdentity = "Unverified nonactive target" end
    if kind == "save" then
        trace.farmId, trace.requestedAmount = owner and owner.farmId, nil
        trace.directoryBefore = label(owner and owner.mission and owner.mission.missionInfo and owner.mission.missionInfo.savegameDirectory)
    end
    diagnostic("emit", kind == "save" and "history.save.begin" or "history.transaction.begin", copied(trace))
    return trace
end

local function invokeNative(record, target, args, trace)
    if trace then diagnostic("emit", "history.native.begin", copied(trace)) end
    local result = pack(pcall(record.original, target, unpack(args, 1, args.n)))
    if trace then
        local proof = copied(trace)
        proof.nativeCallCount, proof.succeeded, proof.returnCount = 1, result[1], result.n - 1
        local types = {}
        for i = 2, math.min(result.n, 17) do types[#types + 1] = type(result[i]) end
        proof.returnTypes = table.concat(types, ",")
        proof.returnTypesTruncated = result.n > 17
        if not result[1] then proof.error, proof.errorType = scalar(result[2]), type(result[2]) end
        diagnostic("emit", result[1] and "history.native.return" or "history.native.error", proof)
        diagnostic("check", "HISTORY_TRANSACTION_NATIVE_ONCE", "PASS", {transactionId = trace.transactionId,
            method = record.method, nativeCallCount = 1, succeeded = result[1], basis = "One original invocation in this wrapper call; nested calls have separate IDs"})
    end
    return result
end

local function directNative(record, target, args, trace)
    if trace == nil then return record.original(target, unpack(args, 1, args.n)) end
    local result = invokeNative(record, target, args, trace)
    local proof = copied(trace)
    proof.succeeded, proof.observed = result[1], false
    diagnostic("emit", record.kind == "save" and "history.save.end" or "history.transaction.end", proof)
    if not result[1] then error(result[2], 0) end
    return unpack(result, 2, result.n)
end

function BankHistoryRuntime:attach(object, method, kind)
    if object == nil or type(object[method]) ~= "function" then
        diagnostic("check", "HISTORY_HOOK_ATTACH", "UNAVAILABLE", {method = method, kind = kind})
        return false
    end
    for _, existing in ipairs(self.hooks) do if existing.owner == self and existing.object == object and existing.method == method then return true end end
    local record = {object = object, method = method, original = object[method], previous = rawget(object, method), owner = self, kind = kind}
    record.wrapper = function(target, ...)
        local owner = record.owner
        local args = pack(...)
        if owner == nil or not owner.enabled then return directNative(record, target, args, traceStart(owner, method, kind, args, "inactive_observer")) end
        if kind == "save" then
            local trace = traceStart(owner, method, kind, args, "native_save_callback")
            local result
            if trace then
                trace.directoryBefore = label(owner.mission and owner.mission.missionInfo and owner.mission.missionInfo.savegameDirectory)
                local called = invokeNative(record, target, args, trace)
                if not called[1] then
                    diagnostic("emit", "history.save.end", {transactionId = trace.transactionId, stage = "native_callback_error", succeeded = false})
                    error(called[2], 0)
                end
                result = {n = called.n - 1}
                for i = 2, called.n do result[i - 1] = called[i] end
            else result = pack(record.original(target, ...)) end
            local previousSaveTrace = owner.diagnosticSaveId
            if trace then owner.diagnosticSaveId = trace.transactionId end
            if result[1] ~= false then owner:safe(owner.save) end
            owner.diagnosticSaveId = previousSaveTrace
            if trace then diagnostic("emit", "history.save.end", {transactionId = trace.transactionId, stage = "native_callback_returned",
                directoryBefore = trace.directoryBefore, directoryAfter = label(owner.mission and owner.mission.missionInfo and owner.mission.missionInfo.savegameDirectory),
                nativeReturnedFalse = result[1] == false, nativeReturnType = type(result[1]),
                basis = "Callback return and sidecar stage observed; whole native save completion is not proven"}) end
            return unpack(result, 1, result.n)
        end
        if kind == "loan" and target ~= owner.farm then return directNative(record, target, args, traceStart(owner, method, kind, args, "nonactive_loan_target")) end
        if owner.depth > 0 then
            if owner.pending then owner.pending.nested = true end
            return directNative(record, target, args, traceStart(owner, method, kind, args, "nested_accounted_by_parent"))
        end
        local trace = traceStart(owner, method, kind, args, "observer")
        local previousTrace = owner.diagnosticTransactionId
        if trace then owner.diagnosticTransactionId = trace.transactionId end
        local token = owner:safe(owner.beforeTransaction, kind == "loan" and owner.farmId or args[2])
        if token and trace then token.transactionId = trace.transactionId end
        owner.depth, owner.pending = 1, token
        local result = invokeNative(record, target, args, trace)
        owner.depth, owner.pending = 0, nil
        owner:safe(owner.afterTransaction, token, kind, args[3], result[1], args[1])
        owner.diagnosticTransactionId = previousTrace
        if trace then diagnostic("emit", "history.transaction.end", {transactionId = trace.transactionId, parentTransactionId = trace.parentTransactionId,
            kind = kind, farmId = trace.farmId, succeeded = result[1], observed = token ~= nil,
            reason = token == nil and "Farm did not match active readable ledger, or observer failed" or nil,
            cashBefore = token and token.before, cashAfter = token and token.observedAfterCash,
            debtBefore = token and token.debtBefore, debtAfter = token and token.observedAfterDebt,
            nested = token and token.nested == true}) end
        if not result[1] then error(result[2], 0) end
        return unpack(result, 2, result.n)
    end
    object[method] = record.wrapper
    self.hooks[#self.hooks + 1] = record
    diagnostic("emit", "history.hook.attach", {method = method, kind = kind, replacedOwnProperty = record.previous ~= nil})
    diagnostic("check", "HISTORY_HOOK_ATTACH", "PASS", {method = method, kind = kind, wrapperInstalled = object[method] == record.wrapper})
    return true
end

function BankHistoryRuntime:start()
    self.capabilities.addMoney = self:attach(self.mission, "addMoney", "money")
    self.capabilities.saveSavegame = self:attach(self.mission, "saveSavegame", "save")
    self.capabilities.xml = BankHistoryStore.available()
    if not self.capabilities.addMoney then self:issue("Native money observer unavailable.") end
    if not self.capabilities.saveSavegame then self:issue("Native save callback unavailable; history cannot persist.") end
    if not self.capabilities.xml then self:issue("Native history XML functions unavailable.") end
    self:safe(self.sample)
end

function BankHistoryRuntime:releaseFarmHooks(farm)
    if farm == nil then return end
    local retained = {}
    for _, hook in ipairs(self.hooks) do
        if hook.kind == "loan" and hook.object == farm then
            local owned = hook.object[hook.method] == hook.wrapper
            hook.owner = nil
            if owned then hook.object[hook.method] = hook.previous end
            diagnostic("check", "HISTORY_HOOK_RESTORE", owned and "PASS" or "WARN", {method = hook.method,
                ownedWrapper = owned, restored = owned, otherWrapperPreserved = not owned, reason = "farm_switch"})
            hook.object = nil
        else retained[#retained + 1] = hook end
    end
    self.hooks = retained
end

function BankHistoryRuntime:sample()
    if not self.enabled then return end
    local farm, id = self:resolveFarm()
    local stamp, balance = self:stamp(), cash(farm)
    if farm == nil or balance == nil or not BankHistory.isCalendar(stamp) then
        if BankHistory.diagnosticsEnabled() and self.diagnosticReadyState ~= false then
            self.diagnosticReadyState = false
            diagnostic("emit", "history.readiness", {ready = false, requestedFarmId = id, farmAvailable = farm ~= nil,
                cashAvailable = balance ~= nil, calendarAvailable = BankHistory.isCalendar(stamp) == true})
        end
        BankHistory.markGap(self.active, "Current farm cash or calendar became unavailable.")
        self:releaseFarmHooks(self.farm)
        self.active, self.farmId, self.farm = nil, nil, nil
        return
    end
    if self.farmId ~= id or self.farm ~= farm then
        diagnostic("emit", "history.farm.change", {previousFarmId = self.farmId, farmId = id, sameIdNewObject = self.farmId == id and self.farm ~= farm})
        if self.active then BankHistory.markGap(self.active, "Active farm changed; observation was interrupted.") end
        self:releaseFarmHooks(self.farm)
        local ledger = self.ledgers[id]
        if ledger == nil then
            local path = pathFor(self.mission, id)
            local saved, message
            if path then saved, message = BankHistoryStore.read(path) end
            if saved and (saved.debt == nil or debt(farm) == nil or math.abs(saved.debt - debt(farm)) > 0.01) then
                diagnostic("check", "HISTORY_RESUME_DEBT_ANCHOR", "WARN", {farmId = id, savedDebt = saved.debt, basis = "Existing native debt comparison rejected the saved ledger"})
                saved = nil; message = "Saved debt anchor does not match."
            end
            if saved then ledger = BankHistory.resume(saved, id, stamp, balance)
            else
                ledger = BankHistory.new(id, stamp, balance)
                diagnostic("emit", "history.resume", {farmId = id, resumed = false, basis = "New partial ledger; no accepted saved anchor",
                    loadNoteAvailable = message ~= nil, directory = label(self.mission and self.mission.missionInfo and self.mission.missionInfo.savegameDirectory)})
                diagnostic("check", "HISTORY_RESUME_ANCHOR", "NOT_EXERCISED", {farmId = id, reason = "No saved ledger reached exact anchor comparison"})
            end
            if ledger == nil then return end
            ledger.loadNote = message
            self.ledgers[id] = ledger
        end
        self.active, self.farmId, self.farm = ledger, id, farm
        self.capabilities.changeLoan = self:attach(farm, "changeLoan", "loan")
    end
    if self.active.last.daysPerPeriod ~= nil and stamp and stamp.daysPerPeriod ~= self.active.last.daysPerPeriod then
        BankHistory.markGap(self.active, "Days per period changed; seasonal amounts are no longer comparable.")
        self.active.periods = {}
    end
    BankHistory.observe(self.active, stamp, balance)
    local currentDebt = debt(farm)
    if self.active.debt ~= nil and (currentDebt == nil or math.abs(currentDebt - self.active.debt) > 0.01) then
        BankHistory.markGap(self.active, "Native debt changed outside matched loan observation; financing continuity is unknown.")
    end
    if currentDebt == nil then BankHistory.markGap(self.active, "Current native debt is unavailable.") end
    self.active.debt = currentDebt
    if BankHistory.diagnosticsEnabled() then
        local state = {farmId = id, cash = balance, debt = currentDebt, day = stamp.day, period = stamp.period,
            daysPerPeriod = stamp.daysPerPeriod, cycle = self.active.cycle}
        local changed = self.diagnosticReadyState ~= true or self.diagnosticSample == nil
        for key, value in pairs(state) do if not self.diagnosticSample or self.diagnosticSample[key] ~= value then changed = true end end
        if self.diagnosticSample and self.diagnosticSample.debt ~= state.debt then changed = true end
        if changed then
            if self.diagnosticReadyState ~= true then diagnostic("emit", "history.readiness", {ready = true, farmId = id}) end
            self.diagnosticReadyState = true
            self.diagnosticSample = copied(state)
            state.dayTime = stamp.dayTime
            diagnostic("emit", "history.sample.changed", state)
        end
    end
end

function BankHistoryRuntime:beforeTransaction(farmId)
    self:sample()
    if farmId ~= self.farmId or self.active == nil then return nil end
    local trace = BankHistory.diagnosticsEnabled() and {transactionId = self.diagnosticTransactionId, farmId = self.farmId, stage = "before_native_call"} or nil
    return {ledger = self.active, farm = self.farm, before = cash(self.farm, trace), debtBefore = debt(self.farm, trace), stamp = self:stamp()}
end

function BankHistoryRuntime:afterTransaction(token, kind, moneyType, succeeded, requestedAmount)
    if token == nil then return end
    local trace = BankHistory.diagnosticsEnabled() and {transactionId = token.transactionId, farmId = token.ledger.farmId, stage = "after_native_call"} or nil
    local after, afterDebt = cash(token.farm, trace), debt(token.farm, trace)
    token.observedAfterCash, token.observedAfterDebt = after, afterDebt
    local category, classification, source = "unknown", "unclassified", "unidentified money type"
    if kind == "loan" then
        if N(after) and N(token.before) and N(afterDebt) and N(token.debtBefore)
            and math.abs((after - token.before) - (afterDebt - token.debtBefore)) < 0.01 then
            category, classification, source = "nativeLoan", "financing", "Matched cash and native loan deltas"
        end
    elseif BankFinanceDataSource and BankFinanceDataSource.classifyMoneyType then
        category, classification, source = BankFinanceDataSource.classifyMoneyType(moneyType, MoneyType)
        if token.nested then classification = "unclassified" end
    end
    if N(afterDebt) and N(token.debtBefore) and math.abs(afterDebt - token.debtBefore) > 0.01 and classification ~= "financing" then
        BankHistory.markGap(token.ledger, "Native debt changed without a matched financing observation.")
    end
    if afterDebt == nil then BankHistory.markGap(token.ledger, "Native debt became unavailable during a transaction.") end
    if not succeeded then BankHistory.markGap(token.ledger, "Native transaction raised an error.") end
    local identity = moneyIdentity(moneyType)
    if category == nil and identity.nativeNames ~= "" then category = "unclassified:" .. identity.nativeNames:sub(1, 80) end
    BankHistory.record(token.ledger, token.stamp, token.before, after, category, classification)
    token.ledger.debt = afterDebt
    self.lastTransaction = {category = category, classification = classification, source = source,
        kind = kind, succeeded = succeeded, nested = token.nested == true, moneyType = identity,
        requestedAmount = N(requestedAmount) and requestedAmount or nil, beforeCash = token.before,
        afterCash = after, beforeDebt = token.debtBefore, afterDebt = afterDebt, capturedAt = copied(token.stamp)}
    if BankHistory.diagnosticsEnabled() then
        local proof = copied(self.lastTransaction)
        proof.transactionId, proof.farmId = token.transactionId, token.ledger.farmId
        proof.cashDelta = N(after) and N(token.before) and after - token.before or nil
        proof.debtDelta = N(afterDebt) and N(token.debtBefore) and afterDebt - token.debtBefore or nil
        diagnostic("emit", "history.transaction.classification", proof)
        if kind == "loan" then diagnostic("check", "HISTORY_FINANCING_DELTA_MATCH",
            classification == "financing" and "PASS" or (proof.cashDelta == nil or proof.debtDelta == nil) and "UNAVAILABLE" or "WARN", proof) end
    end
end

function BankHistoryRuntime:update(dt)
    if not self.enabled then return end
    self.elapsed = self.elapsed + (N(dt) and dt or 0)
    if self.elapsed >= 1000 then self.elapsed = 0; self:safe(self.sample) end
end

function BankHistoryRuntime:save()
    if not self.enabled then return end
    self:sample()
    -- Resolve the directory at this callback, never cache savegameN: FS25 may
    -- currently be writing tempsavegame before promoting it to the final slot.
    for id, ledger in pairs(self.ledgers) do
        local path = pathFor(self.mission, id)
        diagnostic("emit", "history.save.sidecar.begin", {transactionId = self.diagnosticSaveId, farmId = id, directory = label(self.mission and self.mission.missionInfo and self.mission.missionInfo.savegameDirectory),
            filename = label(path), stage = "after_native_save_callback", periods = #ledger.periods, cash = ledger.balance, debt = ledger.debt})
        local ok, message = false, "Save directory unavailable."
        if path then ok, message = BankHistoryStore.write(path, ledger) end
        self.lastSave = {status = ok and "written" or "failed", detail = message,
            basis = "Sidecar write during native save; full save completion not confirmed"}
        if not ok then self:issue("History sidecar could not be written.") end
        diagnostic("emit", "history.save.end", {transactionId = self.diagnosticSaveId, farmId = id, stage = "sidecar_write_returned", written = ok,
            directory = label(self.mission and self.mission.missionInfo and self.mission.missionInfo.savegameDirectory), filename = label(path),
            nativeSaveCompletionProven = false})
    end
end

function BankHistoryRuntime:report()
    self:safe(self.sample)
    local issues = {}
    for message in pairs(self.issues) do issues[#issues + 1] = message end
    if self.active == nil then issues[#issues + 1] = "Waiting for readable farm cash and calendar." end
    table.sort(issues)
    local report = BankHistory.report(self.active, issues)
    report.capabilities, report.lastSave, report.lastTransaction = copied(self.capabilities), copied(self.lastSave), copied(self.lastTransaction)
    report.lastError = self.lastError
    report.loadNote = self.active and self.active.loadNote
    report.persistence = self.capabilities.saveSavegame and self.capabilities.xml and "save_callback_candidate" or "unavailable"
    return report
end

function BankHistoryRuntime:cycleMode()
    if not self.active then return end
    local modes = {standard = "strict", strict = "lenient", lenient = "standard"}
    local previous = self.active.mode
    self.active.mode = modes[self.active.mode] or "standard"
    diagnostic("emit", "history.mode.change", {farmId = self.farmId, previousMode = previous, mode = self.active.mode})
end

function BankHistoryRuntime:delete()
    self.enabled = false
    for _, hook in ipairs(self.hooks) do
        hook.owner = nil
        local owned = hook.object and hook.object[hook.method] == hook.wrapper or false
        if owned then hook.object[hook.method] = hook.previous end
        diagnostic("check", "HISTORY_HOOK_RESTORE", owned and "PASS" or "WARN", {method = hook.method,
            ownedWrapper = owned, restored = owned, otherWrapperPreserved = not owned, reason = "mission_delete"})
        hook.object = nil
    end
    self.hooks, self.ledgers, self.active, self.farm, self.mission = {}, {}, nil, nil, nil
end
