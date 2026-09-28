-- Read-only snapshot boundary. No references to live objects escape capture().
-- Sources and their verification limits are recorded in docs/data-sources.md.
BankDataSource = {}

local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function identifier(value)
    return (type(value) == "string" and value ~= "") or finite(value)
end

local function issue(snapshot, code, detail)
    snapshot.issues[#snapshot.issues + 1] = {code = code, detail = tostring(detail)}
end

local function call(snapshot, object, name, ...)
    if object == nil or type(object[name]) ~= "function" then
        return nil
    end
    local ok, value = pcall(object[name], object, ...)
    if not ok then
        issue(snapshot, "ACCESSOR_ERROR", name .. ": " .. tostring(value))
        return nil
    end
    return value
end

local function fieldNumber(object, name, nonnegative)
    local value = object and object[name]
    if finite(value) and (not nonnegative or value >= 0) then
        return value
    end
    return nil
end

local function runtimeContext()
    return {
        g_currentMission = g_currentMission,
        g_localPlayer = g_localPlayer,
        g_farmManager = g_farmManager,
        g_farmlandManager = g_farmlandManager,
        g_fillTypeManager = g_fillTypeManager,
        g_i18n = g_i18n,
        FinanceStats = FinanceStats,
        FarmManager = FarmManager,
        FillType = FillType,
        Bale = Bale,
        VehiclePropertyState = VehiclePropertyState,
        g_gameVersion = g_gameVersion,
        g_gameVersionDisplay = g_gameVersionDisplay
    }
end

local function readFinance(snapshot, farm, getter, field, allowNegative)
    local result = {status = "unavailable", source = "unavailable"}
    snapshot.capabilities["farm_" .. getter] = farm ~= nil and type(farm[getter]) == "function"
    snapshot.capabilities["farm_" .. field .. "Type"] = type(farm and farm[field])
    local value = call(snapshot, farm, getter)
    if finite(value) and (allowNegative or value >= 0) then
        result.value = value
        result.status = "available"
        result.source = "farm:" .. getter .. "() [compatibility candidate]"
        return result
    end
    value = fieldNumber(farm, field, not allowNegative)
    if value ~= nil then
        result.value = value
        result.status = "available"
        result.source = "farm." .. field .. " [compatibility candidate]"
    else
        issue(snapshot, string.upper(field) .. "_UNAVAILABLE", "No finite " .. field .. " value returned by the farm getter or scalar field.")
    end
    return result
end

local function readFarm(snapshot, context)
    local mission = context.g_currentMission
    local farmId = call(snapshot, mission, "getFarmId")
    if farmId == nil and context.g_localPlayer ~= nil then
        farmId = context.g_localPlayer.farmId
        snapshot.capabilities.farmIdSource = "g_localPlayer.farmId"
    else
        snapshot.capabilities.farmIdSource = "mission:getFarmId()"
    end
    local constants = context.FarmManager or {}
    if not finite(farmId) or farmId <= 0 or farmId == constants.SPECTATOR_FARM_ID or farmId == constants.INVALID_FARM_ID then
        issue(snapshot, "FARM_UNAVAILABLE", "The current player has no resolved active farm.")
        return
    end
    snapshot.farm.id = farmId
    local farm = call(snapshot, context.g_farmManager, "getFarmById", farmId)
    if type(farm) ~= "table" then
        issue(snapshot, "FARM_UNAVAILABLE", "The active farm could not be read from the farm manager.")
        return
    end
    local name = call(snapshot, farm, "getName") or farm.name
    if type(name) == "string" then
        snapshot.farm.name = name
    end
    snapshot.cash = readFinance(snapshot, farm, "getBalance", "money", true)
    snapshot.debt = readFinance(snapshot, farm, "getLoan", "loan", false)
end

local function readDate(snapshot, context)
    local environment = context.g_currentMission and context.g_currentMission.environment
    snapshot.capabilities.environment = type(environment) == "table"
    if type(environment) ~= "table" then
        issue(snapshot, "DATE_UNAVAILABLE", "The game calendar is unavailable.")
        return
    end
    -- Monotonic game day is used by FS25 contract timing. Optional calendar
    -- fields remain compatibility candidates; never invent a calendar date.
    snapshot.capturedAt.year = fieldNumber(environment, "currentYear", true)
    snapshot.capturedAt.period = fieldNumber(environment, "currentPeriod", true)
    snapshot.capturedAt.day = fieldNumber(environment, "currentMonotonicDay", true)
    snapshot.capabilities.daySource = "environment.currentMonotonicDay"
    if snapshot.capturedAt.day == nil then
        snapshot.capturedAt.day = fieldNumber(environment, "currentDay", true)
        snapshot.capabilities.daySource = "environment.currentDay [compatibility candidate]"
    end
    snapshot.capturedAt.dayTime = fieldNumber(environment, "dayTime", true)
    snapshot.capabilities.calendarSource = "environment calendar fields [compatibility candidate]"
    if snapshot.capturedAt.day == nil or snapshot.capturedAt.dayTime == nil then
        issue(snapshot, "DATE_INCOMPLETE", "One or more game calendar fields are unavailable.")
    end
end

local function sortItems(items)
    table.sort(items, function(a, b)
        if type(a.id) ~= type(b.id) then
            return type(a.id) < type(b.id)
        end
        if type(a.id) == "number" and type(b.id) == "number" then
            return a.id < b.id
        end
        return tostring(a.id) < tostring(b.id)
    end)
end

local function readLand(snapshot, context)
    local section = snapshot.land
    local manager = context.g_farmlandManager
    snapshot.capabilities.farmlandManager = type(manager) == "table"
    snapshot.capabilities.getFarmlandOwner = manager ~= nil and type(manager.getFarmlandOwner) == "function"
    snapshot.capabilities.getFarmlands = manager ~= nil and type(manager.getFarmlands) == "function"
    if snapshot.farm.id == nil or manager == nil then
        issue(snapshot, "LAND_UNAVAILABLE", "Active farm or farmland manager is unavailable.")
        return
    end
    local farmlands = call(snapshot, manager, "getFarmlands")
    if type(farmlands) ~= "table" or type(manager.getFarmlandOwner) ~= "function" then
        issue(snapshot, "LAND_UNAVAILABLE", "Farmland enumeration or ownership lookup is unavailable.")
        return
    end
    section.status = "available"
    local valueSum, areaSum, valueCount, areaCount = 0, 0, 0, 0
    local seen = {}
    for key, farmland in pairs(farmlands) do
        local ok, failure = pcall(function()
            if type(farmland) ~= "table" then
                error("Invalid farmland record " .. tostring(key))
            end
            local id = farmland.id or key
            if not identifier(id) then
                error("Farmland identifier is unavailable")
            end
            if seen[id] then
                return
            end
            seen[id] = true
            local owner = call(snapshot, manager, "getFarmlandOwner", id)
            if not finite(owner) then
                section.status = "partial"
                issue(snapshot, "LAND_OWNER_UNAVAILABLE", "Parcel " .. tostring(id) .. " omitted because its owner is unavailable.")
                return
            end
            if owner ~= snapshot.farm.id then
                return
            end
            local item = {
                id = id,
                name = type(farmland.name) == "string" and farmland.name or tostring(id),
                areaHa = fieldNumber(farmland, "areaInHa", true),
                value = fieldNumber(farmland, "price", true),
                source = "farmland.price (current game-configured parcel price)"
            }
            section.items[#section.items + 1] = item
            if item.value ~= nil then
                valueSum, valueCount = valueSum + item.value, valueCount + 1
            else
                section.unknownValueCount = section.unknownValueCount + 1
                issue(snapshot, "LAND_VALUE_UNAVAILABLE", "Parcel " .. tostring(id) .. " has no finite nonnegative price.")
            end
            if item.areaHa ~= nil then
                areaSum, areaCount = areaSum + item.areaHa, areaCount + 1
            else
                section.unknownAreaCount = section.unknownAreaCount + 1
                issue(snapshot, "LAND_AREA_UNAVAILABLE", "Parcel " .. tostring(id) .. " has no finite nonnegative area.")
            end
        end)
        if not ok then
            section.status = "partial"
            issue(snapshot, "LAND_RECORD_ERROR", failure)
        end
    end
    if section.unknownValueCount > 0 or section.unknownAreaCount > 0 then
        section.status = "partial"
    end
    if not finite(valueSum) or not finite(areaSum) then
        section.status = "partial"
        issue(snapshot, "LAND_TOTAL_OVERFLOW", "A land subtotal exceeded the supported numeric range and is unavailable.")
    end
    if finite(valueSum) and (valueCount > 0 or (#section.items == 0 and section.status == "available")) then
        section.totalValue = valueSum
    end
    if finite(areaSum) and (areaCount > 0 or (#section.items == 0 and section.status == "available")) then
        section.totalAreaHa = areaSum
    end
    sortItems(section.items)
end

local function readEquipment(snapshot, context)
    local section = snapshot.equipment
    local mission = context.g_currentMission
    local system = mission and mission.vehicleSystem
    snapshot.capabilities.vehicleSystem = type(system) == "table"
    if snapshot.farm.id == nil or type(system) ~= "table" then
        issue(snapshot, "EQUIPMENT_UNAVAILABLE", "Active farm or vehicle system is unavailable.")
        return
    end
    local vehicles = system.vehicles
    snapshot.capabilities.vehicleEnumeration = "mission.vehicleSystem.vehicles"
    if type(vehicles) ~= "table" then
        vehicles = system.vehicleByUniqueId
        snapshot.capabilities.vehicleEnumeration = "mission.vehicleSystem.vehicleByUniqueId"
        if type(vehicles) == "table" then
            issue(snapshot, "VEHICLE_ENUMERATION_FALLBACK", "Using the registered vehicle lookup because the vehicle list is unavailable.")
        end
    end
    if type(vehicles) ~= "table" then
        issue(snapshot, "EQUIPMENT_UNAVAILABLE", "Registered vehicle enumeration is unavailable.")
        return
    end
    local states = context.VehiclePropertyState or {}
    snapshot.capabilities.vehicleOwnedState = states.OWNED or "unavailable"
    snapshot.capabilities.vehicleLeasedState = states.LEASED or "unavailable"
    snapshot.capabilities.vehicleMissionState = states.MISSION or "unavailable"
    snapshot.capabilities.saleQuoteAvailableCount = 0
    snapshot.capabilities.saleQuoteUnavailableCount = 0
    section.status = "available"
    local seenObjects, seenIds = {}, {}
    local valueSum, valueCount, ordinal = 0, 0, 0
    for _, vehicle in pairs(vehicles) do
        local ok, failure = pcall(function()
            if type(vehicle) ~= "table" then
                error("Invalid registered vehicle record")
            end
            if seenObjects[vehicle] then
                return
            end
            seenObjects[vehicle] = true
            local id = call(snapshot, vehicle, "getUniqueId") or vehicle.uniqueId
            if identifier(id) then
                if seenIds[id] then
                    return
                end
                seenIds[id] = true
            else
                id = nil
            end
            local owner = call(snapshot, vehicle, "getOwnerFarmId")
            if not finite(owner) then
                section.status = "partial"
                section.excludedCount = section.excludedCount + 1
                issue(snapshot, "VEHICLE_OWNER_UNAVAILABLE", "Vehicle " .. tostring(id or "without ID") .. " omitted because its owner cannot be verified.")
                return
            end
            if owner ~= snapshot.farm.id then
                return
            end
            if vehicle.spec_rideable ~= nil then
                section.excludedCount = section.excludedCount + 1
                issue(snapshot, "RIDDEN_ANIMAL_EXCLUDED", "Ridden animal " .. tostring(id or "without ID") .. " is excluded from equipment value and husbandry livestock coverage.")
                return
            end
            if vehicle.isPallet == true or vehicle.spec_pallet ~= nil or vehicle.spec_bigBag ~= nil or vehicle.trainSystem ~= nil then
                section.excludedCount = section.excludedCount + 1
                return
            end
            if call(snapshot, vehicle, "getIsBeingDeleted") == true then
                section.status = "partial"
                section.excludedCount = section.excludedCount + 1
                issue(snapshot, "VEHICLE_REMOVING", "Vehicle " .. tostring(id or "without ID") .. " is being removed; refresh when the operation finishes.")
                return
            end
            ordinal = ordinal + 1
            id = id or ("snapshot-item-" .. tostring(ordinal))
            local name = call(snapshot, vehicle, "getName")
            local state = call(snapshot, vehicle, "getPropertyState")
            if state == nil then
                state = vehicle.propertyState
            end
            local ownership = "unknown"
            if state ~= nil and state == states.OWNED then
                ownership = "owned"
            elseif state ~= nil and state == states.LEASED then
                ownership = "leased"
            elseif state ~= nil and state == states.MISSION then
                ownership = "borrowed"
            end
            local item = {
                id = id,
                name = type(name) == "string" and name or tostring(id),
                ownership = ownership,
                source = "excluded from owned equipment subtotal",
                quoteIncludesContents = true
            }
            section.items[#section.items + 1] = item
            if ownership == "owned" then
                section.ownedCount = section.ownedCount + 1
                item.source = "vehicle:getSellPrice() (engine quote; may include contents)"
                local price = call(snapshot, vehicle, "getSellPrice")
                if finite(price) and price >= 0 then
                    item.value = price
                    valueSum, valueCount = valueSum + price, valueCount + 1
                    snapshot.capabilities.saleQuoteAvailableCount = snapshot.capabilities.saleQuoteAvailableCount + 1
                else
                    section.unknownValueCount = section.unknownValueCount + 1
                    snapshot.capabilities.saleQuoteUnavailableCount = snapshot.capabilities.saleQuoteUnavailableCount + 1
                    section.status = "partial"
                    issue(snapshot, "VEHICLE_VALUE_UNAVAILABLE", "Vehicle " .. tostring(id) .. " has no finite nonnegative sale quote.")
                end
            elseif ownership == "leased" then
                section.leasedCount = section.leasedCount + 1
            elseif ownership == "borrowed" then
                section.borrowedCount = section.borrowedCount + 1
            else
                section.status = "partial"
                section.excludedCount = section.excludedCount + 1
                issue(snapshot, "VEHICLE_PROPERTY_UNAVAILABLE", "Vehicle " .. tostring(id) .. " is listed but excluded because its property state is unrecognized.")
            end
        end)
        if not ok then
            section.status = "partial"
            section.excludedCount = section.excludedCount + 1
            issue(snapshot, "VEHICLE_RECORD_ERROR", failure)
        end
    end
    if not finite(valueSum) then
        section.status = "partial"
        issue(snapshot, "EQUIPMENT_TOTAL_OVERFLOW", "The equipment subtotal exceeded the supported numeric range and is unavailable.")
    elseif valueCount > 0 or (section.ownedCount == 0 and section.status == "available") then
        section.ownedValue = valueSum
    end
    sortItems(section.items)
end

function BankDataSource.capture(context)
    context = context or runtimeContext()
    local snapshot = {
        schemaVersion = 4,
        farm = {},
        capturedAt = {},
        cash = {status = "unavailable", source = "unavailable"},
        debt = {status = "unavailable", source = "unavailable"},
        land = {items = {}, unknownValueCount = 0, unknownAreaCount = 0, status = "unavailable"},
        equipment = {items = {}, ownedCount = 0, leasedCount = 0, borrowedCount = 0, excludedCount = 0, unknownValueCount = 0, status = "unavailable"},
        buildings = {items = {}, status = "unavailable"},
        animals = {items = {}, status = "unavailable"},
        inventory = {items = {}, status = "unavailable"},
        finance = {records = {}, status = "unavailable"},
        issues = {},
        capabilities = {},
        gameVersion = tostring(context.g_gameVersionDisplay or context.g_gameVersion or "unavailable")
    }
    local function collect(name, callback)
        local ok, failure = pcall(callback, snapshot, context)
        if not ok then
            if snapshot[name] ~= nil then
                snapshot[name].status = "partial"
            end
            issue(snapshot, "SECTION_ERROR", name .. ": " .. tostring(failure))
        end
    end
    collect("farm", readFarm)
    collect("capturedAt", readDate)
    collect("land", readLand)
    collect("equipment", readEquipment)
    collect("buildings", BankPropertyDataSource.collect)
    collect("animals", BankAnimalDataSource.collect)
    collect("inventory", BankInventoryDataSource.collect)
    collect("finance", BankFinanceDataSource.collect)
    return snapshot
end
