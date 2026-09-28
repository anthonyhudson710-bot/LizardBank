-- Quantity-only inventory boundary. Never assigns monetary values or retains
-- game objects. Verified adapters and explicit gaps: docs/inventory-sources.md.
BankInventoryDataSource = {}

-- Opt-in evidence only. No extra game accessors or live references in events.
local function diagnosticScalar(value)
    if type(value) == "string" or type(value) == "boolean" then return value end
    if type(value) == "number" and value == value and math.abs(value) < math.huge then return value end
    return nil
end

local function diagnosticRead(name, ok, value, reason)
    if BankDiagnostics ~= nil and BankDiagnostics.isEnabled() then
        BankDiagnostics.read("inventory", name, ok, value, {reason = reason})
    end
end

local function diagnosticField(object, name)
    local value = object[name]
    diagnosticRead(name, true, value, "raw_field")
    return value
end

local function diagnosticDecision(checkId, outcome, id, value, reason, expected)
    if BankDiagnostics ~= nil and BankDiagnostics.isEnabled() then
        BankDiagnostics.check(checkId, outcome, {section = "inventory", id = diagnosticScalar(id),
            value = diagnosticScalar(value), valueType = type(value), reason = reason,
            expected = diagnosticScalar(expected)})
    end
end

local function diagnosticBoundary(stage, name, ok, status, detail)
    if BankDiagnostics ~= nil and BankDiagnostics.isEnabled() then
        BankDiagnostics.emit("collector." .. stage, {section = "inventory", name = name,
            ok = ok, status = status, detail = diagnosticScalar(detail)})
    end
end

local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function scalar(value)
    return (type(value) == "string" and value ~= "") or finite(value)
end

