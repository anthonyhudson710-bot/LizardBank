-- Run from the repository root: lua tests/test_data.lua
dofile("scripts/BankDataSource.lua")

local count = 0
local function test(name, callback)
    if _G.test ~= nil then
        _G.test("data: " .. name, callback)
        return
    end
    callback()
    count = count + 1
    print("PASS data: " .. name)
end

local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function hasIssue(snapshot, code)
    for _, item in ipairs(snapshot.issues) do
        if item.code == code then return true end
    end
    return false
end

local function fixture()
    local farm = {name = "Farm Seven", money = 120000, loan = 50000}
    local land = {[4] = {id = 4, name = "West", price = 50000, areaInHa = 3}, [9] = {id = 9, price = 70000, areaInHa = 5}}
    return {
        g_currentMission = {
            getFarmId = function() return 7 end,
            environment = {currentYear = 3, currentPeriod = 8, currentDay = 64, dayTime = 3600000},
            vehicleSystem = {vehicles = {}}
        },
        g_farmManager = {getFarmById = function(_, id) assert(id == 7); return farm end},
        g_farmlandManager = {
            getFarmlands = function() return land end,
            getFarmlandOwner = function(_, id) return id == 4 and 7 or 8 end,
            getCanAccessLandAtWorldPosition = function() error("Access permission must never determine ownership") end
        },
        FarmManager = {SPECTATOR_FARM_ID = 0, INVALID_FARM_ID = -1},
        VehiclePropertyState = {OWNED = 11, LEASED = 12, MISSION = 13},
        g_gameVersion = "test-only"
    }, farm, land
end

local function vehicle(id, state, price, owner)
    return {
        uniqueId = id,
        getOwnerFarmId = function() return owner or 7 end,
        getName = function() return "Machine " .. id end,
        getPropertyState = function() return state end,
        getSellPrice = function() return price end
    }
end

