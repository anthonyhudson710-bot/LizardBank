dofile("scripts/BankFinancialReport.lua")
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
    end,
    formatVolume = function(_, value, decimals)
        assertEqual(decimals, 1)
        return string.format("%.1f L", value)
    end,
    formatNumber = function(_, value, decimals)
        assertEqual(decimals, 1)
        return string.format("%.1f", value)
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
        local captures, failing, mode = 0, false, "standard"
        local screen = BankScreen.new({captureSnapshot = function()
            captures = captures + 1
            if failing then error("fixture failure") end
            local result = snapshot()
            result.history = {mode = mode}
            return result
        end, cyclePolicy = function() mode = "strict" end})
        for _, key in ipairs({"pageTitle", "pageNumber", "reportText", "backButton", "previousButton", "nextButton", "refreshButton", "policyButton"}) do
            screen[key] = {setText = function(self, value) self.text = value end}
        end
        screen:onGuiSetupFinished()
        assertEqual(FocusManager.links, 10)
        screen:onOpen()
        assertEqual(captures, 1)
        assertTrue(cursor)
        assertEqual(FocusManager.focused, screen.refreshButton)
        screen:onClickNext()
        screen:onClickPrevious()
        assertEqual(captures, 1)
        screen:onClickRefresh()
        assertEqual(captures, 2)
        screen:onClickPolicy()
        assertEqual(captures, 3)
        assertContains(screen.policyButton.text, "Strict")
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

test("financial report discloses raw native slots without importing them as complete history", function()
    local data = snapshot()
    data.finance = {source = "fixture native statistics", knownValueCount = 2, unknownValueCount = 1, unclassifiedCount = 1,
        records = {
            {bucketKind = "historyCandidate", periodKey = 3, label = "Harvest", rawSignedValue = -40, classification = "operating"},
            {bucketKind = "currentCandidate", periodKey = "current", label = "Mystery", classification = "unclassified"}
        }}
    local report = joined(BankReport.buildPages(data, i18n))
    assertContains(report, "Native slot 3 | Harvest")
    assertContains(report, "Raw amount: $-40")
    assertContains(report, "Raw amount: Unavailable")
    assertContains(report, "not dated cash-flow totals")
    assertContains(report, "Insufficient history")
    assertFalse(report:find("Provisional native-data score:", 1, true) ~= nil)
end)