local function issue(snapshot, code, detail)
    snapshot.issues[#snapshot.issues + 1] = {code = code, detail = tostring(detail)}
    diagnosticBoundary("issue", code, false, "reported", detail)
end

local function call(snapshot, object, method, ...)
    if type(object) ~= "table" or type(object[method]) ~= "function" then
        diagnosticRead(method, false, nil, "missing_accessor")
        return nil
    end
    local ok, value = pcall(object[method], object, ...)
    diagnosticRead(method, ok, value, ok and "accessor_return" or "accessor_error")
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
    diagnosticBoundary("recordEnter", category, true)
    local ok, failure = pcall(callback)
    diagnosticBoundary(ok and "recordExit" or "recordError", category, ok, nil, failure)
    if not ok then
        unknown(snapshot, category, "INVENTORY_RECORD_ERROR", failure)
    end
end

local function objectId(object, fallback)
    if scalar(object.uniqueId) then
        local id = tostring(object.uniqueId)
        diagnosticRead("uniqueId", true, id, "selected_raw_identifier")
        return id
    end
    if scalar(object.id) then
        local id = tostring(object.id)
        diagnosticRead("id", true, id, "selected_raw_identifier")
        return id
    end
    return tostring(fallback)
end

local function nameOf(snapshot, object, fallback)
    local name = call(snapshot, object, "getName")
    if type(name) == "string" and name ~= "" then return name end
    if type(object.name) == "string" and object.name ~= "" then return object.name end
    return fallback
end

local function isRemoving(snapshot, object)
    return diagnosticField(object, "markedForDeletion") == true or diagnosticField(object, "isDeleting") == true or diagnosticField(object, "isDeleted") == true
        or call(snapshot, object, "getIsBeingDeleted") == true
end

local function rememberStorage(storage, seen, seenIds)
    if type(storage) ~= "table" then return end
    seen[storage] = true
    if scalar(storage.uniqueId) then seenIds["unique:" .. tostring(storage.uniqueId)] = true end
end

local function blockPlaceableStorage(placeable, seen, seenIds)
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
    diagnosticDecision("INVENTORY_QUANTITY", finite(item.quantity) and item.quantity >= 0 and "PASS" or "UNAVAILABLE",
        item.id, item.quantity, item.source)
    local section = snapshot.inventory
    -- Empty supported compartments are counted, not expanded into display rows.
    if item.quantity == 0 then
        diagnosticDecision("INVENTORY_ZERO", "PASS", item.id, 0, "Verified empty compartment; omitted only from display rows.")
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
    if seen[storage] then diagnosticDecision("STORAGE_DEDUP", "PASS", metadata.id, true, "Duplicate storage reference excluded."); return end
    seen[storage] = true
    -- A generic id field can be a local slot, not a globally unique ID.
    local persistentId = scalar(storage.uniqueId) and "unique:" .. tostring(storage.uniqueId) or nil
    if persistentId ~= nil and seenIds[persistentId] then
        diagnosticDecision("STORAGE_DEDUP", "PASS", persistentId, true, "Duplicate persistent storage ID excluded.")
        return
    end
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
    diagnosticDecision("STORAGE_OWNER", finite(owner) and "PASS" or "UNAVAILABLE", metadata.id, owner,
        metadata.kind == "production" and "Production placeable attribution." or "Individual storage attribution.", snapshot.farm.id)
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

local function collectPlaceables(snapshot, context, seenStorage, seenStorageIds)
    local mission = context.g_currentMission or {}
    local system = mission.placeableSystem
    local placeables = type(system) == "table" and system.placeables
    diagnosticRead("mission.placeableSystem.placeables", true, placeables, "raw_registry")
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
                    blockPlaceableStorage(placeable, seenStorage, seenStorageIds)
                end
            end
        end)
    end
    local seen = {}
    for key, placeable in pairs(placeables) do
        safely(snapshot, "production", function()
            if type(placeable) ~= "table" then error("Invalid inventory placeable record") end
            if seen[placeable] then diagnosticDecision("INVENTORY_PLACEABLE_DEDUP", "PASS", nil, true, "Duplicate reference excluded."); return end
            seen[placeable] = true
            if placeable.spec_silo == nil and placeable.spec_siloExtension == nil
                and placeable.spec_productionPoint == nil then return end
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
            diagnosticDecision("PRODUCTION_OWNER", finite(owner) and "PASS" or "UNAVAILABLE", id, owner,
                "Production source admitted only for exact owner match.", snapshot.farm.id)
            if placeable.spec_productionPoint ~= nil then
                if not finite(owner) then
                    unknown(snapshot, "production", "INVENTORY_OWNER_UNAVAILABLE", id .. ": placeable owner unavailable; production storage omitted.")
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
        end)
    end
end

local function collectRegisteredStorage(snapshot, context, seen, seenIds)
    local system = (context.g_currentMission or {}).storageSystem
    -- Registry layout is a guarded compatibility candidate. Documented
    -- placeable adapters remain usable when this registry is unavailable.
    local storages = type(system) == "table" and system.storages
    diagnosticRead("mission.storageSystem.storages", true, storages, "raw_registry_candidate")
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

