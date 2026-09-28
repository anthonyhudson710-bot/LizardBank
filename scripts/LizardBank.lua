-- Mission lifecycle, native input integration and the shared bank entry point.
-- Asset scans occur on demand; lightweight money/calendar observation is separate.
LizardBank = {
    VERSION = "0.0.7",
    GUI_NAME = "LizardBank",
    modName = g_currentModName or "FS25_LizardBank",
    modDirectory = g_currentModDirectory or "",
    enabled = false,
    initialized = false
}

local HOOK_KEY = "__lizardBankInputHook"
local LOAD_HOOK_KEY = "__lizardBankLoadHook"
local profileGui
local function debugEvent(name, data)
    if BankDiagnostics ~= nil and BankDiagnostics.isEnabled() then BankDiagnostics.emit(name, data) end
end
local function debugCheck(name, outcome, evidence)
    if BankDiagnostics ~= nil and BankDiagnostics.isEnabled() then BankDiagnostics.check(name, outcome, evidence) end
end

local function log(message)
    print("[LizardBank] " .. tostring(message))
end

local function scalar(value)
    if type(value) == "string" then
        return string.format("%q", value:gsub("[\r\n]", " "))
    end
    return tostring(value)
end

-- Only serialize our data transfer object, never live engine object graphs.
local function logTable(value, path, depth)
    if type(value) ~= "table" then
        log(path .. "=" .. scalar(value))
        return
    end
    if depth > 8 then
        log(path .. "=<depth limit>")
        return
    end
    local keys = {}
    for key in pairs(value) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do
        logTable(value[key], path .. "." .. tostring(key), depth + 1)
    end
end

function LizardBank:isSinglePlayer()
    local mission = g_currentMission
    if mission == nil or g_dedicatedServer ~= nil then
        return false
    end
    if mission.missionDynamicInfo == nil then
        return false -- wait for the mission's mode to be known
    end
    return mission.missionDynamicInfo.isMultiplayer == false
end

function LizardBank:loadMap()
    self:deleteMap()
    self:beginValidationMission("loadMap")
    self.waitingForMission = true
    self.initFailed = false
    self:installLoadHook()
    debugEvent("lifecycle.loadMap", {loadHook = self.loadHook ~= nil})
end

function LizardBank:beginValidationMission(source)
    if self.validationMissionActive or BankDiagnostics == nil or not BankDiagnostics.isEnabled() then return end
    BankDiagnostics.beginMission({modVersion = self.VERSION, gameVersion = tostring(g_gameVersionDisplay or g_gameVersion or "unavailable"),
        source = source, singlePlayer = self:isSinglePlayer(), inputHook = self.inputHook ~= nil,
        modeKnown = g_currentMission ~= nil and g_currentMission.missionDynamicInfo ~= nil,
        loadHook = self.loadHook ~= nil, guiReady = self.initialized})
    self.validationMissionActive = true
end

-- Read the sidecar before the first clock update when this native callback is
-- present. A first-update fallback never relaxes saved observation anchors.
function LizardBank:installLoadHook()
    if Mission00 == nil or type(Mission00.loadMission00Finished) ~= "function" then return end
    local record = Mission00[LOAD_HOOK_KEY]
    if record == nil then
        record = {original = Mission00.loadMission00Finished}
        record.wrapper = function(mission, ...)
            local function packed(...) return {n = select("#", ...), ...} end
            local result = packed(record.original(mission, ...))
            local owner = record.owner
            if owner ~= nil and mission == g_currentMission and owner:isSinglePlayer() then
                owner.loadCompleteSeen = true
                debugEvent("lifecycle.loadComplete", {nativeReturnCount = result.n, historyAlreadyStarted = owner.historyRuntime ~= nil})
                owner:startHistory("load_complete_candidate")
            end
            return unpack(result, 1, result.n)
        end
        Mission00[LOAD_HOOK_KEY] = record
        Mission00.loadMission00Finished = record.wrapper
    end
    record.owner, self.loadHook = self, record
    debugEvent("lifecycle.loadHook.install", {available = true})