test("financial report presents full model evidence and keeps cash scenario separate from asset value", function()
    local data = snapshot()
    data.underwriting = {modelVersion = "1.0.0", mode = "strict", history = {completePeriodCount = 12,
        totals = {operatingCashBeforeInterest = 900, cashBeforePrincipal = 800}},
        assessment = {status = "available", score = 64, band = "guarded", components = {
            {name = "cashBufferMonths", value = 2, points = 10, weight = 30, weakThreshold = 1,
                strongThreshold = 4, status = "available", formula = "Cash divided by observed monthly costs"}},
            reasons = {{code = "NATIVE_ONLY", detail = "External obligations unverified"}}},
        collateral = {knownAssetQuotes = 200},
        forecast = {status = "available", annualCashBeforePrincipal = 800, periods = {
            {year = 2, month = 4, sourceYear = 1, sourceMonth = 4, operatingRevenue = 100,
                operatingExpense = 30, interestExpense = 10, cashBeforePrincipal = 60}}}}
    data.history = {retainedLimit = 36, mode = "strict", persistence = "save_callback_candidate", periods = {},
        current = {year = 2, month = 3, startDay = 44, openingCash = 100, closingCash = 120, events = 1,
            operatingRevenue = 20, operatingExpense = 0, interestExpense = 0, capitalInflow = 0, capitalOutflow = 0,
            financingInflow = 0, financingOutflow = 0, unclassifiedInflow = 0, unclassifiedOutflow = 0,
            categories = {soldMilk = {inflow = 20, outflow = 0}}, gaps = {}}, anchor = {day = 45}}
    local pages = BankReport.buildPages(data, i18n)
    local report = joined(pages)
    assertContains(report, "score: 64 / 100 | Guarded")
    assertContains(report, "Policy: Strict")
    assertContains(report, "Points: 10.00 / 30")
    assertContains(report, "Baseline: local cycle 1, native period 4")
    assertContains(report, "principal: $60")
    assertContains(report, "soldMilk | In: $20 | Out: $0")
    assertContains(report, "including cash (partial): $350")
    assertContains(report, "not a safe loan payment")
    for _, page in ipairs(pages) do
        local _, count = page.text:gsub("\n", "")
        assertTrue(count + 1 <= BankReport.LINES_PER_PAGE)
    end
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

test("building monetary values extend the subtotal without promising sale proceeds", function()
    local data = snapshot()
    data.buildings = {status = "partial", totalValue = 400, ownedCount = 2,
        unknownValueCount = 1, excludedCount = 0, items = {
            {id = "shed", name = "Old shed", status = "available", value = 400, canBeSold = false},
            {id = "barn", name = "Mod barn", status = "unavailable", value = 999}
        }}
    local report = joined(BankReport.buildPages(data, i18n))
    assertContains(report, "including cash (partial): $750")
    assertContains(report, "Known owned-building monetary value: $400")
    assertContains(report, "Owned placeables: 2 | Unvalued: 1")
    assertContains(report, "Old shed (ID shed)")
    assertContains(report, "Game monetary value: Unavailable")
    assertContains(report, "currently blocks selling")
    assertFalse(report:find("$999", 1, true) ~= nil)
end)

test("goods show native quantities and container ownership without adding inventory money", function()
    local data = snapshot()
    data.inventory = {status = "partial", sourceCount = 3, zeroCount = 1, unknownCount = 1, excludedCount = 0,
        totalValue = 999, items = {
            {location = "Leased trailer", fillTypeTitle = "Wheat", fillTypeName = "WHEAT", quantity = 2500.5,
                quantityStatus = "available", unit = "l", kind = "vehicle", ownership = "leased", value = 999},
            {location = "Tree nursery", fillTypeTitle = "Saplings", quantity = 12,
                quantityStatus = "available", unit = "units", unitText = "trees", kind = "pallet", ownership = "owned"},
            {location = "Mod silo", fillTypeName = "Soybeans", quantity = 999,
                quantityStatus = "unavailable", unit = "l", kind = "storage", ownership = "owned"}
        }}
    local report = joined(BankReport.buildPages(data, i18n))
    assertContains(report, "including cash (partial): $350")
    assertContains(report, "Wheat: 2500.5 L")
    assertContains(report, "Location: Leased trailer | Container: Leased")
    assertContains(report, "Saplings: 12.0 trees")
    assertContains(report, "Soybeans: Unavailable")
    assertContains(report, "Container ownership does not prove cargo ownership")
    assertFalse(report:find("$999", 1, true) ~= nil)
end)

test("missing buildings and goods remain unavailable while verified empty buildings show zero", function()
    local data = snapshot()
    local report = joined(BankReport.buildPages(data, i18n))
    assertContains(report, "Owned placeables: Unavailable")
    assertContains(report, "Containers checked: Unavailable")
    assertFalse(report:find("No owned buildings", 1, true) ~= nil)
    data.buildings = {status = "available", totalValue = 0, ownedCount = 0,
        unknownValueCount = 0, excludedCount = 0, items = {}}
    report = joined(BankReport.buildPages(data, i18n))
    assertContains(report, "Known owned-building monetary value: $0")
    assertContains(report, "No owned buildings or placeables found")
end)

test("large stored-goods reports preserve every location within page limits", function()
    local data = snapshot()
    data.inventory = {status = "partial", sourceCount = 90, zeroCount = 0, unknownCount = 0, excludedCount = 0, items = {}}
    for index = 1, 90 do
        data.inventory.items[index] = {location = "Silo " .. index, fillTypeTitle = "Wheat", quantity = index,
            unit = "l", ownership = "owned", kind = "storage"}
    end
    local pages = BankReport.buildPages(data, i18n)
    assertContains(joined(pages), "Location: Silo 90 | Container: Owned")
    for _, page in ipairs(pages) do
        local _, count = page.text:gsub("\n", "")
        assertTrue(count + 1 <= BankReport.LINES_PER_PAGE)
    end
end)

test("overflow across otherwise finite asset sections is unavailable", function()
    local data = snapshot()
    data.land.totalValue = 1e308
    data.buildings = {status = "available", totalValue = 1e308, items = {}}
    assertContains(joined(BankReport.buildPages(data, i18n)), "including cash (partial): Unavailable")
end)

test("bale report preserves current contents, fermentation and unavailable virtual quantities", function()
    local data = snapshot()
    data.inventory = {status = "partial", sourceCount = 2, zeroCount = 0, unknownCount = 1,
        excludedCount = 0, coverage = {bales = "available", objectStorage = "partial"}, items = {
            {location = "bale:31", fillTypeTitle = "Grass", quantity = 4000, unit = "l", ownership = "owned",
                kind = "bale", isFermenting = true, fermentationProgress = 0.25, objectCount = 1},
            {location = "Pallet shed", objectName = "Seed pallet", fillTypeName = "Unknown fill type",
                quantityStatus = "unavailable", ownership = "unknown", kind = "storedPallet", objectCount = 1}
        }}
    local report = joined(BankReport.buildPages(data, i18n))
    assertContains(report, "Grass: 4000.0 L")
    assertContains(report, "Fermenting: 25.0%")
    assertContains(report, "Seed pallet: Unavailable")
    assertContains(report, "Physical or stored objects in this entry: 1")
    assertContains(report, "Physical bales: Checked | Bale/pallet stores: Partial")
    assertContains(report, "including cash (partial): $350")
    assertFalse(report:find("Silage", 1, true) ~= nil)
    data.inventory.items[1].fermentationProgress = 1.5
    assertContains(joined(BankReport.buildPages(data, i18n)), "Fermenting; progress unavailable")
end)

test("livestock reference values stay separate from covered assets and retain native condition", function()
    local data = snapshot()
    data.animals = {status = "partial", ownedHusbandryCount = 1, clusterCount = 2, totalCount = 12,
        totalValue = 900, unknownCountCount = 1, unknownValueCount = 1, items = {
            {name = "Holstein", location = "North barn", count = 12, ageMonths = 24,
                healthPercent = 80, reproductionPercent = 0, unitValue = 75, value = 900, subtypeKey = "COW_HOLSTEIN"},
            {name = "Mod sheep", location = "North barn"}
        }}
    local report = joined(BankReport.buildPages(data, i18n))
    assertContains(report, "Known animals: 12")
    assertContains(report, "Holstein | Count: 12")
    assertContains(report, "Age: 24 months | Health: 80.0% | Reproduction: 0.0%")
    assertContains(report, "Mod sheep | Count: Unavailable")
    assertContains(report, "Known animal reference value (separate): $900")
    assertContains(report, "Group reference value: Unavailable")
    assertContains(report, "Native quote per animal: $75 | Group reference value: $900")
    assertContains(report, "Subtype: COW_HOLSTEIN")
    assertContains(report, "including cash (partial): $350")
    assertContains(report, "not added to covered assets")
end)

test("livestock empty supported data and absent coverage never look identical", function()
    local data = snapshot()
    local report = joined(BankReport.buildPages(data, i18n))
    assertContains(report, "Known animal reference value (separate): Unavailable")
    assertFalse(report:find("No animals found", 1, true) ~= nil)
    data.animals = {status = "available", ownedHusbandryCount = 1, clusterCount = 0,
        totalCount = 0, totalValue = 0, unknownCountCount = 0, unknownValueCount = 0, items = {}}
    report = joined(BankReport.buildPages(data, i18n))
    assertContains(report, "Known animal reference value (separate): $0")
    assertContains(report, "No animals found")
end)

test("large livestock reports retain every group without overflowing page lines", function()
    local data = snapshot()
    data.animals = {status = "partial", items = {}}
    for index = 1, 100 do
        data.animals.items[index] = {name = "Animal group " .. index, location = "Husbandry " .. index,
            count = 5, healthPercent = math.huge, reproductionPercent = -1}
    end
    local pages = BankReport.buildPages(data, i18n)
    assertContains(joined(pages), "Animal group 100 | Count: 5")
    assertContains(joined(pages), "Health: Unavailable | Reproduction: Unavailable")
    for _, page in ipairs(pages) do
        local _, count = page.text:gsub("\n", "")
        assertTrue(count + 1 <= BankReport.LINES_PER_PAGE)
    end
end)