-- Native handlers can expose the same physical bale through a fill unit.
-- Their exact proxy units are skipped; independent fuel/buffer/material stays.
local function prepareBaleProxies(snapshot, context, blockedRealObjects, blockedUniqueIds)
    local system = (context.g_currentMission or {}).vehicleSystem
    local vehicles = type(system) == "table" and (system.vehicles or system.vehicleByUniqueId)
    diagnosticRead("baleProxy.vehicleRegistry", true, vehicles, "selected_registry")
    local skipped, seen, chamberGap = {}, {}, false
    if type(vehicles) ~= "table" then return skipped end
    for _, vehicle in pairs(vehicles) do
        safely(snapshot, "bales", function()
            if type(vehicle) ~= "table" then return end
            if seen[vehicle] then diagnosticDecision("BALE_PROXY_DEDUP", "PASS", nil, true, "Duplicate vehicle reference excluded."); return end
            seen[vehicle] = true
            local units = {}
            local loader = vehicle.spec_baleLoader
            if type(loader) == "table" and finite(loader.fillUnitIndex) then
                units[loader.fillUnitIndex] = {kind = "baleCount"}
            end
            local blower = vehicle.spec_strawBlower
            if type(blower) == "table" and blower.currentBale ~= nil and finite(blower.fillUnitIndex) then
                units[blower.fillUnitIndex] = {kind = "baleProxy", bale = blower.currentBale}
            end
            local baler = vehicle.spec_baler
            if type(baler) == "table" and baler.hasUnloadingAnimation == true then
                local chamber, affectedFarm = false, false
                if type(baler.bales) == "table" then
                    for _, entry in pairs(baler.bales) do
                        if type(entry) == "table" and type(entry.baleObject) == "table" then
                            blockedRealObjects[entry.baleObject] = true
                            local unique = call(snapshot, entry.baleObject, "getUniqueId")
                            if not scalar(unique) then unique = entry.baleObject.uniqueId end
                            if scalar(unique) then blockedUniqueIds[tostring(unique)] = true end
                            local owner = call(snapshot, entry.baleObject, "getOwnerFarmId")
                            if owner == snapshot.farm.id or not finite(owner) then affectedFarm = true end
                            chamber = true
                        end
                    end
                end
                if finite(baler.lastBaleFillLevel) and baler.lastBaleFillLevel > 0 then chamber = true end
                if chamber and (affectedFarm or call(snapshot, vehicle, "getOwnerFarmId") == snapshot.farm.id) then
                    chamberGap = true
                    unknown(snapshot, "bales", "INVENTORY_BALE_CHAMBER_TRANSITION",
                        objectId(vehicle, "baler") .. ": bale chamber quantity is temporarily omitted; discharge the bale and Refresh.")
                end
                if chamber and finite(baler.fillUnitIndex) then
                    units[baler.fillUnitIndex] = {kind = "chamberTransition"}
                end
            end
            skipped[vehicle] = units
            if BankDiagnostics ~= nil and BankDiagnostics.isEnabled() then
                for unitIndex, unit in pairs(units) do
                    diagnosticDecision("BALE_PROXY_SOURCE", "PASS", nil, unitIndex, unit.kind)
                end
            end
        end)
    end
    return skipped, chamberGap
end

