-- Mission lifecycle, native input integration and the shared bank entry point.
-- Asset scans occur on demand; lightweight money/calendar observation is separate.
LizardBank = {
    VERSION = "0.0.5",
    GUI_NAME = "LizardBank",
    modName = g_currentModName or "FS25_LizardBank",
    modDirectory = g_currentModDirectory or "",
    enabled = false,
    initialized = false
}

local HOOK_KEY = "__lizardBankInputHook"
local LOAD_HOOK_KEY = "__lizardBankLoadHook"
local profileGui

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
    self.waitingForMission = true
    self.initFailed = false
    self:installLoadHook()
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
                owner:startHistory("load_complete_candidate")
            end
            return unpack(result, 1, result.n)
        end
        Mission00[LOAD_HOOK_KEY] = record
        Mission00.loadMission00Finished = record.wrapper
    end
    record.owner, self.loadHook = self, record
end

function LizardBank:removeLoadHook()
    local record = self.loadHook
    if record ~= nil and record.owner == self then
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
    else log("History initialization failed: " .. tostring(result)) end
end

function LizardBank:startMission()
    self.waitingForMission = false
    self.enabled = self:isSinglePlayer()
    self.initialized = false
    if not self.enabled then
        log("Inactive: this preview supports single-player missions only.")
        return
    end
    self:installInputHook()
    if addConsoleCommand ~= nil then
        addConsoleCommand("lbSnapshot", "Write a fresh Lizard Bank snapshot to log.txt", "consoleSnapshot", self)
        addConsoleCommand("lbOpen", "Open the Lizard Bank window", "consoleOpen", self)
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
end

function LizardBank:removeInputHook()
    local record = self.inputHook
    if record ~= nil and record.owner == self then
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
    -- Covers late initialization after the player's first registration. Later
    -- registrations use the context already selected by the game itself.
    if PlayerInputComponent ~= nil and PlayerInputComponent.INPUT_CONTEXT_NAME ~= nil then
        g_inputBinding:beginActionEventsModification(PlayerInputComponent.INPUT_CONTEXT_NAME)
        self:registerInputAction()
        g_inputBinding:endActionEventsModification()
    end
    log("Version " .. self.VERSION .. " ready. Open Lizard Bank in Controls; lbSnapshot writes diagnostics.")
end

function LizardBank:onOpenAction(_, inputValue)
    if inputValue == nil or inputValue > 0 then
        self:openReport()
    end
end

-- Public entry point: future bank triggers call this same method.
function LizardBank:openReport()
    if not self.enabled or not self:isSinglePlayer() then
        return false, "Single-player mission required."
    end
    if not self.initialized or self.screen == nil then
        return false, "Bank window is not ready; check log.txt."
    end
    if g_gui:getIsGuiVisible() or g_gui:getIsDialogVisible() then
        return false, "Close the current menu before opening the bank."
    end
    g_gui:showGui(self.GUI_NAME)
    return true
end

function LizardBank:captureSnapshot()
    if self.enabled and self.historyRuntime == nil then self:startHistory("first_report_fallback") end
    local snapshot = BankDataSource.capture()
    snapshot.modVersion = self.VERSION
    if self.historyRuntime ~= nil then snapshot.history = self.historyRuntime:report()
    else snapshot.history = {periods = {}, materialGaps = {"History tracking unavailable."}} end
    if type(BankUnderwriting) == "table" then
        local ok, result = pcall(BankUnderwriting.prepare, snapshot, snapshot.history, {mode = snapshot.history.mode or "standard"})
        if ok then snapshot.underwriting = result
        else
            snapshot.issues = snapshot.issues or {}
            snapshot.issues[#snapshot.issues + 1] = {code = "UNDERWRITING_ERROR", detail = tostring(result)}
        end
    end
    self.lastSnapshot = snapshot
    return snapshot
end

function LizardBank:cyclePolicy()
    if self.historyRuntime ~= nil then self.historyRuntime:cycleMode() end
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
end

function LizardBank:deleteMap()
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
    end
    self.commandsRegistered = false
    self.waitingForMission = false
    self.initialized = false
    self.actionEventId = nil
    self.lastSnapshot = nil
end

addModEventListener(LizardBank)
