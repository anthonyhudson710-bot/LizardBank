-- Lifecycle contract tests. Stubs do not reproduce the FS25 renderer/input engine.
local function fixture()
    local state = {captures = 0, opens = 0, closes = 0, deletes = 0, events = {}, nextId = 0,
        commands = {}, profiles = 0, logs = {}, originalCalls = 0}
    local env = setmetatable({}, {__index = _G})
    env.g_currentModName, env.g_currentModDirectory = "FS25_LizardBank", ""
    env.g_currentMission = {missionDynamicInfo = {isMultiplayer = false}, missionInfo = {}}
    env.g_dedicatedServer = nil
    env.print = function(message) state.logs[#state.logs + 1] = message end
    env.addModEventListener = function(listener) state.listener = listener end
    env.addConsoleCommand = function(name) state.commands[name] = true end
    env.removeConsoleCommand = function(name) state.commands[name] = nil end
    env.InputAction = {LIZARDBANK_OPEN = "LIZARDBANK_OPEN"}
    env.g_i18n = {getText = function(_, key) return key end}
    env.FocusManager = {currentGui = "Loading", guiFocusData = {Loading = {}}}
    function env.FocusManager:setGui(name)
        self.currentGui = name
        self.guiFocusData[name] = self.guiFocusData[name] or {}
    end
    env.PlayerInputComponent = {
        INPUT_CONTEXT_NAME = "PLAYER",
        registerGlobalPlayerActionEvents = function() state.originalCalls = state.originalCalls + 1 end
    }
    state.originalInput = env.PlayerInputComponent.registerGlobalPlayerActionEvents
    env.g_inputBinding = {context = "BASE"}
    function env.g_inputBinding:beginActionEventsModification(context) self.context = context end
    function env.g_inputBinding:endActionEventsModification() self.context = "BASE" end
    function env.g_inputBinding:removeActionEvent(id) state.events[id] = nil end
    function env.g_inputBinding:removeActionEventsByTarget(target)
        for id, event in pairs(state.events) do
            if event.target == target and event.context == self.context then state.events[id] = nil end
        end
    end
    function env.g_inputBinding:registerActionEvent(_, target)
        state.nextId = state.nextId + 1
        state.events[state.nextId] = {target = target, context = self.context}
        return true, state.nextId
    end
    function env.g_inputBinding:setActionEventTextVisibility() end
    function env.g_inputBinding:setActionEventText() end
    env.g_messageCenter = {unsubscribeAll = function() end}
    env.BankDataSource = {capture = function()
        state.captures = state.captures + 1
        return {farm = {id = state.captures}, cash = {value = 0}}
    end}
    local screenClass = {}
    env.BankScreen = {new = function(owner)
        local screen = {owner = owner}
        function screen:class() return screenClass end
        function screen:onOpen() self.owner:captureSnapshot() end
        function screen:onClose() state.closes = state.closes + 1 end
        function screen:delete()
            -- Real GuiElement.delete traverses the still-live focus record.
            if self.loaded then assertTrue(env.FocusManager.guiFocusData.LizardBank ~= nil) end
            self.owner = nil
            state.deletes = state.deletes + 1
        end
        return screen
    end}
    env.g_gui = {guis = {}, screens = {}, screenControllers = {}, nameScreenTypes = {}}
    function env.g_gui:loadProfiles() state.profiles = state.profiles + 1 return true end
    function env.g_gui:loadGui(_, name, screen)
        env.FocusManager:setGui(name)
        if state.failGui then error("Fixture GUI failure") end
        local root = {target = screen}
        self.guis[name], self.screens[screenClass] = root, root
        self.screenControllers[screenClass], self.nameScreenTypes[name] = screen, screenClass
        screen.loaded = true
        return root
    end
    function env.g_gui:showGui(name)
        self.currentGui = self.guis[name]
        state.opens = state.opens + 1
        self.currentGui.target:onOpen()
    end
    function env.g_gui:changeScreen(screen)
        screen:onClose()
        self.currentGui = nil
    end
    function env.g_gui:getIsGuiVisible() return self.currentGui ~= nil end
    function env.g_gui:getIsDialogVisible() return state.dialog == true end
    local chunk = assert(loadfile("scripts/LizardBank.lua"))
    setfenv(chunk, env)
    chunk()
    return env.LizardBank, env, state
end

test("bootstrap waits for mission mode before starting", function()
    local bank, env, state = fixture()
    env.g_currentMission = nil
    bank:loadMap()
    bank:update()
    assertEqual(state.profiles, 0)
    assertEqual(state.captures, 0)
    env.g_currentMission = {missionDynamicInfo = {isMultiplayer = false}, missionInfo = {}}
    bank:update()
    assertTrue(bank.initialized)
    assertEqual(env.FocusManager.currentGui, "Loading")
end)

test("bootstrap initializes once and only scans when requested", function()
    local bank, env, state = fixture()
    bank:loadMap()
    for _ = 1, 100 do bank:update() end
    assertEqual(state.profiles, 1)
    assertEqual(state.nextId, 1)
    assertEqual(state.captures, 0)
    assertTrue(bank:openReport())
    assertEqual(state.captures, 1)
    assertFalse(bank:openReport())
    assertEqual(state.captures, 1)
    env.g_gui:changeScreen(bank.screen)
    state.dialog = true
    assertFalse(bank:openReport())
    bank:consoleSnapshot()
    assertEqual(state.captures, 2)
    assertContains(table.concat(state.logs, "\n"), "snapshot.cash.value=0")
end)

test("multiplayer and dedicated sessions remain inactive", function()
    for _, dedicated in ipairs({false, true}) do
        local bank, env, state = fixture()
        env.g_currentMission.missionDynamicInfo.isMultiplayer = not dedicated
        if dedicated then env.g_dedicatedServer = {} end
        bank:loadMap()
        bank:update()
        assertFalse(bank.enabled)
        assertFalse(bank.initialized)
        assertEqual(next(state.commands), nil)
        assertEqual(state.profiles, 0)
        assertEqual(state.captures, 0)
    end
end)

test("unload releases inputs, focus, screen, commands and snapshot", function()
    local bank, env, state = fixture()
    bank:loadMap()
    bank:update()
    bank:openReport()
    env.g_inputBinding.context = "MENU"
    bank:deleteMap()
    assertEqual(state.closes, 1)
    assertEqual(state.deletes, 1)
    assertEqual(next(state.events), nil)
    assertEqual(next(state.commands), nil)
    assertEqual(env.g_gui.guis.LizardBank, nil)
    assertEqual(next(env.g_gui.screens), nil)
    assertEqual(next(env.g_gui.screenControllers), nil)
    assertEqual(env.FocusManager.guiFocusData.LizardBank, nil)
    assertEqual(bank.lastSnapshot, nil)
    assertEqual(bank.screen, nil)
    assertEqual(env.PlayerInputComponent.registerGlobalPlayerActionEvents, state.originalInput)
    bank:deleteMap()
    assertEqual(state.deletes, 1)
end)

test("loading another save creates a fresh screen and snapshot", function()
    local bank, env, state = fixture()
    bank:loadMap()
    bank:update()
    local firstScreen = bank.screen
    bank:openReport()
    bank:deleteMap()
    bank:loadMap()
    bank:update()
    assertTrue(bank.screen ~= firstScreen)
    assertEqual(bank.lastSnapshot, nil)
    assertEqual(state.profiles, 1)
    bank:openReport()
    assertEqual(bank.lastSnapshot.farm.id, 2)
end)

test("input rebuild preserves base behavior without accumulating events", function()
    local bank, env, state = fixture()
    bank:loadMap()
    bank:update()
    for _ = 1, 4 do
        env.PlayerInputComponent.registerGlobalPlayerActionEvents({player = {isOwner = true}})
    end
    local count = 0
    for _ in pairs(state.events) do count = count + 1 end
    assertEqual(count, 1)
    assertEqual(state.originalCalls, 4)
end)

test("unload preserves another mod's later input wrapper", function()
    local bank, env, state = fixture()
    bank:loadMap()
    bank:update()
    local ours = env.PlayerInputComponent.registerGlobalPlayerActionEvents
    local foreign = function(component) ours(component) end
    env.PlayerInputComponent.registerGlobalPlayerActionEvents = foreign
    bank:deleteMap()
    assertEqual(env.PlayerInputComponent.registerGlobalPlayerActionEvents, foreign)
    foreign({player = {isOwner = true}})
    assertEqual(next(state.events), nil)
    bank:loadMap()
    bank:update()
    assertEqual(env.PlayerInputComponent.registerGlobalPlayerActionEvents, foreign)
    foreign({player = {isOwner = true}})
    assertEqual(state.originalCalls, 2)
end)

test("failed GUI setup restores previous focus and avoids frame retries", function()
    local bank, env, state = fixture()
    state.failGui = true
    bank:loadMap()
    bank:update()
    assertTrue(bank.initFailed)
    assertFalse(bank.initialized)
    assertEqual(env.FocusManager.currentGui, "Loading")
    assertEqual(bank.screen, nil)
    for _ = 1, 10 do bank:update() end
    assertEqual(state.deletes, 1)
    assertContains(bank:consoleSnapshot(), "log.txt")
end)

test("load completion initializes history before first clock update and preserves native returns", function()
    local bank, env = fixture()
    local observed, deleted, starts = nil, 0, 0
    env.g_currentMission.environment = {dayTime = 1000}
    local original = function(_, marker) return nil, marker, 77 end
    env.Mission00 = {loadMission00Finished = original}
    env.BankHistoryRuntime = {new = function(mission)
        local runtime = {capabilities = {}, start = function() observed = mission.environment.dayTime; starts = starts + 1 end,
            update = function() end, delete = function() deleted = deleted + 1 end}
        function runtime:safe(method) return method(self) end
        return runtime
    end}
    bank:loadMap()
    assertEqual(starts, 0)
    local a, b, c = env.Mission00.loadMission00Finished(env.g_currentMission, "native")
    assertEqual(a, nil); assertEqual(b, "native"); assertEqual(c, 77)
    assertEqual(observed, 1000)
    assertEqual(bank.historyRuntime.capabilities.startTiming, "load_complete_candidate")
    env.g_currentMission.environment.dayTime = 1016
    bank:update(16)
    assertEqual(starts, 1)
    bank:deleteMap()
    assertEqual(deleted, 1)
    assertEqual(env.Mission00.loadMission00Finished, original)
end)

test("an undispatched load callback cannot block first-update history with diagnostics off", function()
    local bank, env, state = fixture()
    local starts = 0
    env.BankDiagnostics = nil
    env.Mission00 = {loadMission00Finished = function() end}
    env.BankHistoryRuntime = {new = function()
        local runtime = {capabilities = {}, start = function() starts = starts + 1 end, update = function() end}
        function runtime:safe(method) return method(self) end
        return runtime
    end}
    bank:loadMap()
    bank:update(16)
    assertEqual(starts, 1)
    assertEqual(state.captures, 0)
    assertEqual(bank.historyRuntime.capabilities.startTiming, "first_update_fallback")
    env.Mission00.loadMission00Finished(env.g_currentMission)
    bank:update(16)
    assertEqual(starts, 1, "Late callback must not duplicate observers")
end)

test("later loading wrappers survive unload and cannot resurrect the bank observer", function()
    local bank, env = fixture()
    local nativeCalls = 0
    env.Mission00 = {loadMission00Finished = function() nativeCalls = nativeCalls + 1 end}
    bank:loadMap()
    local ours = env.Mission00.loadMission00Finished
    local foreign = function(...) return ours(...) end
    env.Mission00.loadMission00Finished = foreign
    bank:deleteMap()
    foreign(env.g_currentMission)
    assertEqual(nativeCalls, 1)
    assertEqual(bank.historyRuntime, nil)
    assertEqual(env.Mission00.loadMission00Finished, foreign)
end)

test("model preparation failures remain explicit instead of looking like ordinary withheld results", function()
    local bank, env = fixture()
    local checks, events = {}, {}
    env.BankDiagnostics = {isEnabled = function() return true end,
        emit = function(id, data) events[id] = data end,
        check = function(id, status) checks[id] = status end}
    env.BankUnderwriting = {prepare = function() error("fixture model failure") end}
    local snapshot = bank:collectSnapshot()
    assertEqual(snapshot.underwriting, nil)
    assertEqual(snapshot.issues[1].code, "UNDERWRITING_ERROR")
    assertEqual(checks.UNDERWRITING_PREPARE, "FAIL")
    assertContains(events["underwriting.prepare.error"].error, "fixture model failure")
    env.BankUnderwriting.prepare = function() return nil end
    snapshot = bank:collectSnapshot()
    assertEqual(checks.UNDERWRITING_PREPARE, "FAIL")
    assertEqual(snapshot.issues[1].code, "UNDERWRITING_ERROR")
    env.BankUnderwriting = false
    snapshot = bank:collectSnapshot()
    assertEqual(checks.UNDERWRITING_PREPARE, "UNAVAILABLE")
    assertEqual(snapshot.issues[1].code, "UNDERWRITING_UNAVAILABLE")
end)

test("manual expectations do not certify unavailable counts as verified zero", function()
    local bank, env = fixture()
    local checks = {}
    env.BankDiagnostics = {isEnabled = function() return true end, beginMission = function() end,
        beginCapture = function() end, endCapture = function() end, emit = function() end, dump = function() end,
        summary = function() end, check = function(id, status, evidence) checks[id] = {status = status, evidence = evidence} end}
    env.BankValidation = {evaluate = function() end}
    env.BankDataSource.capture = function()
        return {farm = {id = 7}, cash = {status = "available", value = 100.4},
            equipment = {status = "unavailable", ownedCount = 0}, animals = {status = "partial", totalCount = 0}}
    end
    bank.enabled = true
    bank:consoleExpect("equipmentOwned", "0")
    assertEqual(checks.MANUAL_EXPECT_equipmentOwned.status, "UNAVAILABLE")
    bank:consoleExpect("animalsCount", "0")
    assertEqual(checks.MANUAL_EXPECT_animalsCount.status, "UNAVAILABLE")
    bank:consoleExpect("cash", "100")
    assertEqual(checks.MANUAL_EXPECT_cash.status, "PASS")
    assertEqual(checks.MANUAL_EXPECT_cash.evidence.tolerance, 0.5)
    bank:consoleExpect("cash", "100.00")
    assertEqual(checks.MANUAL_EXPECT_cash.status, "FAIL")
    env.BankDataSource.capture = function() error("new capture failed") end
    bank:consoleExpect("cash", "100")
    assertEqual(checks.MANUAL_EXPECT_cash.status, "UNAVAILABLE")
    assertEqual(bank.lastSnapshot, nil)
end)
