-- Instrumentation must observe the original read path without changing it.
dofile("scripts/BankPropertyDataSource.lua")
dofile("scripts/BankAnimalDataSource.lua")
dofile("scripts/BankStoredObjectDataSource.lua")
dofile("scripts/BankInventoryDataSource.lua")
dofile("scripts/BankFinanceDataSource.lua")
dofile("scripts/BankDataSource.lua")

local function equalTree(a, b, path)
    path = path or "root"
    assertEqual(type(a), type(b), path .. " type")
    if type(a) ~= "table" then
        assertEqual(a, b, path)
        return
    end
    for key, value in pairs(a) do equalTree(value, b[key], path .. "." .. tostring(key)) end
    for key in pairs(b) do assertTrue(a[key] ~= nil, path .. " unexpected key " .. tostring(key)) end
end

local function fixture()
    local calls, live = {}, {}
    local function native(name, fn)
        return function(...)
            calls[name] = (calls[name] or 0) + 1
            return fn(...)
        end
    end
    local function object(value) live[value] = true; return value end
    local current = object({soldProducts = 350, purchaseSeeds = -50, other = 0})
    local stats = object({farmId = 7, finances = current, financesHistory = {current, {soldProducts = 20}}})
    local farm = object({money = 10000, loan = 2000, name = "Diagnostics farm", stats = stats})
    farm.getBalance = native("cash", function() return farm.money end)
    farm.getLoan = native("debt", function() return farm.loan end)
    local parcel = object({id = 4, price = 25000, areaInHa = 3})
    local storage = object({uniqueId = "grain-store",
        getOwnerFarmId = native("storage.owner", function() return 7 end),
        getFillLevels = native("storage.levels", function() return {[1] = 600, [2] = 0} end)})
    local herd = object({health = 90, reproduction = 0.5,
        getNumAnimals = native("herd.count", function() return 4 end),
        getSellPrice = native("herd.quote", function() return 200 end),
        getAge = native("herd.age", function() return 12 end),
        getSubTypeIndex = native("herd.subtype", function() return 1 end)})
    local barn = object({uniqueId = "barn", spec_silo = {storages = {storage}},
        spec_husbandryAnimals = {},
        getUniqueId = native("barn.id", function() return "barn" end),
        getOwnerFarmId = native("barn.owner", function() return 7 end),
        getName = native("barn.name", function() return "Barn" end),
        getMonetaryValue = native("barn.quote", function() return 30000 end),
        canBeSold = native("barn.sale", function() return false end),
        getClusters = native("barn.clusters", function() return {herd, herd} end)})
    local vehicle = object({uniqueId = "tractor",
        getOwnerFarmId = native("vehicle.owner", function() return 7 end),
        getPropertyState = native("vehicle.state", function() return 11 end),
        getName = native("vehicle.name", function() return "Tractor" end),
        getSellPrice = native("vehicle.quote", function() return 15000 end),
        getFillUnits = native("vehicle.units", function() return {{unitText = "l"}} end),
        getFillUnitFillLevel = native("vehicle.quantity", function() return 40 end),
        getFillUnitFillType = native("vehicle.fillType", function() return 2 end)})
    local foreign = object({uniqueId = "foreign",
        getOwnerFarmId = native("foreign.owner", function() return 9 end),
        getSellPrice = function() error("Foreign value must never be read") end,
        getFillUnits = function() error("Foreign quantities must never be read") end})
    local baleClass = object({})
    local bale = object({uniqueId = "bale-1", isMissionBale = false,
        getUniqueId = native("bale.id", function() return "bale-1" end),
        isa = native("bale.class", function(_, class) return class == baleClass end),
        getOwnerFarmId = native("bale.owner", function() return 7 end),
        getFillLevel = native("bale.quantity", function() return 4000 end),
        getFillType = native("bale.fillType", function() return 1 end),
        getIsFermenting = native("bale.fermenting", function() return false end)})
    local virtual = object({REFERENCE_CLASS_NAME = "Bale",
        getRealObject = native("virtual.real", function() return bale end),
        getDialogText = native("virtual.text", function() return "Stored bale" end)})
    barn.spec_objectStorage = {storedObjects = {virtual, virtual}}
    local context = {
        g_currentMission = object({getFarmId = native("mission.farmId", function() return 7 end),
            farmStats = native("mission.stats", function(_, id) assertEqual(id, 7); return stats end),
            environment = {currentMonotonicDay = 20, currentYear = 2, currentPeriod = 4, dayTime = 3600000},
            placeableSystem = {placeables = {barn, barn}},
            vehicleSystem = {vehicles = {vehicle, vehicle, foreign}},
            storageSystem = {storages = {storage}},
            itemSystem = {items = {bale, bale}},
            animalSystem = {getSubTypeByIndex = native("animalSystem.subtype", function() return {fillTypeIndex = 1, name = "COW"} end)}}),
        g_farmManager = {getFarmById = native("farmManager.get", function(_, id) assertEqual(id, 7); return farm end)},
        g_farmlandManager = {getFarmlands = native("farmlands.get", function() return {parcel, parcel, {id = 5, price = 100}} end),
            getFarmlandOwner = native("farmlands.owner", function(_, id) return id == 4 and 7 or 9 end)},
        g_fillTypeManager = {getFillTypeByIndex = native("fillType.get", function(_, id) return {name = "TYPE_" .. id, title = "Native type"} end)},
        FinanceStats = {statNamesI18n = {soldProducts = "Products"}},
        Bale = baleClass, FillType = {UNKNOWN = 0},
        VehiclePropertyState = {OWNED = 11, LEASED = 12, MISSION = 13}
    }
    return {context = context, calls = calls, live = live, farm = farm, barn = barn, herd = herd, vehicle = vehicle}