end

function LizardBank:removeLoadHook()
    local record = self.loadHook
    if record ~= nil and record.owner == self then
        debugEvent("lifecycle.loadHook.remove", {ownsTopWrapper = Mission00 ~= nil and Mission00.loadMission00Finished == record.wrapper})
        record.owner = nil
        if Mission00 ~= nil and Mission00.loadMission00Finished == record.wrapper then
            Mission00.loadMission00Finished = record.original
            if Mission00[LOAD_HOOK_KEY] == record then Mission00[LOAD_HOOK_KEY] = nil end
        end
    end
    self.loadHook, self.loadCompleteSeen = nil, nil
end

function LizardBank:startHistory(source)
    if self.historyRuntime ~= nil or type(BankHistoryRuntime) ~= "table" or not self:isSinglePlayer() then return end
    local ok, result = pcall(BankHistoryRuntime.new, g_currentMission)
    if ok then
        self.historyRuntime = result
        result.capabilities.startTiming = source
        result:safe(result.start)
        debugEvent("lifecycle.history.start", {source = source, capabilities = result.capabilities})
    else log("History initialization failed: " .. tostring(result)) end
end

function LizardBank:startMission()
    self.waitingForMission = false
    self.enabled = self:isSinglePlayer()
    self.initialized = false
    debugEvent("lifecycle.startMission", {enabled = self.enabled, singlePlayer = self:isSinglePlayer(), dedicated = g_dedicatedServer ~= nil})
    if not self.enabled then
        log("Inactive: this preview supports single-player missions only.")
        return
    end
    self:installInputHook()
    if addConsoleCommand ~= nil then
        addConsoleCommand("lbSnapshot", "Write a fresh Lizard Bank snapshot to log.txt", "consoleSnapshot", self)
        addConsoleCommand("lbOpen", "Open the Lizard Bank window", "consoleOpen", self)
        addConsoleCommand("lbDebug", "Lizard Bank validation: on, trace, off, summary", "consoleDebug", self)
        addConsoleCommand("lbValidate", "Capture and validate a labeled bank checkpoint", "consoleValidate", self)
        addConsoleCommand("lbMark", "Label and capture a validation checkpoint", "consoleMark", self)
        addConsoleCommand("lbExpect", "Compare a bank metric with a manually checked native value", "consoleExpect", self)
        self.commandsRegistered = true
    end
end

-- Extend the player's normal registration, which is rebuilt on context/input
-- changes. Do not repeatedly register actions from update(). The small record
-- lets us detach without removing a different mod's subsequently added hook.
function LizardBank:installInputHook()
    if PlayerInputComponent == nil or type(PlayerInputComponent.registerGlobalPlayerActionEvents) ~= "function" then
        log("Player input hook unavailable; lbOpen remains available for diagnosis.")
        return
    end
    local record = PlayerInputComponent[HOOK_KEY]
    if record == nil then
        record = {original = PlayerInputComponent.registerGlobalPlayerActionEvents}
        record.wrapper = function(component, ...)
            record.original(component, ...)
            local owner = record.owner
            if owner ~= nil and owner.enabled and component.player ~= nil and component.player.isOwner then
                owner:registerInputAction()
            end
        end
        PlayerInputComponent[HOOK_KEY] = record
        PlayerInputComponent.registerGlobalPlayerActionEvents = record.wrapper
    end
    record.owner = self
    self.inputHook = record
    debugEvent("input.hook.install", {available = true})
end

function LizardBank:removeInputHook()
    local record = self.inputHook
    if record ~= nil and record.owner == self then
        debugEvent("input.hook.remove", {ownsTopWrapper = PlayerInputComponent ~= nil and PlayerInputComponent.registerGlobalPlayerActionEvents == record.wrapper})
        record.owner = nil
        if PlayerInputComponent ~= nil and PlayerInputComponent.registerGlobalPlayerActionEvents == record.wrapper then
            PlayerInputComponent.registerGlobalPlayerActionEvents = record.original
            if PlayerInputComponent[HOOK_KEY] == record then
                PlayerInputComponent[HOOK_KEY] = nil
            end
        end
    end
    self.inputHook = nil
