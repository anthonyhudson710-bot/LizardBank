dofile("scripts/BankAnimalDataSource.lua")

local function cluster(count, price, subtype)
    return {
        health = 85,
        getNumAnimals = function() return count end,
        getSellPrice = function() return price end,
        getSubTypeIndex = function() return subtype or 1 end,
        getAge = function() return 12 end
    }
end

local function husbandry(id, owner, clusters)
    return {
        spec_husbandryAnimals = {},
        getUniqueId = function() return id end,
        getName = function() return "Husbandry " .. tostring(id) end,
        getOwnerFarmId = function() return owner end,
        getClusters = function() return clusters end
    }
end

local function contextFor(placeables)
    return {
        g_currentMission = {
            placeableSystem = {placeables = placeables},
            animalSystem = {getSubTypeByIndex = function(_, index)
                return {name = "NATIVE_SUBTYPE_" .. tostring(index), fillTypeIndex = index}
            end}
        },
        g_fillTypeManager = {getFillTypeByIndex = function(_, index)
            return {title = index == 1 and "Cattle" or "Sheep"}
        end}
    }
end

local function capture(placeables, farmId)
    local snapshot = {farm = {id = farmId or 8}, issues = {}, capabilities = {}}
    BankAnimalDataSource.collect(snapshot, contextFor(placeables))
    return snapshot
end

local function hasIssue(snapshot, code)
    for _, entry in ipairs(snapshot.issues) do
        if entry.code == code then return true end
    end
    return false
end

test("animals read owned husbandries and multiply native per-animal quotes exactly once", function()
    local foreign = cluster(900, 10000)
    foreign.getSellPrice = function() error("Foreign animals must not be scanned") end
    local result = capture({husbandry("a", 8, {cluster(3, 100)}), husbandry("b", 8, {cluster(2, 250, 2)}), husbandry("foreign", 4, {foreign}), husbandry("map", 0, {foreign})})
    assertEqual(result.animals.ownedHusbandryCount, 2)
    assertEqual(result.animals.clusterCount, 2)
    assertEqual(result.animals.totalCount, 5)
    assertEqual(result.animals.totalValue, 800)
    assertEqual(result.animals.items[1].unitValue, 100)
    assertEqual(result.animals.items[1].value, 300)
    assertEqual(result.animals.items[1].healthPercent, 85)
    assertEqual(result.animals.status, "available")
    assertFalse(hasIssue(result, "ANIMAL_ACCESSOR_ERROR"))
    assertContains(result.animals.items[1].valueSource, "no additional fee/transport calculation")
end)

test("animals distinguish verified empty husbandry coverage from unavailable enumeration", function()
    local empty = capture({husbandry("empty", 8, {})})
    assertEqual(empty.animals.totalCount, 0)
    assertEqual(empty.animals.totalValue, 0)
    assertEqual(empty.animals.ownedHusbandryCount, 1)
    assertEqual(capture({}).animals.totalValue, 0)
    local missing = capture(nil)
    assertEqual(missing.animals.totalCount, nil)
    assertEqual(missing.animals.totalValue, nil)
    assertEqual(missing.animals.status, "unavailable")
end)

test("animals require a resolved farm and mission without assuming farm one", function()
    assertEqual(capture({}, 0).animals.totalCount, nil)
    local snapshot = {farm = {}, issues = {}, capabilities = {}}
    BankAnimalDataSource.collect(snapshot, {})
    assertEqual(snapshot.animals.status, "unavailable")
    assertEqual(snapshot.animals.totalValue, nil)
end)

test("animals use documented registered placeable lookup when list is absent", function()
    local context = contextFor(nil)
    context.g_currentMission.placeableSystem.placableByUniqueId = {barn = husbandry("barn", 8, {cluster(2, 30)})}
    local snapshot = {farm = {id = 8}, issues = {}, capabilities = {}}
    BankAnimalDataSource.collect(snapshot, context)
    assertEqual(snapshot.animals.totalValue, 60)
    assertContains(snapshot.capabilities.animalEnumeration, "placableByUniqueId")
    assertTrue(hasIssue(snapshot, "ANIMAL_ENUMERATION_FALLBACK"))
end)