end

local function runWithDiagnostics(enabled, scenario, fn)
    local old, entries = BankDiagnostics, {}
    local function dto(value)
        if type(value) ~= "table" then
            assertTrue(value == nil or type(value) == "string" or type(value) == "boolean"
                or (type(value) == "number" and value == value and math.abs(value) < math.huge))
            return value
        end
        assertFalse(scenario.live[value] == true, "Live object leaked into diagnostic DTO")
        local result = {}
        for k, v in pairs(value) do
            assertTrue(type(k) == "string" or type(k) == "number")
            result[k] = dto(v)
        end
        return result
    end
    BankDiagnostics = {
        isEnabled = function() return enabled end,
        emit = function(name, evidence)
            assertTrue(enabled, "Disabled diagnostics emitted an event")
            entries[#entries + 1] = {kind = "event", name = name, evidence = dto(evidence)}
        end,
        check = function(id, outcome, evidence)
            assertTrue(enabled)
            entries[#entries + 1] = {kind = "check", id = id, outcome = outcome, evidence = dto(evidence)}
        end,
        read = function(section, name, ok, value, details)
            assertTrue(enabled)
            -- This is the API's shallow read contract: no traversal of a native
            -- table, metatable, function, node or userdata is permitted.
            local summary = {type = type(value)}
            if type(value) == "string" or type(value) == "boolean"
                or (type(value) == "number" and value == value and math.abs(value) < math.huge) then summary.value = value end
            entries[#entries + 1] = {kind = "read", section = section, name = name, ok = ok,
                summary = summary, details = dto(details)}
        end
    }
    local ok, result = pcall(fn, entries)
    BankDiagnostics = old
    if not ok then error(result, 0) end
    return result, entries
end

local function find(entries, kind, name, outcome)
    for _, entry in ipairs(entries) do
        if entry.kind == kind and (entry.id == name or entry.name == name)
            and (outcome == nil or entry.outcome == outcome) then return entry end
    end
end

test("collector diagnostics preserve every snapshot value and native call count when enabled", function()
    local scenario = fixture()
    local baseline, offEvents = runWithDiagnostics(false, scenario, function() return BankDataSource.capture(scenario.context) end)
    assertEqual(#offEvents, 0)
    local counts = {}
    for name, count in pairs(scenario.calls) do counts[name] = count; scenario.calls[name] = 0 end
    local observed, entries = runWithDiagnostics(true, scenario, function() return BankDataSource.capture(scenario.context) end)
    equalTree(observed, baseline)
    equalTree(scenario.calls, counts, "native calls")
    assertTrue(#entries > 50)
    for _, id in ipairs({"CASH_GETTER_FIELD_MATCH", "DEBT_GETTER_FIELD_MATCH", "LAND_OWNER", "LAND_DEDUP",
        "EQUIPMENT_OWNER", "EQUIPMENT_DEDUP", "EQUIPMENT_VALUE", "PROPERTY_OWNER", "PROPERTY_DEDUP",
        "ANIMAL_OWNER", "ANIMAL_COUNT", "ANIMAL_CLUSTER_DEDUP", "STORAGE_OWNER", "STORAGE_DEDUP",
        "INVENTORY_QUANTITY", "INVENTORY_ZERO", "STORED_OBJECT_OWNER", "STORED_OBJECT_DEDUP",
        "LOOSE_BALE_DEDUP", "FINANCE_BUCKET_DEDUP", "FINANCE_RAW_VALUE"}) do
        assertTrue(find(entries, "check", id) ~= nil, "Missing diagnostic evidence " .. id)
    end
    assertTrue(find(entries, "event", "collector.enter") ~= nil)
    assertTrue(find(entries, "event", "collector.exit") ~= nil)
end)

test("collector diagnostics distinguish missing accessors thrown errors nil returns and verified zero", function()
    local scenario = fixture()
    scenario.farm.getBalance = nil
    scenario.farm.money = 0
    scenario.farm.getLoan = function() return nil end
    scenario.barn.getMonetaryValue = function() error("synthetic quote failure") end
    local result, entries = runWithDiagnostics(true, scenario, function() return BankDataSource.capture(scenario.context) end)
    assertEqual(result.cash.value, 0)
    assertEqual(result.debt.value, 2000)
    local missing = find(entries, "read", "getBalance")
    assertFalse(missing.ok)
    assertEqual(missing.details.reason, "missing_accessor")
    local empty = find(entries, "read", "getLoan")
    assertTrue(empty.ok)
    assertEqual(empty.summary.type, "nil")
    local failed = find(entries, "read", "getMonetaryValue")
    assertFalse(failed.ok)
    assertEqual(failed.details.reason, "accessor_error")
    assertContains(failed.summary.value, "synthetic quote failure")
    assertTrue(find(entries, "check", "CASH_GETTER_FIELD_MATCH", "UNAVAILABLE") ~= nil)
    assertTrue(find(entries, "check", "PROPERTY_VALUE", "UNAVAILABLE") ~= nil)
end)

test("collector diagnostics report getter-field disagreement without replacing the selected source", function()
    local scenario = fixture()
    scenario.farm.getBalance = function() return -125 end
    scenario.farm.getLoan = function() return 0 end
    local result, entries = runWithDiagnostics(true, scenario, function() return BankDataSource.capture(scenario.context) end)
    assertEqual(result.cash.value, -125)
    assertEqual(result.debt.value, 0)
    local mismatch = find(entries, "check", "CASH_GETTER_FIELD_MATCH", "FAIL")
    assertEqual(mismatch.evidence.value, -125)
    assertEqual(mismatch.evidence.expected, 10000)
    assertTrue(find(entries, "check", "DEBT_GETTER_FIELD_MATCH", "FAIL") ~= nil)
end)

test("collector diagnostic DTOs stay detached and native return tables are only shallow read inputs", function()
    local scenario = fixture()
    local nativeTable = setmetatable({}, {__index = function() error("Do not inspect native return metadata") end})
    scenario.live[nativeTable] = true
    scenario.farm.getBalance = function() return nativeTable end
    local result, entries = runWithDiagnostics(true, scenario, function() return BankDataSource.capture(scenario.context) end)
    assertEqual(result.cash.value, 10000)
    local read = find(entries, "read", "getBalance")
    assertEqual(read.summary.type, "table")
    assertEqual(read.summary.value, nil)
    scenario.farm.money = 1
    local raw = find(entries, "read", "farm.money")
    assertEqual(raw.summary.value, 10000)
end)

test("collector diagnostics preserve unfamiliar owners and explicitly record foreign exclusion decisions", function()
    local scenario = fixture()
    scenario.vehicle.getOwnerFarmId = function() return nil end
    scenario.vehicle.ownerFarmId = 7
    local result, entries = runWithDiagnostics(true, scenario, function() return BankDataSource.capture(scenario.context) end)
    assertEqual(result.equipment.ownedCount, 0)
    assertTrue(find(entries, "check", "EQUIPMENT_OWNER", "UNAVAILABLE") ~= nil)
    local foreign
    for _, entry in ipairs(entries) do
        if entry.id == "EQUIPMENT_OWNER" and entry.evidence.id == "foreign" then foreign = entry end
    end
    assertEqual(foreign.evidence.value, 9)
    assertEqual(foreign.evidence.expected, 7)
    assertContains(foreign.evidence.reason, "Excluded")
end)

test("collector MoneyType instrumentation preserves exact identity results and does not traverse tokens", function()
    local scenario, token = fixture(), {}
    scenario.live[token] = true
    local registry = {SOLD_PRODUCTS = token}
    local baseline = {BankFinanceDataSource.classifyMoneyType(token, registry)}
    local observed, entries = runWithDiagnostics(true, scenario, function()
        return {BankFinanceDataSource.classifyMoneyType(token, registry)}
    end)
    equalTree(observed, baseline)
    assertTrue(find(entries, "check", "MONEY_TYPE_CLASSIFICATION", "PASS") ~= nil)
end)
