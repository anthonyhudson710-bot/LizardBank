dofile("scripts/BankPropertyDataSource.lua")

local function property(id, owner, value, canSell)
    return {
        getUniqueId = function() return id end,
        getOwnerFarmId = function() return owner end,
        getName = function() return "Building " .. tostring(id) end,
        getMonetaryValue = function() return value end,
        canBeSold = function() return canSell end
    }
end

local function capture(placeables, farmId)
    local snapshot = {farm = {id = farmId or 8}, issues = {}, capabilities = {}}
    BankPropertyDataSource.collect(snapshot, {g_currentMission = {placeableSystem = {placeables = placeables}}})
    return snapshot
end

local function hasIssue(snapshot, code)
    for _, value in ipairs(snapshot.issues) do
        if value.code == code then return true end
    end
    return false
end

test("buildings include only the resolved farm and accept zero monetary value", function()
    local result = capture({property("shed", 8, 12000, true), property("decoration", 8, 0, false), property("other", 3, 900000, true), property("map", 0, 800000, true)})
    assertEqual(result.buildings.ownedCount, 2)
    assertEqual(result.buildings.totalValue, 12000)
    assertEqual(result.buildings.unknownValueCount, 0)
    assertEqual(result.buildings.status, "available")
    assertEqual(result.buildings.items[1].value, 0)
end)

test("buildings distinguish a complete empty registry from unavailable enumeration", function()
    assertEqual(capture({}).buildings.totalValue, 0)
    local unavailable = capture(nil)
    assertEqual(unavailable.buildings.totalValue, nil)
    assertEqual(unavailable.buildings.status, "unavailable")
    assertTrue(hasIssue(unavailable, "BUILDINGS_UNAVAILABLE"))
end)

test("buildings require a valid active farm and placeable system", function()
    local snapshot = {farm = {}, issues = {}, capabilities = {}}
    BankPropertyDataSource.collect(snapshot, {})
    assertEqual(snapshot.buildings.status, "unavailable")
    assertEqual(snapshot.buildings.totalValue, nil)
    assertEqual(capture({}, 0).buildings.totalValue, nil)
end)

test("buildings deduplicate both repeated objects and registered unique identifiers", function()
    local shed = property("shed", 8, 12000, true)
    local result = capture({shed, shed, property("shed", 8, 12000, true), property("barn", 8, 30000, true)})
    assertEqual(result.buildings.ownedCount, 2)
    assertEqual(result.buildings.totalValue, 42000)
    assertEqual(result.capabilities.propertyDuplicateCount, 2)
end)

test("buildings never use temporary construction refunds or inferred purchase costs", function()
    local shed = property("shed", 8, 12000, true)
    shed.price = 100000
    shed.getSellPrice = function() error("A temporary refund must not be read") end
    local unknown = property("unknown", 8, nil, true)
    unknown.price = 200000
    unknown.getPrice = function() error("Purchase cost must not be read") end
    local result = capture({shed, unknown})
    assertEqual(result.buildings.totalValue, 12000)
    assertEqual(result.buildings.unknownValueCount, 1)
    assertFalse(hasIssue(result, "PROPERTY_ACCESSOR_ERROR"))
end)

test("buildings preserve advisory sale veto separately from monetary value", function()
    local result = capture({property("a", 8, 10, true), property("b", 8, 20, false), property("c", 8, 30, nil)})
    assertEqual(result.buildings.totalValue, 60)
    assertTrue(result.buildings.items[1].canBeSold)
    assertFalse(result.buildings.items[2].canBeSold)
    assertEqual(result.buildings.items[3].canBeSold, nil)
    assertEqual(result.capabilities.propertySaleEligibilityAvailableCount, 2)
    assertEqual(result.capabilities.propertySaleEligibilityUnavailableCount, 1)
    assertContains(result.buildings.items[1].source, "not a sale guarantee")
end)