test("animals deduplicate husbandry aliases and repeated cluster references without merging distinct groups", function()
    local herd = cluster(3, 100)
    local barn = husbandry("a", 8, {herd, herd, cluster(3, 100)})
    local result = capture({barn, barn, husbandry("a", 8, {cluster(999, 100)}), husbandry("b", 8, {herd})})
    assertEqual(result.animals.ownedHusbandryCount, 2)
    assertEqual(result.animals.clusterCount, 2)
    assertEqual(result.animals.totalCount, 6)
    assertEqual(result.animals.totalValue, 600)
    assertEqual(result.capabilities.animalDuplicateHusbandryCount, 2)
    assertEqual(result.capabilities.animalDuplicateClusterCount, 2)
end)

test("animals never infer ownership from fields or access permissions", function()
    local barn = husbandry("unknown", nil, {cluster(90, 100)})
    barn.ownerFarmId = 8
    barn.getIsAccessible = function() return true end
    local result = capture({barn})
    assertEqual(result.animals.ownedHusbandryCount, 0)
    assertEqual(result.animals.totalCount, nil)
    assertEqual(result.animals.totalValue, nil)
    assertEqual(result.animals.excludedCount, 1)
    assertTrue(hasIssue(result, "ANIMAL_OWNER_UNAVAILABLE"))
end)

test("animals preserve valid zero counts prices and health", function()
    local empty, worthless = cluster(0, 10), cluster(2, 0)
    empty.health, worthless.health = 0, 0
    local result = capture({husbandry("a", 8, {empty, worthless})})
    assertEqual(result.animals.totalCount, 2)
    assertEqual(result.animals.totalValue, 0)
    assertEqual(result.animals.unknownValueCount, 0)
    assertEqual(result.animals.items[1].healthPercent, 0)
    assertEqual(result.animals.items[1].status, "available")
end)