end

function LizardBank:registerInputAction()
    if not self.enabled or g_inputBinding == nil or InputAction == nil or InputAction.LIZARDBANK_OPEN == nil then
        debugEvent("input.registration.unavailable", {enabled = self.enabled, bindingAvailable = g_inputBinding ~= nil})
        return
    end
    if self.actionEventId ~= nil then
        g_inputBinding:removeActionEvent(self.actionEventId)
    end
    g_inputBinding:removeActionEventsByTarget(self)
    local success, eventId = g_inputBinding:registerActionEvent(
        InputAction.LIZARDBANK_OPEN, self, self.onOpenAction,
        false, true, false, true, nil, true
    )
    if success then
        self.actionEventId = eventId
        g_inputBinding:setActionEventTextVisibility(eventId, true)
        if g_i18n ~= nil then
            g_inputBinding:setActionEventText(eventId, g_i18n:getText("input_LIZARDBANK_OPEN", self.modName))
        end
    else
        self.actionEventId = nil
    end
    debugCheck("INPUT_ACTION_REGISTRATION", success and "PASS" or "FAIL", {actionEventId = eventId, inputContext = PlayerInputComponent and PlayerInputComponent.INPUT_CONTEXT_NAME})
end

function LizardBank:update(dt)
    if self.waitingForMission then
        if g_currentMission == nil or g_currentMission.missionDynamicInfo == nil then
            return
        end
        self:startMission()
    end
    if self.enabled and self.historyRuntime == nil and (self.loadHook == nil or self.loadCompleteSeen)
        and g_currentMission ~= nil and g_currentMission.missionInfo ~= nil then
        self:startHistory("first_update_fallback")
    end
    if self.historyRuntime ~= nil then self.historyRuntime:update(dt) end
    if BankDiagnostics ~= nil and BankDiagnostics.isEnabled() then
        local reason = BankDiagnostics.tick(dt, self.enabled and self.initialized)
        if reason ~= nil then
            local ok, err = pcall(self.captureSnapshot, self, "auto:" .. reason)
            if not ok then debugEvent("capture.auto.error", {error = tostring(err)}) end
        end
    end
    if not self.enabled or self.initialized or self.initFailed then
        return
    end
    if g_currentMission == nil or g_currentMission.missionInfo == nil or g_gui == nil or g_inputBinding == nil then
        return
    end
    local ok, err = pcall(self.initialize, self)
    if not ok then
        self.initFailed = true
        self:releaseScreen()
        log("Initialization failed: " .. tostring(err) .. ". Use lbSnapshot for diagnostics.")
        debugCheck("GUI_INITIALIZATION", "FAIL", {error = tostring(err)})
    end
end

function LizardBank:initialize()
    if g_gui.guis[self.GUI_NAME] ~= nil then
        error("A GUI named " .. self.GUI_NAME .. " is already registered")
    end
    if profileGui ~= g_gui then
        local result = g_gui:loadProfiles(self.modDirectory .. "gui/guiProfiles.xml")
        if result == false then error("Could not load GUI profiles") end
        profileGui = g_gui
    end
    self.screen = BankScreen.new(self)
    self.guiManager = g_gui
    local previousFocusGui = FocusManager.currentGui
    local loaded, root = pcall(g_gui.loadGui, g_gui, self.modDirectory .. "gui/BankScreen.xml", self.GUI_NAME, self.screen)
    FocusManager:setGui(previousFocusGui or "")
    if not loaded then error(root) end
    self.guiRoot = root
    if self.guiRoot == nil then
        -- Gui:loadGui deletes the controller on XML load failure.
        self.screen = nil
        error("Could not load the bank window")
    end
    self.initialized = true
    debugCheck("GUI_INITIALIZATION", g_gui.guis[self.GUI_NAME] == self.guiRoot and FocusManager.currentGui == (previousFocusGui or "") and "PASS" or "FAIL", {registered = g_gui.guis[self.GUI_NAME] == self.guiRoot, focusRestored = FocusManager.currentGui == (previousFocusGui or "")})
    -- Covers late initialization after the player's first registration. Later
    -- registrations use the context already selected by the game itself.
    if PlayerInputComponent ~= nil and PlayerInputComponent.INPUT_CONTEXT_NAME ~= nil then
        g_inputBinding:beginActionEventsModification(PlayerInputComponent.INPUT_CONTEXT_NAME)
        self:registerInputAction()
        g_inputBinding:endActionEventsModification()
    end
    log("Version " .. self.VERSION .. " ready. Open Lizard Bank in Controls; lbSnapshot writes diagnostics.")
    if BankValidationProbes ~= nil and BankDiagnostics ~= nil and BankDiagnostics.isEnabled() then BankValidationProbes.run() end