test("buildings reject missing, invalid, negative and nonfinite values without claiming zero", function()
    local values = {false, "100", -1, math.huge, -math.huge, 0 / 0, {value = 99}}
    local list = {property("missing", 8, nil, true)}
    for index, value in ipairs(values) do
        list[#list + 1] = property(index, 8, value, true)
    end
    local result = capture(list)
    assertEqual(result.buildings.totalValue, nil)
    assertEqual(result.buildings.unknownValueCount, #list)
    assertEqual(result.buildings.status, "partial")
    for _, item in ipairs(result.buildings.items) do
        assertEqual(item.value, nil)
        assertEqual(item.status, "unavailable")
    end
end)

test("buildings do not infer ownership from mutable fields or land access", function()
    local unknown = property("unknown", nil, 10000, true)
    unknown.ownerFarmId = 8
    unknown.getIsAccessible = function() return true end
    local result = capture({unknown, property("shed", 8, 500, true)})
    assertEqual(result.buildings.ownedCount, 1)
    assertEqual(result.buildings.totalValue, 500)
    assertEqual(result.buildings.excludedCount, 1)
    assertTrue(hasIssue(result, "PROPERTY_OWNER_UNAVAILABLE"))
end)

test("buildings omit registered objects pending deletion", function()
    local list = {}
    for _, field in ipairs({"markedForDeletion", "isDeleting", "isDeleted"}) do
        local object = property(field, 8, 10000, true)
        object[field] = true
        list[#list + 1] = object
    end
    local result = capture(list)
    assertEqual(result.buildings.excludedCount, 3)
    assertEqual(result.buildings.totalValue, nil)
    assertEqual(result.buildings.status, "partial")
end)

test("buildings retain healthy records when custom monetary accessors throw", function()
    local broken = property("broken", 8, 10000, true)
    broken.getMonetaryValue = function() error("custom specialization failed") end
    local result = capture({broken, property("healthy", 8, 2500, true)})
    assertEqual(result.buildings.ownedCount, 2)
    assertEqual(result.buildings.unknownValueCount, 1)
    assertEqual(result.buildings.totalValue, 2500)
    assertTrue(hasIssue(result, "PROPERTY_ACCESSOR_ERROR"))
end)

test("buildings isolate malformed registry records", function()
    local result = capture({false, "invalid", property("healthy", 8, 2500, true)})
    assertEqual(result.buildings.totalValue, 2500)
    assertEqual(result.buildings.excludedCount, 2)
    assertEqual(result.buildings.status, "partial")
    assertTrue(hasIssue(result, "PROPERTY_RECORD_ERROR"))
end)

test("buildings use the documented lookup spelling when the primary list is absent", function()
    local snapshot = {farm = {id = 8}, issues = {}, capabilities = {}}
    local system = {placableByUniqueId = {shed = property("shed", 8, 12000, true)}}
    BankPropertyDataSource.collect(snapshot, {g_currentMission = {placeableSystem = system}})
    assertEqual(snapshot.buildings.totalValue, 12000)
    assertContains(snapshot.capabilities.propertyEnumeration, "placableByUniqueId")
    assertTrue(hasIssue(snapshot, "PROPERTY_ENUMERATION_FALLBACK"))
end)

test("buildings reject an overflowing subtotal while preserving finite item values", function()
    local result = capture({property("a", 8, 1e308, true), property("b", 8, 1e308, true)})
    assertEqual(result.buildings.totalValue, nil)
    assertEqual(result.buildings.items[1].value, 1e308)
    assertEqual(result.buildings.status, "partial")
    assertTrue(hasIssue(result, "BUILDINGS_TOTAL_OVERFLOW"))
end)

test("buildings return detached scalar data and do not retain stale values", function()
    local object = property("shed", 8, 12000, true)
    local context = {g_currentMission = {placeableSystem = {placeables = {object}}}}
    local snapshot = {farm = {id = 8}, issues = {}, capabilities = {}}
    BankPropertyDataSource.collect(snapshot, context)
    local earlierSection = snapshot.buildings
    object.getMonetaryValue = function() return 6000 end
    BankPropertyDataSource.collect(snapshot, context)
    assertEqual(earlierSection.totalValue, 12000)
    assertEqual(snapshot.buildings.totalValue, 6000)
    for _, item in ipairs(snapshot.buildings.items) do
        for _, value in pairs(item) do
            assertTrue(type(value) == "string" or type(value) == "number" or type(value) == "boolean")
        end
    end
    for _, value in pairs(snapshot.capabilities) do
        assertTrue(type(value) == "string" or type(value) == "number" or type(value) == "boolean")
    end
end)

test("buildings contain invalid custom names and identifiers instead of leaking references", function()
    local object = property({}, 8, 12, {})
    object.getName = function() return {} end
    local result = capture({object})
    assertEqual(result.buildings.items[1].id, "snapshot-property-1")
    assertEqual(result.buildings.items[1].name, "snapshot-property-1")
    assertEqual(result.buildings.items[1].canBeSold, nil)
end)
