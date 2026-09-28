-- Narrow capability-checked observers. Native calls run once with their exact
-- arguments/returns. Failures in bank observation never stop native transactions.
BankHistoryRuntime = {}
local mt = {__index = BankHistoryRuntime}
local N = BankHistory.isNumber
local function pack(...) return {n = select("#", ...), ...} end
local function call(object, name, ...)
    if object and type(object[name]) == "function" then
        local ok, value = pcall(object[name], object, ...)
        if ok then return value end
    end
end
local function cash(farm)
    local value = call(farm, "getBalance")
    if not N(value) then value = farm and farm.money end
    return N(value) and value or nil
end
local function debt(farm)
    local value = call(farm, "getLoan")
    if not N(value) then value = farm and farm.loan end
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

function BankHistoryRuntime:attach(object, method, kind)
    if object == nil or type(object[method]) ~= "function" then return false end
    for _, existing in ipairs(self.hooks) do if existing.owner == self and existing.object == object and existing.method == method then return true end end
    local record = {object = object, method = method, original = object[method], previous = rawget(object, method), owner = self, kind = kind}
    record.wrapper = function(target, ...)
        local owner = record.owner
        if owner == nil or not owner.enabled then return record.original(target, ...) end
        if kind == "save" then
            local result = pack(record.original(target, ...))
            if result[1] ~= false then owner:safe(owner.save) end
            return unpack(result, 1, result.n)
        end
        if kind == "loan" and target ~= owner.farm then return record.original(target, ...) end
        if owner.depth > 0 then
            if owner.pending then owner.pending.nested = true end
            return record.original(target, ...)
        end
        local args = pack(...)
        local token = owner:safe(owner.beforeTransaction, kind == "loan" and owner.farmId or args[2])
        owner.depth, owner.pending = 1, token
        local result = pack(pcall(record.original, target, ...))
        owner.depth, owner.pending = 0, nil
        owner:safe(owner.afterTransaction, token, kind, args[3], result[1], args[1])
        if not result[1] then error(result[2], 0) end
        return unpack(result, 2, result.n)
    end
    object[method] = record.wrapper
    self.hooks[#self.hooks + 1] = record
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
            hook.owner = nil
            if hook.object[hook.method] == hook.wrapper then hook.object[hook.method] = hook.previous end
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
        BankHistory.markGap(self.active, "Current farm cash or calendar became unavailable.")
        self:releaseFarmHooks(self.farm)
        self.active, self.farmId, self.farm = nil, nil, nil
        return
    end
    if self.farmId ~= id or self.farm ~= farm then
        if self.active then BankHistory.markGap(self.active, "Active farm changed; observation was interrupted.") end
        self:releaseFarmHooks(self.farm)
        local ledger = self.ledgers[id]
        if ledger == nil then
            local path = pathFor(self.mission, id)
            local saved, message
            if path then saved, message = BankHistoryStore.read(path) end
            if saved and (saved.debt == nil or debt(farm) == nil or math.abs(saved.debt - debt(farm)) > 0.01) then saved = nil; message = "Saved debt anchor does not match." end
            if saved then ledger = BankHistory.resume(saved, id, stamp, balance)
            else ledger = BankHistory.new(id, stamp, balance) end
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
end

function BankHistoryRuntime:beforeTransaction(farmId)
    self:sample()
    if farmId ~= self.farmId or self.active == nil then return nil end
    return {ledger = self.active, farm = self.farm, before = cash(self.farm), debtBefore = debt(self.farm), stamp = self:stamp()}
end

function BankHistoryRuntime:afterTransaction(token, kind, moneyType, succeeded, requestedAmount)
    if token == nil then return end
    local after, afterDebt = cash(token.farm), debt(token.farm)
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
        local ok, message = false, "Save directory unavailable."
        if path then ok, message = BankHistoryStore.write(path, ledger) end
        self.lastSave = {status = ok and "written" or "failed", detail = message,
            basis = "Sidecar write during native save; full save completion not confirmed"}
        if not ok then self:issue("History sidecar could not be written.") end
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
    self.active.mode = modes[self.active.mode] or "standard"
end

function BankHistoryRuntime:delete()
    self.enabled = false
    for _, hook in ipairs(self.hooks) do
        hook.owner = nil
        if hook.object and hook.object[hook.method] == hook.wrapper then hook.object[hook.method] = hook.previous end
        hook.object = nil
    end
    self.hooks, self.ledgers, self.active, self.farm, self.mission = {}, {}, nil, nil, nil
end