end

function LizardBank:onOpenAction(_, inputValue)
    if inputValue == nil or inputValue > 0 then
        self:openReport()
    end
end

-- Public entry point: future bank triggers call this same method.
function LizardBank:openReport()
    if not self.enabled or not self:isSinglePlayer() then
        debugEvent("gui.open.denied", {reason = "single_player_required"})
        return false, "Single-player mission required."
    end
    if not self.initialized or self.screen == nil then
        debugEvent("gui.open.denied", {reason = "not_ready"})
        return false, "Bank window is not ready; check log.txt."
    end
    if g_gui:getIsGuiVisible() or g_gui:getIsDialogVisible() then
        debugEvent("gui.open.denied", {reason = "other_menu_open"})
        return false, "Close the current menu before opening the bank."
    end
    g_gui:showGui(self.GUI_NAME)
    debugEvent("gui.open.requested", {guiName = self.GUI_NAME})
    return true
end

function LizardBank:captureSnapshot(reason)
    local diagnostics = BankDiagnostics ~= nil and BankDiagnostics.isEnabled()
    if diagnostics then
        self:beginValidationMission("first_capture")
        BankDiagnostics.beginCapture(reason or "open_or_refresh")
    end
    local ok, result = pcall(self.collectSnapshot, self)
    if diagnostics then
        if ok then
            local audited, err = pcall(BankValidation.evaluate, result, self.validationPrevious, BankDiagnostics.check)
            debugCheck("VALIDATION_ENGINE", audited and "PASS" or "FAIL", {error = not audited and tostring(err) or nil})
            BankDiagnostics.dump("snapshot", result)
            self.validationPrevious = result
        else debugCheck("SNAPSHOT_CAPTURE", "FAIL", {error = tostring(result)}) end
        BankDiagnostics.endCapture({ok = ok, farmId = ok and result.farm and result.farm.id or nil})
    end
    if not ok then self.lastSnapshot, self.validationPrevious = nil, nil; error(result, 0) end
    return result
end