test("active farm and strict land ownership", function()
    local context = fixture()
    local snapshot = BankDataSource.capture(context)
    equal(snapshot.farm.id, 7)
    equal(snapshot.farm.name, "Farm Seven")
    equal(snapshot.cash.value, 120000)
    equal(snapshot.debt.value, 50000)
    equal(#snapshot.land.items, 1)
    equal(snapshot.land.totalValue, 50000)
    equal(snapshot.land.totalAreaHa, 3)
    equal(snapshot.capturedAt.day, 64)
end)

test("zero, negative cash, unavailable finance and accessor precedence", function()
    local context, farm = fixture()
    farm.getBalance = function() return -500 end
    farm.getLoan = function() return 0 end
    local snapshot = BankDataSource.capture(context)
    equal(snapshot.cash.value, -500)
    equal(snapshot.debt.value, 0)
    equal(snapshot.debt.status, "available")
    farm.getBalance = nil
    farm.money = 0 / 0
    farm.getLoan = nil
    farm.loan = -1
    snapshot = BankDataSource.capture(context)
    equal(snapshot.cash.value, nil)
    equal(snapshot.debt.value, nil)
    equal(snapshot.debt.status, "unavailable")
end)

test("deduplicate attached equipment without excluding independent implements", function()
    local context = fixture()
    local tractor = vehicle("tractor", 11, 100)
    local implement = vehicle("implement", 11, 30)
    local quoteCalls = 0
    tractor.getSellPrice = function() quoteCalls = quoteCalls + 1; return 100 end
    tractor.attachedImplements = {{object = implement}}
    context.g_currentMission.vehicleSystem.vehicles = {tractor, implement, tractor, vehicle("implement", 11, 30)}
    local snapshot = BankDataSource.capture(context)
    equal(snapshot.equipment.ownedCount, 2)
    equal(snapshot.equipment.ownedValue, 130)
    equal(quoteCalls, 1)
end)

test("leased, borrowed and another farm equipment never inflate owned total", function()
    local context = fixture()
    local leased = vehicle("lease", 12, 100000)
    leased.getSellPrice = function() error("Do not quote non-owned assets") end
    context.g_currentMission.vehicleSystem.vehicles = {
        vehicle("owned", 11, 70), leased, vehicle("mission", 13, 100000), vehicle("other", 11, 100000, 8)
    }
    local snapshot = BankDataSource.capture(context)
    equal(snapshot.equipment.ownedValue, 70)
    equal(snapshot.equipment.leasedCount, 1)
    equal(snapshot.equipment.borrowedCount, 1)
    equal(#snapshot.equipment.items, 3)
end)

test("pallets and big bags are excluded from equipment", function()
    local context = fixture()
    local pallet, bag = vehicle("pallet", 11, 600), vehicle("bag", 11, 700)
    pallet.isPallet = true
    bag.spec_bigBag = {}
    context.g_currentMission.vehicleSystem.vehicles = {pallet, bag}
    local snapshot = BankDataSource.capture(context)
    equal(snapshot.equipment.ownedValue, 0)
    equal(snapshot.equipment.excludedCount, 2)
    equal(#snapshot.equipment.items, 0)
end)

test("loaded trailer uses the engine quote exactly once without inventory additions", function()
    local context = fixture()
    local trailer = vehicle("loaded", 11, 12500)
    trailer.spec_livestockTrailer = {contentsValue = 999999}
    context.g_currentMission.vehicleSystem.vehicles = {trailer}
    local snapshot = BankDataSource.capture(context)
    equal(snapshot.equipment.ownedValue, 12500)
    equal(snapshot.equipment.items[1].quoteIncludesContents, true)
end)

test("bad quote and unknown state preserve a useful partial list", function()
    local context = fixture()
    local broken = vehicle("broken", 11, nil)
    broken.getSellPrice = function() error("third party accessor failure") end
    context.g_currentMission.vehicleSystem.vehicles = {vehicle("good", 11, 10), broken, vehicle("unknown", 99, 9999)}
    local snapshot = BankDataSource.capture(context)
    equal(snapshot.equipment.ownedValue, 10)
    equal(snapshot.equipment.unknownValueCount, 1)
    equal(snapshot.equipment.status, "partial")
    equal(#snapshot.equipment.items, 3)
    assert(hasIssue(snapshot, "ACCESSOR_ERROR"))
    assert(hasIssue(snapshot, "VEHICLE_PROPERTY_UNAVAILABLE"))
end)

test("unavailable is distinct from a verified empty collection", function()
    local context = fixture()
    local empty = BankDataSource.capture(context)
    equal(empty.equipment.ownedValue, 0)
    context.g_currentMission.vehicleSystem = nil
    local missing = BankDataSource.capture(context)
    equal(missing.equipment.ownedValue, nil)
    equal(missing.equipment.status, "unavailable")
    equal(BankDataSource.capture({}).cash.value, nil)
end)

test("all unvalued assets never produce a zero valuation", function()
    local context, _, land = fixture()
    land[4].price = math.huge
    land[4].areaInHa = nil
    context.g_currentMission.vehicleSystem.vehicles = {vehicle("bad", 11, math.huge)}
    local snapshot = BankDataSource.capture(context)
    equal(snapshot.land.totalValue, nil)
    equal(snapshot.land.totalAreaHa, nil)
    equal(snapshot.land.unknownValueCount, 1)
    equal(snapshot.equipment.ownedValue, nil)
end)

test("unknown ownership does not become another farm's asset", function()
    local context = fixture()
    local unknown = vehicle("unattributed", 11, 9000)
    unknown.getOwnerFarmId = function() return nil end
    context.g_currentMission.vehicleSystem.vehicles = {unknown}
    local snapshot = BankDataSource.capture(context)
    equal(#snapshot.equipment.items, 0)
    equal(snapshot.equipment.ownedValue, nil)
    assert(hasIssue(snapshot, "VEHICLE_OWNER_UNAVAILABLE"))
end)

test("refresh makes a detached snapshot and retains no live objects", function()
    local context, farm, land = fixture()
    local first = BankDataSource.capture(context)
    farm.money = 123
    land[4].price = 321
    local second = BankDataSource.capture(context)
    equal(first.cash.value, 120000)
    equal(first.land.items[1].value, 50000)
    equal(second.cash.value, 123)
    equal(second.land.items[1].value, 321)
end)

test("verified vehicle lookup fallback and missing state constants", function()
    local context = fixture()
    context.g_currentMission.vehicleSystem = {vehicleByUniqueId = {a = vehicle("a", 11, 20)}}
    local snapshot = BankDataSource.capture(context)
    equal(snapshot.equipment.ownedValue, 20)
    assert(hasIssue(snapshot, "VEHICLE_ENUMERATION_FALLBACK"))
    context.VehiclePropertyState = nil
    snapshot = BankDataSource.capture(context)
    equal(snapshot.equipment.items[1].ownership, "unknown")
    equal(snapshot.equipment.ownedValue, nil)
end)

test("overflow never escapes as an infinite financial subtotal", function()
    local context, _, land = fixture()
    context.g_farmlandManager.getFarmlandOwner = function() return 7 end
    land[4].price, land[9].price = 1e308, 1e308
    land[4].areaInHa, land[9].areaInHa = 1e308, 1e308
    context.g_currentMission.vehicleSystem.vehicles = {vehicle("a", 11, 1e308), vehicle("b", 11, 1e308)}
    local snapshot = BankDataSource.capture(context)
    equal(snapshot.land.totalValue, nil)
    equal(snapshot.land.totalAreaHa, nil)
    equal(snapshot.equipment.ownedValue, nil)
    assert(hasIssue(snapshot, "LAND_TOTAL_OVERFLOW"))
    assert(hasIssue(snapshot, "EQUIPMENT_TOTAL_OVERFLOW"))
end)

test("monotonic game day wins over optional calendar day", function()
    local context = fixture()
    context.g_currentMission.environment.currentMonotonicDay = 400
    equal(BankDataSource.capture(context).capturedAt.day, 400)
end)

test("mixed numeric and string asset IDs sort consistently", function()
    local context = fixture()
    context.g_currentMission.vehicleSystem.vehicles = {
        vehicle("15", 11, 3), vehicle(10, 11, 2), vehicle(2, 11, 1)
    }
    local snapshot = BankDataSource.capture(context)
    equal(snapshot.equipment.items[1].id, 2)
    equal(snapshot.equipment.items[2].id, 10)
    equal(snapshot.equipment.items[3].id, "15")
    equal(snapshot.equipment.ownedValue, 6)
end)

if _G.test == nil then
    print(string.format("Data collector: %d tests passed", count))
end
