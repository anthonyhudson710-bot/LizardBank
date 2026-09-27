dofile("scripts/BankReport.lua")

local i18n = {
    getText = function(_, key) return BankReport.ENGLISH[key] or key end,
    formatMoney = function(_, value, decimals, showCurrency, useSymbol)
        assertEqual(decimals, 0)
        assertTrue(showCurrency)
        assertFalse(useSymbol)
        return string.format("$%.0f", value)
    end,
    formatArea = function(_, value, decimals)
        assertEqual(decimals, 2)
        return string.format("%.2f ac", value * 2.47105)
    end
}

local function snapshot()
    return {
        farm = {id = 6, name = "Green Farm"},
        capturedAt = {year = 2, period = 4, day = 11, dayTime = 36000000},
        cash = {status = "available", value = 100},
        debt = {status = "available", value = 20},
        land = {status = "available", totalValue = 200, totalAreaHa = 10,
            unknownValueCount = 0, unknownAreaCount = 0,
            items = {{id = 7, name = "East", value = 200, areaHa = 10}}},
        equipment = {status = "available", ownedValue = 50, ownedCount = 1,
            leasedCount = 1, borrowedCount = 1, excludedCount = 0, unknownValueCount = 0,
            items = {
                {id = 1, name = "Owned tractor", ownership = "owned", value = 50},
                {id = 2, name = "Lease tractor", ownership = "leased", value = 999},
                {id = 3, name = "Contract tractor", ownership = "borrowed", value = 999}
            }},
        issues = {}
    }
end

