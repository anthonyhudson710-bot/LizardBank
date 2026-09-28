-- Quantity-only inventory boundary. Never assigns monetary values or retains
-- game objects. Verified adapters and explicit gaps: docs/inventory-sources.md.
BankInventoryDataSource = {}

local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function scalar(value)
    return (type(value) == "string" and value ~= "") or finite(value)
end

local function issue(snapshot, code, detail)
    snapshot.issues[#snapshot.issues + 1] = {code = code, detail = tostring(detail)}
end

local function call(snapshot, object, method, ...)
    if type(object) ~= "table" or type(object[method]) ~= "function" then return nil end
    local ok, value = pcall(object[method], object, ...)
    if ok then return value end
    issue(snapshot, "INVENTORY_ACCESSOR_ERROR", method .. ": " .. tostring(value))
    return nil
end

local function unknown(snapshot, category, code, detail)
    local section = snapshot.inventory
    section.unknownCount = section.unknownCount + 1
    section.coverage[category] = "partial"
    issue(snapshot, code, detail)
end

local function safely(snapshot, category, callback)
    local ok, failure = pcall(callback)
    if not ok then
        unknown(snapshot, category, "INVENTORY_RECORD_ERROR", failure)
    end
end

local function objectId(object, fallback)
    if scalar(object.uniqueId) then return tostring(object.uniqueId) end
    if scalar(object.id) then return tostring(object.id) end
    return tostring(fallback)
end

local function nameOf(snapshot, object, fallback)
    local name = call(snapshot, object, "getName")
    if type(name) == "string" and name ~= "" then return name end
    if type(object.name) == "string" and object.name ~= "" then return object.name end
    return fallback
end

local function isRemoving(snapshot, object)
    return object.markedForDeletion == true or object.isDeleting == true or object.isDeleted == true
        or call(snapshot, object, "getIsBeingDeleted") == true
end

local function rememberStorage(storage, seen, seenIds)
    if type(storage) ~= "table" then return end
    seen[storage] = true
    if scalar(storage.uniqueId) then seenIds["unique:" .. tostring(storage.uniqueId)] = true end
end

local function blockPlaceableStorage(snapshot, placeable, seen, seenIds, storedRealObjects)
    local silo = placeable.spec_silo
    if type(silo) == "table" and type(silo.storages) == "table" then
        for _, storage in pairs(silo.storages) do rememberStorage(storage, seen, seenIds) end
    end
    local extension = placeable.spec_siloExtension
    if type(extension) == "table" then rememberStorage(extension.storage, seen, seenIds) end
    local production = placeable.spec_productionPoint
    if type(production) == "table" and type(production.productionPoint) == "table" then
        rememberStorage(production.productionPoint.storage, seen, seenIds)
    end
    local objectStorage = placeable.spec_objectStorage
    if type(objectStorage) == "table" and type(objectStorage.storedObjects) == "table" then
        for _, abstractObject in pairs(objectStorage.storedObjects) do
            local real = call(snapshot, abstractObject, "getRealObject")
            if type(real) == "table" then storedRealObjects[real] = true end
        end
    end
end

local function fillName(snapshot, context, item)
    if not finite(item.fillTypeIndex) or item.fillTypeIndex <= 0
        or item.fillTypeIndex ~= math.floor(item.fillTypeIndex)
        or item.fillTypeIndex == (context.FillType or {}).UNKNOWN then
        item.fillTypeIndex = nil
        item.fillTypeName = "Unknown fill type"
        return false
    end
    local descriptor = call(snapshot, context.g_fillTypeManager, "getFillTypeByIndex", item.fillTypeIndex)
    if type(descriptor) == "table" then
        if type(descriptor.name) == "string" then item.fillTypeName = descriptor.name end
        if type(descriptor.title) == "string" then item.fillTypeTitle = descriptor.title end
    end
    item.fillTypeName = item.fillTypeName or "Fill type " .. tostring(item.fillTypeIndex)
    return type(descriptor) == "table"
end

local function addQuantity(snapshot, context, category, item)
    local section = snapshot.inventory
    -- Empty supported compartments are counted, not expanded into display rows.
    if item.quantity == 0 then
        section.zeroCount = section.zeroCount + 1
        return
    end
    if not finite(item.quantity) or item.quantity < 0 then
        item.quantity = nil
        item.quantityStatus = "unavailable"
        unknown(snapshot, category, "INVENTORY_QUANTITY_UNAVAILABLE", item.id .. ": invalid or unavailable quantity.")
    else
        item.quantityStatus = "available"
    end
    if not fillName(snapshot, context, item) then
        unknown(snapshot, category, "INVENTORY_FILLTYPE_UNAVAILABLE", item.id .. ": fill type metadata is unavailable.")
    end
    -- Container attribution does not establish provenance: a farmer-owned
    -- trailer can contain contract crop.
    item.cargoOwnership = "unverified"
    item.includedInAssetQuote = "unknown"
    section.items[#section.items + 1] = item
end

local function collectStorage(snapshot, context, storage, metadata, seen, seenIds)
    if type(storage) ~= "table" then
        unknown(snapshot, metadata.kind, "INVENTORY_STORAGE_UNAVAILABLE", metadata.id .. ": storage object is unavailable.")
        return
    end
    if seen[storage] then return end
    seen[storage] = true
    -- A generic id field can be a local slot, not a globally unique ID.
    local persistentId = scalar(storage.uniqueId) and "unique:" .. tostring(storage.uniqueId) or nil
    if persistentId ~= nil and seenIds[persistentId] then return end
    if persistentId ~= nil then seenIds[persistentId] = true end
    if isRemoving(snapshot, storage) then
        snapshot.inventory.excludedCount = snapshot.inventory.excludedCount + 1
        snapshot.inventory.coverage[metadata.kind] = "partial"
        issue(snapshot, "INVENTORY_SOURCE_REMOVING", metadata.id .. ": storage is being removed; refresh after removal finishes.")
        return
    end

    local owner = call(snapshot, storage, "getOwnerFarmId")
    -- The dedicated production storage follows its owning production placeable.
    if metadata.kind == "production" then owner = metadata.owner end
    if not finite(owner) then
        unknown(snapshot, metadata.kind, "INVENTORY_OWNER_UNAVAILABLE", metadata.id .. ": storage owner unavailable; omitted.")
        return
    end
    if owner ~= snapshot.farm.id then return end
    local section = snapshot.inventory
    section.sourceCount = section.sourceCount + 1
    local levels = call(snapshot, storage, "getFillLevels")
    if type(levels) ~= "table" then
        unknown(snapshot, metadata.kind, "INVENTORY_STORAGE_UNAVAILABLE", metadata.id .. ": getFillLevels() is unavailable.")
        return
    end
    for fillType, quantity in pairs(levels) do
        safely(snapshot, metadata.kind, function()
            addQuantity(snapshot, context, metadata.kind, {
                id = metadata.id .. ":fill:" .. (scalar(fillType) and tostring(fillType) or "unknown"),
                location = metadata.location, kind = metadata.kind, fillTypeIndex = fillType,
                quantity = quantity, unit = "l", ownership = "owned",
                source = metadata.source .. ":getFillLevels()"
            })
        end)
    end
end

local function collectPlaceables(snapshot, context, seenStorage, seenStorageIds, storedRealObjects)
    local mission = context.g_currentMission or {}
    local system = mission.placeableSystem
    local placeables = type(system) == "table" and system.placeables
    snapshot.capabilities.inventoryPlaceables = type(placeables) == "table"
    if type(placeables) ~= "table" then
        unknown(snapshot, "production", "INVENTORY_PLACEABLES_UNAVAILABLE", "Production and object storage enumeration is unavailable.")
        snapshot.inventory.coverage.production = "unavailable"
        snapshot.inventory.coverage.storage = "partial"
        return
    end
    snapshot.inventory.coverage.production = "available"
    snapshot.inventory.coverage.storage = "available"
    -- Block removed owners' stores before collecting any live records. A
    -- storage may still be registered (or aliased by another adapter) mid-sale.
    local removing = {}
    for _, placeable in pairs(placeables) do
        safely(snapshot, "storage", function()
            if type(placeable) == "table" and removing[placeable] == nil then
                removing[placeable] = isRemoving(snapshot, placeable)
                if removing[placeable] then
                    blockPlaceableStorage(snapshot, placeable, seenStorage, seenStorageIds, storedRealObjects)
                end
            end
        end)
    end
    local seen = {}
    for key, placeable in pairs(placeables) do
        safely(snapshot, "production", function()
            if type(placeable) ~= "table" then error("Invalid inventory placeable record") end
            if seen[placeable] then return end
            seen[placeable] = true
            local id = "placeable:" .. objectId(placeable, key)
            if removing[placeable] then
                snapshot.inventory.excludedCount = snapshot.inventory.excludedCount + 1
                snapshot.inventory.coverage.storage = "partial"
                snapshot.inventory.coverage.production = "partial"
                issue(snapshot, "INVENTORY_SOURCE_REMOVING", id .. ": placeable is being removed; refresh after removal finishes.")
                return
            end
            local location = nameOf(snapshot, placeable, id)
            -- Per-farm silo contents can belong to a farm that does not own the
            -- building. Check the individual Storage owner, never land access.
            if type(placeable.spec_silo) == "table" then
                local storages = placeable.spec_silo.storages
                if type(storages) ~= "table" then
                    unknown(snapshot, "storage", "INVENTORY_STORAGE_UNAVAILABLE", id .. ": silo storage list unavailable.")
                else
                    for index, storage in pairs(storages) do
                        safely(snapshot, "storage", function()
                            collectStorage(snapshot, context, storage, {id = id .. ":storage:" .. tostring(index),
                                location = location, kind = "storage", source = "spec_silo.storages"}, seenStorage, seenStorageIds)
                        end)
                    end
                end
            end
            if type(placeable.spec_siloExtension) == "table" then
                collectStorage(snapshot, context, placeable.spec_siloExtension.storage,
                    {id = id .. ":extension", location = location, kind = "storage", source = "spec_siloExtension.storage"},
                    seenStorage, seenStorageIds)
            end
            local owner = call(snapshot, placeable, "getOwnerFarmId")
            -- Skip real display objects from any virtual store; only the owned
            -- store receives a user-facing omission finding below.
            if type(placeable.spec_objectStorage) == "table" then
                local objects = placeable.spec_objectStorage.storedObjects
                if type(objects) == "table" then
                    for _, abstractObject in pairs(objects) do
                        local real = call(snapshot, abstractObject, "getRealObject")
                        if type(real) == "table" then storedRealObjects[real] = true end
                    end
                end
            end
            if placeable.spec_productionPoint ~= nil or placeable.spec_objectStorage ~= nil then
                if not finite(owner) then
                    unknown(snapshot, "production", "INVENTORY_OWNER_UNAVAILABLE", id .. ": placeable owner unavailable; production/object storage omitted.")
                    return
                end
            end
            if owner ~= snapshot.farm.id then return end
            if type(placeable.spec_productionPoint) == "table" then
                local spec = placeable.spec_productionPoint
                if spec.isFinalized == false then
                    snapshot.inventory.excludedCount = snapshot.inventory.excludedCount + 1
                    issue(snapshot, "INVENTORY_UNFINISHED_PRODUCTION", id .. ": unfinished production excluded.")
                else
                    local point = spec.productionPoint
                    collectStorage(snapshot, context, type(point) == "table" and point.storage or nil,
                        {id = id .. ":production", location = location, kind = "production", owner = owner,
                            source = "spec_productionPoint.productionPoint.storage"}, seenStorage, seenStorageIds)
                end
            end
            if type(placeable.spec_objectStorage) == "table" then
                snapshot.inventory.excludedCount = snapshot.inventory.excludedCount + 1
                issue(snapshot, "INVENTORY_OBJECT_STORAGE_EXCLUDED", id .. ": stored bales and pallets are outside this build's quantity coverage.")
            end
        end)
    end
end

local function collectRegisteredStorage(snapshot, context, seen, seenIds)
    local system = (context.g_currentMission or {}).storageSystem
    -- Registry layout is a guarded compatibility candidate. Documented
    -- placeable adapters remain usable when this registry is unavailable.
    local storages = type(system) == "table" and system.storages
    snapshot.capabilities.inventoryStorageRegistry = type(storages) == "table"
    snapshot.capabilities.inventoryStorageRegistrySource = "mission.storageSystem.storages [compatibility candidate]"
    if type(storages) ~= "table" then
        issue(snapshot, "INVENTORY_STORAGE_REGISTRY_UNAVAILABLE", "Only directly enumerated silo, extension and production storage could be checked.")
        if snapshot.inventory.coverage.storage == "available" then snapshot.inventory.coverage.storage = "partial" end
        if not snapshot.capabilities.inventoryPlaceables then snapshot.inventory.coverage.storage = "unavailable" end
        return
    end
    if snapshot.inventory.coverage.storage == "unavailable" then snapshot.inventory.coverage.storage = "available" end
    for key, value in pairs(storages) do
        safely(snapshot, "storage", function()
            local storage = type(value) == "table" and value or (type(key) == "table" and key)
            if type(storage) ~= "table" then error("Invalid storage registry entry") end
            local fallback = scalar(key) and key or tostring(storage)
            local id = "storage:" .. objectId(storage, fallback)
            collectStorage(snapshot, context, storage, {id = id, location = nameOf(snapshot, storage, id),
                kind = "storage", source = "mission.storageSystem.storages"}, seen, seenIds)
        end)
    end
end

local function collectVehicles(snapshot, context, storedRealObjects)
    local section = snapshot.inventory
    local system = (context.g_currentMission or {}).vehicleSystem
    local vehicles = type(system) == "table" and system.vehicles
    if type(vehicles) ~= "table" and type(system) == "table" then vehicles = system.vehicleByUniqueId end
    snapshot.capabilities.inventoryVehicles = type(vehicles) == "table"
    if type(vehicles) ~= "table" then
        unknown(snapshot, "vehicle", "INVENTORY_VEHICLES_UNAVAILABLE", "Vehicle and pallet enumeration is unavailable.")
        section.coverage.vehicle = "unavailable"
        return
    end
    section.coverage.vehicle = "available"
    local seen, seenIds = {}, {}
    local registered = {}
    for _, vehicle in pairs(vehicles) do
        if type(vehicle) == "table" then registered[vehicle] = true end
    end
    local states = context.VehiclePropertyState or {}
    for key, vehicle in pairs(vehicles) do
        safely(snapshot, "vehicle", function()
            if type(vehicle) ~= "table" then error("Invalid vehicle inventory record") end
            if seen[vehicle] or storedRealObjects[vehicle] then return end
            seen[vehicle] = true
            local uniqueId = scalar(vehicle.uniqueId) and tostring(vehicle.uniqueId) or nil
            if uniqueId ~= nil and seenIds[uniqueId] then return end
            if uniqueId ~= nil then seenIds[uniqueId] = true end
            if type(vehicle.getFillUnits) ~= "function" and vehicle.spec_fillUnit == nil then return end
            local id = "vehicle:" .. objectId(vehicle, key)
            if isRemoving(snapshot, vehicle) then
                section.excludedCount = section.excludedCount + 1
                section.coverage.vehicle = "partial"
                issue(snapshot, "INVENTORY_SOURCE_REMOVING", id .. ": vehicle is being removed; refresh after removal finishes.")
                return
            end
            local owner = call(snapshot, vehicle, "getOwnerFarmId")
            if not finite(owner) then
                unknown(snapshot, "vehicle", "INVENTORY_OWNER_UNAVAILABLE", id .. ": owner unavailable; contents omitted.")
                return
            end
            if owner ~= snapshot.farm.id then return end
            local state = call(snapshot, vehicle, "getPropertyState")
            local ownership
            if states.OWNED ~= nil and state == states.OWNED then ownership = "owned"
            elseif states.LEASED ~= nil and state == states.LEASED then ownership = "leased"
            elseif states.MISSION ~= nil and state == states.MISSION then
                section.excludedCount = section.excludedCount + 1
                return
            else
                unknown(snapshot, "vehicle", "INVENTORY_PROPERTY_UNAVAILABLE", id .. ": property state unavailable; contents omitted.")
                return
            end
            section.sourceCount = section.sourceCount + 1
            local units = call(snapshot, vehicle, "getFillUnits")
            if type(units) ~= "table" then
                unknown(snapshot, "vehicle", "INVENTORY_FILLUNITS_UNAVAILABLE", id .. ": fill units unavailable.")
                return
            end
            local location = nameOf(snapshot, vehicle, id)
            local kind = (vehicle.isPallet == true or vehicle.spec_pallet ~= nil or vehicle.spec_bigBag ~= nil) and "pallet" or "vehicle"
            for index, unit in pairs(units) do
                safely(snapshot, "vehicle", function()
                    if type(unit) ~= "table" or not finite(index) or index < 1 or index ~= math.floor(index) then error(id .. ": invalid fill unit") end
                    -- TreePlanter's getter proxies a separately registered pallet.
                    local treePlanter = vehicle.spec_treePlanter
                    if type(treePlanter) == "table" and treePlanter.mountedSaplingPallet ~= nil and treePlanter.fillUnitIndex == index then
                        section.excludedCount = section.excludedCount + 1
                        if not registered[treePlanter.mountedSaplingPallet] then
                            unknown(snapshot, "vehicle", "INVENTORY_MOUNTED_PALLET_UNAVAILABLE",
                                id .. ": mounted pallet is absent from the vehicle registry; proxy quantity omitted.")
                        end
                        return
                    end
                    local quantity = call(snapshot, vehicle, "getFillUnitFillLevel", index)
                    local fillType = call(snapshot, vehicle, "getFillUnitFillType", index)
                    local unitText = type(unit.unitText) == "string" and unit.unitText or nil
                    addQuantity(snapshot, context, "vehicle", {id = id .. ":fillUnit:" .. tostring(index),
                        location = location, kind = kind, fillTypeIndex = fillType, quantity = quantity,
                        unit = unitText ~= nil and "units" or "l", unitText = unitText, ownership = ownership,
                        source = "vehicle:getFillUnitFillLevel(" .. tostring(index) .. ")"})
                end)
            end
        end)
    end
end

function BankInventoryDataSource.collect(snapshot, context)
    context = context or {}
    snapshot.issues = snapshot.issues or {}
    snapshot.capabilities = snapshot.capabilities or {}
    snapshot.inventory = {items = {}, status = "unavailable", sourceCount = 0, unknownCount = 0,
        excludedCount = 0, zeroCount = 0, coverage = {storage = "unavailable", production = "unavailable",
            vehicle = "unavailable", objectStorage = "excluded", bales = "excluded"}}
    if type(snapshot.farm) ~= "table" or not finite(snapshot.farm.id) or snapshot.farm.id <= 0 then
        issue(snapshot, "INVENTORY_FARM_UNAVAILABLE", "Inventory cannot be attributed without an active farm.")
        return snapshot.inventory
    end
    local seenStorage, seenStorageIds, storedRealObjects = {}, {}, {}
    collectPlaceables(snapshot, context, seenStorage, seenStorageIds, storedRealObjects)
    collectRegisteredStorage(snapshot, context, seenStorage, seenStorageIds)
    collectVehicles(snapshot, context, storedRealObjects)
    for _, category in ipairs({"storage", "production", "vehicle"}) do
        if snapshot.inventory.coverage[category] ~= "unavailable" then
            -- Always partial overall: bales and virtual storage are not covered.
            snapshot.inventory.status = "partial"
        end
    end
    table.sort(snapshot.inventory.items, function(a, b)
        if a.location ~= b.location then return a.location < b.location end
        if a.id ~= b.id then return a.id < b.id end
        return tostring(a.fillTypeIndex) < tostring(b.fillTypeIndex)
    end)
    return snapshot.inventory
end