test("animals never convert unknown or fractional counts into zero or a quoted group value", function()
    local records = {cluster(nil, 100), cluster(-1, 100), cluster(1.5, 100), cluster(math.huge, 100), cluster(0 / 0, 100), cluster("4", 100)}
    local result = capture({husbandry("a", 8, records)})
    assertEqual(result.animals.totalCount, nil)
    assertEqual(result.animals.totalValue, nil)
    assertEqual(result.animals.unknownCountCount, #records)
    assertEqual(result.animals.unknownValueCount, #records)
    assertEqual(result.animals.items[1].unitValue, 100)
end)

test("animals preserve known counts when all native quotes are unavailable", function()
    local records = {cluster(2, nil), cluster(2, -1), cluster(2, math.huge), cluster(2, 0 / 0), cluster(2, "100")}
    local result = capture({husbandry("a", 8, records)})
    assertEqual(result.animals.totalCount, 10)
    assertEqual(result.animals.totalValue, nil)
    assertEqual(result.animals.unknownValueCount, #records)
    assertEqual(result.animals.status, "partial")
end)

test("animals use documented raw count only when getter is absent and never mask getter failure", function()
    local plain, broken = cluster(2, 10), cluster(2, 10)
    plain.getNumAnimals, plain.numAnimals = nil, 4
    broken.getNumAnimals = function() error("custom count failed") end
    broken.numAnimals = 900
    local result = capture({husbandry("a", 8, {plain, broken})})
    assertEqual(result.animals.totalCount, 4)
    assertEqual(result.animals.totalValue, 40)
    assertEqual(result.animals.unknownCountCount, 1)
    assertTrue(hasIssue(result, "ANIMAL_ACCESSOR_ERROR"))
end)

test("animals isolate failed quote and metadata getters while preserving healthy groups", function()
    local broken = cluster(3, 30)
    broken.getSellPrice = function() error("quote failed") end
    broken.getSubTypeIndex = function() error("metadata failed") end
    local result = capture({husbandry("a", 8, {broken, cluster(2, 10)})})
    assertEqual(result.animals.totalCount, 5)
    assertEqual(result.animals.totalValue, 20)
    assertEqual(result.animals.unknownValueCount, 1)
    assertEqual(result.animals.clusterCount, 2)
    assertTrue(hasIssue(result, "ANIMAL_ACCESSOR_ERROR"))
end)

test("animals show an explicit unavailable group when a husbandry cannot enumerate clusters", function()
    local broken = husbandry("a", 8, {})
    broken.getClusters = function() error("cluster system unloading") end
    local result = capture({broken, husbandry("b", 8, {cluster(2, 10)})})
    assertEqual(result.animals.ownedHusbandryCount, 2)
    assertEqual(result.animals.totalCount, 2)
    assertEqual(result.animals.unknownCountCount, 1)
    assertEqual(result.animals.unknownValueCount, 1)
    assertEqual(result.animals.items[1].status, "unavailable")
    assertTrue(hasIssue(result, "ANIMAL_CLUSTERS_UNAVAILABLE"))
end)

test("animals isolate malformed placeables and clusters without suppressing supported figures", function()
    local result = capture({false, husbandry("a", 8, {false, "broken", cluster(2, 10)})})
    assertEqual(result.animals.excludedCount, 1)
    assertEqual(result.animals.unknownCountCount, 2)
    assertEqual(result.animals.clusterCount, 1)
    assertEqual(result.animals.totalCount, 2)
    assertEqual(result.animals.totalValue, 20)
    assertTrue(hasIssue(result, "ANIMAL_HUSBANDRY_ERROR"))
    assertTrue(hasIssue(result, "ANIMAL_CLUSTER_ERROR"))
end)

test("animals omit husbandries and groups being removed without inventing empty coverage", function()
    local barn, herd = husbandry("a", 8, {cluster(2, 10)}), cluster(2, 10)
    barn.markedForDeletion, herd.isDeleted = true, true
    local result = capture({barn, husbandry("b", 8, {herd})})
    assertEqual(result.animals.totalCount, nil)
    assertEqual(result.animals.totalValue, nil)
    assertEqual(result.animals.excludedCount, 1)
    assertTrue(hasIssue(result, "ANIMAL_HUSBANDRY_REMOVING"))
    assertTrue(hasIssue(result, "ANIMAL_CLUSTER_REMOVING"))
end)

test("animals reject overflowing group values and subtotals while retaining finite evidence", function()
    local product = capture({husbandry("a", 8, {cluster(10, 1e308)})})
    assertEqual(product.animals.items[1].unitValue, 1e308)
    assertEqual(product.animals.items[1].value, nil)
    assertEqual(product.animals.totalValue, nil)
    local valueSum = capture({husbandry("a", 8, {cluster(1, 1e308), cluster(1, 1e308)})})
    assertEqual(valueSum.animals.totalValue, nil)
    assertEqual(valueSum.animals.items[1].value, 1e308)
    assertTrue(hasIssue(valueSum, "ANIMAL_VALUE_OVERFLOW"))
    local countSum = capture({husbandry("a", 8, {cluster(1e308, 0), cluster(1e308, 0)})})
    assertEqual(countSum.animals.totalCount, nil)
    assertEqual(countSum.animals.totalValue, 0)
    assertTrue(hasIssue(countSum, "ANIMAL_COUNT_OVERFLOW"))
end)

test("animals keep age and reproduction raw diagnostics without inventing confirmed units", function()
    local herd = cluster(2, 10)
    herd.reproduction = 0.5
    local result = capture({husbandry("a", 8, {herd})})
    local row = result.animals.items[1]
    assertEqual(row.ageRaw, 12)
    assertContains(row.ageSource, "unit unverified")
    assertEqual(row.reproductionRaw, 0.5)
    assertContains(row.reproductionSource, "diagnostic only")
    assertEqual(row.ageMonths, nil)
    assertEqual(row.reproductionPercent, nil)
    assertEqual(row.healthPercent, 85)
    assertFalse(result.capabilities.animalAgeUnitsVerified)
    assertFalse(result.capabilities.animalReproductionUnitsVerified)
    assertTrue(hasIssue(result, "ANIMAL_OPTIONAL_DETAILS_UNVERIFIED"))
end)

test("animals reject invalid health and raw optional objects without leaking references", function()
    local herd = cluster(2, 10)
    herd.health, herd.reproduction = 101, {}
    herd.getAge = function() return {} end
    herd.getName = function() return {} end
    local result = capture({husbandry("a", 8, {herd})})
    assertEqual(result.animals.items[1].healthPercent, nil)
    assertEqual(result.animals.items[1].ageRaw, nil)
    assertEqual(result.animals.items[1].reproductionRaw, nil)
    assertEqual(result.animals.totalValue, 20)
    assertTrue(hasIssue(result, "ANIMAL_HEALTH_UNAVAILABLE"))
end)

test("animals use localized native labels and individual names without guessing breed metadata", function()
    local horse = cluster(1, 10)
    horse.getName = function() return "Scout" end
    local result = capture({husbandry("a", 8, {horse, cluster(2, 10, 2)})})
    assertEqual(result.animals.items[1].name, "Scout")
    assertEqual(result.animals.items[1].nativeTypeName, "Cattle")
    assertEqual(result.animals.items[1].subtypeKey, "NATIVE_SUBTYPE_1")
    assertEqual(result.animals.items[2].name, "Sheep")
    assertEqual(result.animals.items[2].species, nil)
    assertEqual(result.animals.items[2].subtype, nil)
end)

test("animals remain useful without optional animal or fill type metadata systems", function()
    local context = contextFor({husbandry("a", 8, {cluster(2, 10)})})
    context.g_currentMission.animalSystem, context.g_fillTypeManager = nil, nil
    local snapshot = {farm = {id = 8}, issues = {}, capabilities = {}}
    BankAnimalDataSource.collect(snapshot, context)
    assertEqual(snapshot.animals.items[1].name, "Animal group")
    assertEqual(snapshot.animals.totalCount, 2)
    assertEqual(snapshot.animals.totalValue, 20)
    assertTrue(hasIssue(snapshot, "ANIMAL_NAME_UNAVAILABLE"))
end)

test("animals defer transported and ridden stock and do not perform economic or reproductive updates", function()
    local herd = cluster(2, 10)
    for _, name in ipairs({"updateReproduction", "onPeriodChanged", "changeNumAnimals", "updateNow"}) do
        herd[name] = function() error("Read-only snapshot invoked " .. name) end
    end
    local context = contextFor({husbandry("a", 8, {herd})})
    context.g_currentMission.vehicles = {{spec_livestockTrailer = {}, getClusters = function() error("Transported animals must be deferred") end}, {spec_rideable = {cluster = herd}}}
    local snapshot = {farm = {id = 8}, issues = {}, capabilities = {}}
    BankAnimalDataSource.collect(snapshot, context)
    assertEqual(snapshot.animals.totalCount, 2)
    assertEqual(snapshot.animals.transportedStatus, "excluded")
    assertEqual(snapshot.animals.riddenStatus, "excluded")
    assertTrue(hasIssue(snapshot, "ANIMAL_COVERAGE_PARTIAL"))
    assertFalse(hasIssue(snapshot, "ANIMAL_ACCESSOR_ERROR"))
end)

test("animals return detached scalar rows and refresh without retaining mission state", function()
    local herd = cluster(2, 10)
    local context = contextFor({husbandry("a", 8, {herd})})
    local snapshot = {farm = {id = 8}, issues = {}, capabilities = {}}
    BankAnimalDataSource.collect(snapshot, context)
    local old = snapshot.animals
    herd.getNumAnimals = function() return 4 end
    BankAnimalDataSource.collect(snapshot, context)
    assertEqual(old.totalCount, 2)
    assertEqual(snapshot.animals.totalCount, 4)
    for _, row in ipairs(snapshot.animals.items) do
        for _, value in pairs(row) do
            assertTrue(type(value) == "string" or type(value) == "number" or type(value) == "boolean")
        end
    end
    for _, value in pairs(snapshot.capabilities) do
        assertTrue(type(value) == "string" or type(value) == "number" or type(value) == "boolean")
    end
end)