local function collectVehicles(snapshot, context, storedRealObjects, blockedUniqueIds, registeredBales, skippedBaleUnits)
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
            if seen[vehicle] or storedRealObjects[vehicle] then
                diagnosticDecision("INVENTORY_VEHICLE_DEDUP", "PASS", key, true, "Duplicate or stored counterpart reference excluded.")
                return
            end
            seen[vehicle] = true
            local uniqueId = scalar(vehicle.uniqueId) and tostring(vehicle.uniqueId) or nil
            if uniqueId ~= nil and blockedUniqueIds[uniqueId] then
                diagnosticDecision("INVENTORY_VEHICLE_DEDUP", "PASS", uniqueId, true, "Stored/transition counterpart ID excluded."); return
            end
            if uniqueId ~= nil and seenIds[uniqueId] then
                diagnosticDecision("INVENTORY_VEHICLE_DEDUP", "PASS", uniqueId, true, "Duplicate persistent ID excluded."); return
            end
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
            diagnosticDecision("INVENTORY_VEHICLE_OWNER", finite(owner) and "PASS" or "UNAVAILABLE", id, owner,
                owner == snapshot.farm.id and "Exact owner match." or "Excluded: owner mismatch or unavailable.", snapshot.farm.id)
            if not finite(owner) then
                unknown(snapshot, "vehicle", "INVENTORY_OWNER_UNAVAILABLE", id .. ": owner unavailable; contents omitted.")
                return
            end
            if owner ~= snapshot.farm.id then return end
            local state = call(snapshot, vehicle, "getPropertyState")
            diagnosticRead("vehicle.propertyState decision", true, state, "existing_getter_result")
            local ownership
            if states.OWNED ~= nil and state == states.OWNED then ownership = "owned"
            elseif states.LEASED ~= nil and state == states.LEASED then ownership = "leased"
            elseif states.MISSION ~= nil and state == states.MISSION then
                diagnosticDecision("INVENTORY_VEHICLE_EXCLUSION", "PASS", id, state, "Borrowed equipment cargo excluded.")
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
                    local skipped = skippedBaleUnits[vehicle] and skippedBaleUnits[vehicle][index]
                    if skipped ~= nil then
                        diagnosticDecision("INVENTORY_PROXY_EXCLUSION", "PASS", id, index, skipped.kind)
                        section.excludedCount = section.excludedCount + 1
                        if skipped.kind == "baleProxy" and not registeredBales[skipped.bale] then
                            unknown(snapshot, "vehicle", "INVENTORY_BALE_PROXY_UNAVAILABLE",
                                id .. ": bale-handler quantity is omitted because its physical bale is absent from the item registry.")
                        end
                        return
                    end
                    -- TreePlanter's getter proxies a separately registered pallet.
                    local treePlanter = vehicle.spec_treePlanter
                    if type(treePlanter) == "table" and treePlanter.mountedSaplingPallet ~= nil and treePlanter.fillUnitIndex == index then
                        diagnosticDecision("INVENTORY_PROXY_EXCLUSION", "PASS", id, index, "Mounted sapling pallet counted separately.")
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
    diagnosticBoundary("enter", "collect", true)
    context = context or {}
    snapshot.issues = snapshot.issues or {}
    snapshot.capabilities = snapshot.capabilities or {}
    snapshot.inventory = {items = {}, status = "unavailable", sourceCount = 0, unknownCount = 0,
        excludedCount = 0, zeroCount = 0, coverage = {storage = "unavailable", production = "unavailable",
            vehicle = "unavailable", objectStorage = "unavailable", bales = "unavailable"}}
    if type(snapshot.farm) ~= "table" or not finite(snapshot.farm.id) or snapshot.farm.id <= 0 then
        issue(snapshot, "INVENTORY_FARM_UNAVAILABLE", "Inventory cannot be attributed without an active farm.")
        diagnosticBoundary("exit", "collect", true, snapshot.inventory.status)
        return snapshot.inventory
    end
    local seenStorage, seenStorageIds, storedRealObjects = {}, {}, {}
    local blockedUniqueIds, registeredBales = {}, {}
    local skippedBaleUnits, chamberGap = prepareBaleProxies(snapshot, context, storedRealObjects, blockedUniqueIds)
    local ok, failure = pcall(BankStoredObjectDataSource.collect, snapshot, context,
        {addQuantity = addQuantity, unknown = unknown, call = call, issue = issue, isRemoving = isRemoving,
            blockedUniqueIds = blockedUniqueIds, registeredBales = registeredBales}, storedRealObjects)
    diagnosticBoundary(ok and "exit" or "error", "storedObjects", ok, nil, failure)
    if not ok then
        unknown(snapshot, "bales", "INVENTORY_STORED_OBJECT_ERROR", failure)
        snapshot.inventory.coverage.objectStorage = "partial"
    end
    if chamberGap and snapshot.inventory.coverage.bales ~= "unavailable" then
        snapshot.inventory.coverage.bales = "partial"
    end
    collectPlaceables(snapshot, context, seenStorage, seenStorageIds)
    collectRegisteredStorage(snapshot, context, seenStorage, seenStorageIds)
    collectVehicles(snapshot, context, storedRealObjects, blockedUniqueIds, registeredBales, skippedBaleUnits)
    for _, category in ipairs({"storage", "production", "vehicle", "bales", "objectStorage"}) do
        if snapshot.inventory.coverage[category] ~= "unavailable" then
            -- Ground heaps and unsupported stock still prevent full coverage.
            snapshot.inventory.status = "partial"
        end
    end
    table.sort(snapshot.inventory.items, function(a, b)
        if a.location ~= b.location then return a.location < b.location end
        if a.id ~= b.id then return a.id < b.id end
        return tostring(a.fillTypeIndex) < tostring(b.fillTypeIndex)
    end)
    diagnosticBoundary("exit", "collect", true, snapshot.inventory.status)
    return snapshot.inventory
end