function LizardBank:collectSnapshot()
    if self.enabled and self.historyRuntime == nil then self:startHistory("first_report_fallback") end
    local snapshot = BankDataSource.capture()
    snapshot.modVersion = self.VERSION
    if self.historyRuntime ~= nil then snapshot.history = self.historyRuntime:report()
    else snapshot.history = {periods = {}, materialGaps = {"History tracking unavailable."}} end
    if type(BankUnderwriting) == "table" and type(BankUnderwriting.prepare) == "function" then
        local ok, result = pcall(BankUnderwriting.prepare, snapshot, snapshot.history, {mode = snapshot.history.mode or "standard"})
        if ok and type(result) == "table" then
            snapshot.underwriting = result
            debugCheck("UNDERWRITING_PREPARE", "PASS", {returnedReport = true})
        else
            local detail = ok and "Model returned no report table." or tostring(result)
            snapshot.issues = snapshot.issues or {}
            snapshot.issues[#snapshot.issues + 1] = {code = "UNDERWRITING_ERROR", detail = detail}
            debugEvent("underwriting.prepare.error", {error = detail})
            debugCheck("UNDERWRITING_PREPARE", "FAIL", {error = detail})
        end
    else
        snapshot.issues = snapshot.issues or {}
        snapshot.issues[#snapshot.issues + 1] = {code = "UNDERWRITING_UNAVAILABLE", detail = "Underwriting module unavailable."}
        debugCheck("UNDERWRITING_PREPARE", "UNAVAILABLE", {reason = "module_unavailable"})
    end
    self.lastSnapshot = snapshot
    return snapshot
end

function LizardBank:cyclePolicy()
    if self.historyRuntime ~= nil then self.historyRuntime:cycleMode() end
    debugEvent("gui.policy.changed", {mode = self.historyRuntime and self.historyRuntime.active and self.historyRuntime.active.mode})
end

function LizardBank:logSnapshot(snapshot)
    log("BEGIN SNAPSHOT (partial coverage; observational preview)")
    log("modVersion=" .. self.VERSION .. " inputHook=" .. tostring(self.inputHook ~= nil)
        .. " guiReady=" .. tostring(self.initialized) .. " actionEvent=" .. scalar(self.actionEventId))
    logTable(snapshot, "snapshot", 0)
    log("END SNAPSHOT")
end

function LizardBank:consoleSnapshot()
    if not self.enabled or not self:isSinglePlayer() then
        return "Lizard Bank is inactive outside single-player."
    end
    self:logSnapshot(self:captureSnapshot())
    return "Lizard Bank snapshot written to log.txt."
end

function LizardBank:consoleOpen()
    local ok, reason = self:openReport()
    return ok and "Lizard Bank opened." or reason
end

function LizardBank:consoleDebug(mode)
    if not self.enabled or not self:isSinglePlayer() then return "Lizard Bank is inactive outside single-player." end
    if BankDiagnostics == nil then return "Validation module unavailable." end
    mode = mode or "summary"
    if mode == "summary" then BankDiagnostics.summary("command"); return "Validation summary written to log.txt (when logging is enabled)." end
    if not BankDiagnostics.setMode(mode) then return "Usage: lbDebug on | trace | off | summary" end
    if mode == "off" then self.validationPrevious = nil else self:beginValidationMission("enabled_by_command") end
    return "Lizard Bank validation mode: " .. mode .. "."
end

function LizardBank:consoleValidate(label)
    if not self.enabled or not self:isSinglePlayer() then return "Lizard Bank is inactive outside single-player." end
    if BankDiagnostics == nil then return "Validation module unavailable." end
    if not BankDiagnostics.isEnabled() then BankDiagnostics.setMode("on") end
    self:beginValidationMission("validation_command")
    local ok, err = pcall(self.captureSnapshot, self, "manual:" .. tostring(label or "checkpoint"):sub(1, 120))
    BankDiagnostics.summary("checkpoint")
    return ok and "Validation checkpoint written to log.txt." or ("Validation capture failed: " .. tostring(err))
end

function LizardBank:consoleMark(label)
    return self:consoleValidate(label or "manual_mark")
end

function LizardBank:consoleExpect(metric, expected)
    if not self.enabled or not self:isSinglePlayer() then return "Lizard Bank is inactive outside single-player." end
    local number = tonumber(expected)
    local readers = {cash = function(s) return s.cash and s.cash.value end, debt = function(s) return s.debt and s.debt.value end,
        landCount = function(s) return s.land and s.land.status == "available" and #s.land.items or nil end,
        equipmentOwned = function(s) return s.equipment and s.equipment.status == "available" and s.equipment.ownedCount or nil end,
        animalsCount = function(s) return s.animals and s.animals.status == "available" and s.animals.totalCount or nil end}
    if readers[metric] == nil or number == nil or number ~= number or math.abs(number) == math.huge then
        return "Usage: lbExpect cash|debt|landCount|equipmentOwned|animalsCount NUMBER (from the native screen)."
    end
    local isMoney = metric == "cash" or metric == "debt"
    if not isMoney and (number < 0 or number ~= math.floor(number)) then return "Count expectations must be nonnegative whole numbers." end
    self:consoleValidate("manual_expectation")
    local actual = self.lastSnapshot and readers[metric](self.lastSnapshot)
    local decimals = tostring(expected):match("%.(%d+)")
    local tolerance = isMoney and 0.5 * 10 ^ -(decimals and math.min(#decimals, 6) or 0) or 0
    debugCheck("MANUAL_EXPECT_" .. metric, actual == nil and "UNAVAILABLE" or (math.abs(actual - number) <= tolerance + 1e-8 and "PASS" or "FAIL"),
        {expected = number, actual = actual, tolerance = tolerance, oracle = "user_supplied_native_screen_value",
            caveat = "Money compares at entered display precision; the log cannot establish that the manual observation is truthful or current."})
    return "Manual comparison recorded; the source observation must be checked independently."
end

function LizardBank:releaseScreen()
    local manager, screen, root = self.guiManager, self.screen, self.guiRoot
    if manager ~= nil and screen ~= nil then
        if root ~= nil and manager.currentGui == root then
            manager:changeScreen(screen, nil)
        end
        local screenClass = screen:class()
        local ownsRegistration = root ~= nil and manager.guis[self.GUI_NAME] == root
        -- Element deletion traverses the focus records, so they must still
        -- exist until all owned GUI elements have been deleted.
        screen:delete()
        if ownsRegistration then
            manager.guis[self.GUI_NAME] = nil
            manager.nameScreenTypes[self.GUI_NAME] = nil
            if FocusManager ~= nil and FocusManager.guiFocusData ~= nil then
                FocusManager.guiFocusData[self.GUI_NAME] = nil
            end
        end
        if manager.screens[screenClass] == root then manager.screens[screenClass] = nil end
        if manager.screenControllers[screenClass] == screen then manager.screenControllers[screenClass] = nil end
    end
    self.screen, self.guiRoot, self.guiManager = nil, nil, nil
    if self.validationMissionActive then debugEvent("gui.release", {hadScreen = screen ~= nil, hadRoot = root ~= nil}) end
end

function LizardBank:deleteMap()
    if self.validationMissionActive then debugEvent("lifecycle.deleteMap.begin", {initialized = self.initialized, hadHistory = self.historyRuntime ~= nil}) end
    self.enabled = false
    self:removeLoadHook()
    if self.historyRuntime ~= nil then self.historyRuntime:delete() end
    self.historyRuntime = nil
    self:removeInputHook()
    if g_inputBinding ~= nil then
        if self.actionEventId ~= nil then g_inputBinding:removeActionEvent(self.actionEventId) end
        g_inputBinding:removeActionEventsByTarget(self)
        if PlayerInputComponent ~= nil and PlayerInputComponent.INPUT_CONTEXT_NAME ~= nil then
            g_inputBinding:beginActionEventsModification(PlayerInputComponent.INPUT_CONTEXT_NAME)
            g_inputBinding:removeActionEventsByTarget(self)
            g_inputBinding:endActionEventsModification()
        end
    end
    if g_messageCenter ~= nil then g_messageCenter:unsubscribeAll(self) end
    self:releaseScreen()
    if self.commandsRegistered and removeConsoleCommand ~= nil then
        removeConsoleCommand("lbSnapshot")
        removeConsoleCommand("lbOpen")
        removeConsoleCommand("lbDebug")
        removeConsoleCommand("lbValidate")
        removeConsoleCommand("lbMark")
        removeConsoleCommand("lbExpect")
    end
    self.commandsRegistered = false
    self.waitingForMission = false
    self.initialized = false
    self.actionEventId = nil
    self.lastSnapshot = nil
    self.validationPrevious = nil
    if self.validationMissionActive and BankDiagnostics ~= nil then
        debugCheck("LIFECYCLE_RELEASED_REFERENCES", self.historyRuntime == nil and self.screen == nil and self.actionEventId == nil and self.lastSnapshot == nil and self.inputHook == nil and self.loadHook == nil and "PASS" or "FAIL", {})
        BankDiagnostics.finishMission({referencesCleared = true, initialized = self.initialized})
    end
    self.validationMissionActive = false
end

addModEventListener(LizardBank)