local function joined(pages)
    local texts = {}
    for _, page in ipairs(pages) do texts[#texts + 1] = page.title .. "\n" .. page.text end
    return table.concat(texts, "\n")
end

test("report uses active farm, game date and native currency/area formatting", function()
    local report = joined(BankReport.buildPages(snapshot(), i18n))
    assertContains(report, "Farm: Green Farm (ID 6)")
    assertContains(report, "Game year 2 | Period 4 | Game day 11 | 10:00")
    assertContains(report, "Cash: $100")
    assertContains(report, "Native loan balance: $20")
    assertContains(report, "Area: 24.71 ac | Game price: $200")
    assertContains(report, "including cash (partial): $350")
    assertFalse(report:find("$999", 1, true) ~= nil)
    assertContains(report, "Lease tractor | Leased")
    assertContains(report, "Contract tractor | Borrowed")
end)

test("report distinguishes verified zero, unavailable and known partial totals", function()
    local data = snapshot()
    data.cash = {status = "unavailable", value = 999}
    data.debt.value = 0
    data.land = {status = "unavailable", totalValue = 999, items = {}}
    data.equipment.status = "partial"
    data.equipment.unknownValueCount = 2
    local report = joined(BankReport.buildPages(data, i18n))
    assertContains(report, "Cash: Unavailable")
    assertContains(report, "Native loan balance: $0")
    assertContains(report, "Known farmland value: Unavailable")
    assertContains(report, "including cash (partial): $50")
    assertContains(report, "Unvalued owned equipment: 2")
    assertFalse(report:find("No owned farmland found", 1, true) ~= nil)
    assertContains(report, "this is not net worth or a credit assessment")
end)

test("report fully unavailable input does not invent zero balances", function()
    local report = joined(BankReport.buildPages({}, i18n))
    assertContains(report, "including cash (partial): Unavailable")
    assertContains(report, "Cash: Unavailable")
    assertContains(report, "Owned parcels recorded: Unavailable")
    assertContains(report, "Owned: Unavailable")
    assertFalse(report:find("$0", 1, true) ~= nil)
end)

test("screen captures only on open/refresh, replaces failed data and releases references", function()
    local saved = {Class = Class, ScreenElement = ScreenElement, FocusManager = FocusManager,
        Logging = Logging, g_i18n = g_i18n, g_currentModName = g_currentModName, BankScreen = BankScreen}
    local ok, message = pcall(function()
        local cursor = false
        Class = function(class, base)
            setmetatable(class, {__index = base})
            class.superClass = function() return base end
            return {__index = class}
        end
        ScreenElement = {
            new = function(_, mt) return setmetatable({isBackAllowed = true}, mt) end,
            onGuiSetupFinished = function() end,
            onOpen = function(self) self.oldCursor = cursor; cursor = true; self.isOpen = true end,
            onClose = function(self) cursor = self.oldCursor; self.isOpen = false end,
            changeScreen = function(self, target) assertEqual(target, nil); self:onClose() end,
            delete = function(self) self.deleted = true end
        }
        FocusManager = {LEFT = "left", RIGHT = "right", links = 0,
            linkElements = function(self) self.links = self.links + 1 end,
            setFocus = function(self, control) self.focused = control end}
        Logging = {error = function() end}
        g_i18n, g_currentModName = i18n, "FS25_LizardBank"
        dofile("scripts/BankScreen.lua")
        local captures, failing = 0, false
        local screen = BankScreen.new({captureSnapshot = function()
            captures = captures + 1
            if failing then error("fixture failure") end
            return snapshot()
        end})
        for _, key in ipairs({"pageTitle", "pageNumber", "reportText", "backButton", "previousButton", "nextButton", "refreshButton"}) do
            screen[key] = {setText = function(self, value) self.text = value end}
        end
        screen:onGuiSetupFinished()
        assertEqual(FocusManager.links, 8)
        screen:onOpen()
        assertEqual(captures, 1)
        assertTrue(cursor)
        assertEqual(FocusManager.focused, screen.refreshButton)
        screen:onClickNext()
        screen:onClickPrevious()
        assertEqual(captures, 1)
        screen:onClickRefresh()
        assertEqual(captures, 2)
        failing = true
        screen:onClickRefresh()
        assertEqual(#screen.pages, 1)
        assertContains(screen.reportText.text, "could not be refreshed")
        assertFalse(screen.reportText.text:find("Cash: $100", 1, true) ~= nil)
        screen:onClickBack()
        assertFalse(cursor)
        assertFalse(screen.isOpen)
        assertEqual(#screen.pages, 0)
        screen:delete()
        assertEqual(screen.owner, nil)
        assertTrue(screen.deleted)
    end)
    for _, key in ipairs({"Class", "ScreenElement", "FocusManager", "Logging", "g_i18n", "g_currentModName", "BankScreen"}) do
        _G[key] = saved[key]
    end
    assert(ok, message)
end)

test("large reports paginate every asset and issue without truncation", function()
    local data = snapshot()
    for index = 1, 150 do
        data.equipment.items[#data.equipment.items + 1] = {
            id = index + 10, name = "Machine " .. index, ownership = "owned", value = index
        }
    end
    data.issues = {{code = "LONG", detail = string.rep("界", 200) .. " final marker 100%"}}
    local pages = BankReport.buildPages(data, i18n)
    local report = joined(pages)
    assertTrue(#pages > 30)
    assertContains(report, "Machine 150 | Owned")
    assertContains(report, "final marker 100%")
    for _, page in ipairs(pages) do
        local _, count = page.text:gsub("\n", "")
        assertTrue(count + 1 <= BankReport.LINES_PER_PAGE)
        for line in (page.text .. "\n"):gmatch("(.-)\n") do
            local _, characters = line:gsub("[%z\1-\127\194-\244][\128-\191]*", "")
            assertTrue(characters <= BankReport.LINE_COLUMNS)
        end
    end
end)

test("snapshot formatting is read-only and keeps contents qualification", function()
    local data = snapshot()
    data.equipment.items[1].quoteIncludesContents = true
    local report = joined(BankReport.buildPages(data, i18n))
    assertContains(report, "inventory is not added separately")
    assertEqual(data.cash.value, 100)
    assertEqual(data.equipment.items[1].value, 50)
    assertEqual(#data.equipment.items, 3)
end)

test("localization is scoped to this mod and malformed translation falls back", function()
    local translated = {
        getText = function(_, key, environment)
            assertEqual(environment, "FS25_LizardBank")
            if key == "lb_cash" then return "Cash: %d" end
            if key == "lb_title" then return "Banque" end
            return key
        end
    }
    assertEqual(BankReport.getText(translated, "lb_title", "FS25_LizardBank"), "Banque")
    local report = joined(BankReport.buildPages(snapshot(), translated, "FS25_LizardBank"))
    assertContains(report, "Cash: 100")
end)
