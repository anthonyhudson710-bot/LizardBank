-- Native real bales and object-storage counterparts. No prices or predictions.
-- Missing virtual quantity APIs remain explicit gaps, never inferred fields.
BankStoredObjectDataSource = {}

local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function scalar(value)
    return (type(value) == "string" and value ~= "") or finite(value)
end

local function uniqueId(snapshot, object, helpers)
    local id = helpers.call(snapshot, object, "getUniqueId")
    if not scalar(id) then id = object.uniqueId end
    return scalar(id) and tostring(id) or nil
end

local function safe(snapshot, category, helpers, callback)
    local ok, failure = pcall(callback)
    if not ok then helpers.unknown(snapshot, category, "INVENTORY_STORED_OBJECT_ERROR", tostring(failure)) end
end

local function removed(snapshot, object, helpers)
    if type(helpers.isRemoving) == "function" then return helpers.isRemoving(snapshot, object) end
    return object.markedForDeletion == true or object.isDeleting == true or object.isDeleted == true
        or helpers.call(snapshot, object, "getIsBeingDeleted") == true
end

local function isBale(snapshot, context, object, helpers)
    if context.Bale == nil or type(object.isa) ~= "function" then return nil end
    return helpers.call(snapshot, object, "isa", context.Bale)
end

local function omitRemoving(snapshot, category, id, helpers)
    snapshot.inventory.excludedCount = snapshot.inventory.excludedCount + 1
    snapshot.inventory.coverage[category] = "partial"
    helpers.issue(snapshot, "INVENTORY_SOURCE_REMOVING", id .. ": stored object is being removed; refresh after removal finishes.")
end

local function rememberReal(snapshot, object, helpers, blocked, blockedIds)
    if type(object) ~= "table" then return end
    blocked[object] = true
    local id = uniqueId(snapshot, object, helpers)
    if id ~= nil then blockedIds[id] = true end
end

local function fermentation(snapshot, bale, item, category, helpers)
    local fermenting = helpers.call(snapshot, bale, "getIsFermenting")
    if type(fermenting) ~= "boolean" then return end
    item.isFermenting = fermenting
    if fermenting then
        local progress = helpers.call(snapshot, bale, "getFermentingPercentage")
        if finite(progress) and progress >= 0 and progress <= 1 then
            item.fermentationProgress = progress
        else
            helpers.unknown(snapshot, category, "INVENTORY_FERMENTATION_UNAVAILABLE", item.id .. ": fermentation progress is unavailable.")
        end
    end
end

local function owned(snapshot, object, category, id, helpers)
    local owner = helpers.call(snapshot, object, "getOwnerFarmId")
    if not finite(owner) then
        helpers.unknown(snapshot, category, "INVENTORY_OWNER_UNAVAILABLE", id .. ": object owner is unavailable; quantity omitted.")
        return false
    end
    return owner == snapshot.farm.id
end

local function collectBale(snapshot, context, bale, item, category, helpers)
    if removed(snapshot, bale, helpers) then omitRemoving(snapshot, category, item.id, helpers); return end
    if not owned(snapshot, bale, category, item.id, helpers) then return end
    if bale.isMissionBale == true then
        snapshot.inventory.excludedCount = snapshot.inventory.excludedCount + 1
        helpers.issue(snapshot, "INVENTORY_MISSION_BALE_EXCLUDED", item.id .. ": contract bale omitted from farm holdings.")
        return
    end
    snapshot.inventory.sourceCount = snapshot.inventory.sourceCount + 1
    item.quantity = helpers.call(snapshot, bale, "getFillLevel")
    item.fillTypeIndex = helpers.call(snapshot, bale, "getFillType")
    item.unit, item.ownership = "l", "owned"
    fermentation(snapshot, bale, item, category, helpers)
    helpers.addQuantity(snapshot, context, category, item)
end

local function collectPallet(snapshot, context, pallet, id, location, objectName, helpers)
    if removed(snapshot, pallet, helpers) then omitRemoving(snapshot, "objectStorage", id, helpers); return end
    if not owned(snapshot, pallet, "objectStorage", id, helpers) then return end
    local state = helpers.call(snapshot, pallet, "getPropertyState")
    local states = context.VehiclePropertyState or {}
    if states.MISSION ~= nil and state == states.MISSION then
        snapshot.inventory.excludedCount = snapshot.inventory.excludedCount + 1
        helpers.issue(snapshot, "INVENTORY_MISSION_PALLET_EXCLUDED", id .. ": borrowed pallet omitted.")
        return
    end
    if states.OWNED == nil or state ~= states.OWNED then
        helpers.unknown(snapshot, "objectStorage", "INVENTORY_PROPERTY_UNAVAILABLE", id .. ": stored pallet property state is unavailable; quantity omitted.")
        return
    end
    snapshot.inventory.sourceCount = snapshot.inventory.sourceCount + 1
    local units = helpers.call(snapshot, pallet, "getFillUnits")
    if type(units) ~= "table" then
        helpers.unknown(snapshot, "objectStorage", "INVENTORY_FILLUNITS_UNAVAILABLE", id .. ": stored pallet fill units are unavailable.")
        return
    end
    local countedObject = false
    for index, unit in pairs(units) do
        safe(snapshot, "objectStorage", helpers, function()
            if type(unit) ~= "table" or not finite(index) or index < 1 or index ~= math.floor(index) then
                error(id .. ": invalid stored pallet fill unit")
            end
            local unitText = type(unit.unitText) == "string" and unit.unitText or nil
            local quantity = helpers.call(snapshot, pallet, "getFillUnitFillLevel", index)
            local objectCount
            if not countedObject and quantity ~= 0 then objectCount, countedObject = 1, true end
            helpers.addQuantity(snapshot, context, "objectStorage", {
                id = id .. ":fillUnit:" .. tostring(index), location = location, kind = "storedPallet", ownership = "owned",
                quantity = quantity, objectName = objectName, objectCount = objectCount,
                fillTypeIndex = helpers.call(snapshot, pallet, "getFillUnitFillType", index),
                unit = unitText ~= nil and "units" or "l", unitText = unitText,
                source = "spec_objectStorage.storedObjects:getRealObject():getFillUnitFillLevel(" .. tostring(index) .. ")"
            })
        end)
    end
end

local function recordUnsupported(snapshot, context, object, id, location, helpers)
    snapshot.inventory.sourceCount = snapshot.inventory.sourceCount + 1
    local className = type(object.REFERENCE_CLASS_NAME) == "string" and object.REFERENCE_CLASS_NAME or nil
    local kind = className == "Bale" and "storedBale"
        or ((className == "Vehicle" or className == "Pallet") and "storedPallet" or "objectStorage")
    helpers.issue(snapshot, "INVENTORY_VIRTUAL_QUANTITY_UNAVAILABLE",
        id .. ": abstract " .. tostring(className or "object") .. " has no readable real counterpart; virtual quantity and ownership APIs are unverified.")
    helpers.addQuantity(snapshot, context, "objectStorage", {
        id = id, location = location, kind = kind, ownership = "unknown", unit = "units",
        objectClass = className, objectCount = 1,
        objectName = (function()
            local text = helpers.call(snapshot, object, "getDialogText")
            return type(text) == "string" and text or nil
        end)(),
        source = "spec_objectStorage.storedObjects (quantity interface unavailable)"
    })
end

local function sampleAbstract(snapshot, object, sampleIndex)
    if sampleIndex > 3 then return end
    local fields = {}
    for key, value in pairs(object) do
        if type(key) == "string" then
            fields[#fields + 1] = key:sub(1, 60) .. ":" .. type(value)
        end
    end
    table.sort(fields)
    local sample = {}
    for index = 1, math.min(12, #fields) do sample[index] = fields[index] end
    snapshot.capabilities["inventoryAbstractObjectSample" .. tostring(sampleIndex)] = table.concat(sample, ", ")
end

local function collectStored(snapshot, context, helpers, blocked, blockedIds)
    local mission = context.g_currentMission or {}
    local system = mission.placeableSystem
    local placeables = type(system) == "table" and system.placeables
    if type(placeables) ~= "table" and type(system) == "table" then placeables = system.placableByUniqueId end
    snapshot.capabilities.inventoryObjectStorageEnumeration = type(placeables) == "table"
    if type(placeables) ~= "table" then
        helpers.unknown(snapshot, "objectStorage", "INVENTORY_OBJECT_STORAGE_UNAVAILABLE", "Placeable enumeration is unavailable for object storage.")
        snapshot.inventory.coverage.objectStorage = "unavailable"
        return
    end
    snapshot.inventory.coverage.objectStorage = "available"
    local seenPlaceables, seenObjects, seenReal, seenRealIds = {}, {}, {}, {}
    local sampled = 0
    for placeableKey, placeable in pairs(placeables) do
        safe(snapshot, "objectStorage", helpers, function()
            if type(placeable) ~= "table" then error("Invalid object-storage placeable record") end
            if seenPlaceables[placeable] then return end
            seenPlaceables[placeable] = true
            local spec = placeable.spec_objectStorage
            if spec == nil then return end
            if type(spec) ~= "table" then error("Invalid object-storage specialization") end
            local parentId = "objectStorage:" .. (uniqueId(snapshot, placeable, helpers) or tostring(placeableKey))
            local owner = helpers.call(snapshot, placeable, "getOwnerFarmId")
            local deleting = removed(snapshot, placeable, helpers)
            local objects = spec.storedObjects
            if type(objects) ~= "table" then
                if owner == snapshot.farm.id or not finite(owner) then
                    helpers.unknown(snapshot, "objectStorage", "INVENTORY_OBJECT_STORAGE_UNAVAILABLE", parentId .. ": stored-object enumeration is unavailable.")
                end
                return
            end
            local name = helpers.call(snapshot, placeable, "getName")
            local location = type(name) == "string" and name or parentId
            if deleting then omitRemoving(snapshot, "objectStorage", parentId, helpers) end
            for objectKey, object in pairs(objects) do
                safe(snapshot, "objectStorage", helpers, function()
                    if type(object) ~= "table" then error(parentId .. ": invalid abstract object") end
                    local real = helpers.call(snapshot, object, "getRealObject")
                    -- Block counterparts before attribution or deletion checks.
                    -- A foreign/deleting virtual object is not loose farm stock.
                    if type(real) == "table" then rememberReal(snapshot, real, helpers, blocked, blockedIds) end
                    if seenObjects[object] then return end
                    seenObjects[object] = true
                    if sampled < 3 then
                        sampled = sampled + 1
                        sampleAbstract(snapshot, object, sampled)
                    end
                    if deleting then return end
                    local id = parentId .. ":object:" .. tostring(objectKey)
                    if removed(snapshot, object, helpers) then omitRemoving(snapshot, "objectStorage", id, helpers); return end
                    if type(real) ~= "table" then
                        if owner == snapshot.farm.id then
                            recordUnsupported(snapshot, context, object, id, location, helpers)
                        elseif not finite(owner) then
                            helpers.unknown(snapshot, "objectStorage", "INVENTORY_OWNER_UNAVAILABLE", id .. ": storage owner unavailable.")
                        end
                        return
                    end
                    local realId = uniqueId(snapshot, real, helpers)
                    if seenReal[real] or (realId ~= nil and seenRealIds[realId]) then return end
                    seenReal[real] = true
                    if realId ~= nil then seenRealIds[realId] = true end
                    local dialogText = helpers.call(snapshot, object, "getDialogText")
                    local objectName = type(dialogText) == "string" and dialogText or nil
                    local bale = isBale(snapshot, context, real, helpers)
                    if bale == true then
                        collectBale(snapshot, context, real, {id = id, location = location, kind = "storedBale",
                            objectName = objectName, objectCount = 1,
                            source = "spec_objectStorage.storedObjects:getRealObject():getFillLevel()"}, "objectStorage", helpers)
                    elseif real.isPallet == true or real.spec_pallet ~= nil or real.spec_bigBag ~= nil then
                        collectPallet(snapshot, context, real, id, location, objectName, helpers)
                    elseif owner == snapshot.farm.id then
                        recordUnsupported(snapshot, context, object, id, location, helpers)
                    end
                end)
            end
        end)
    end
end

local function collectLoose(snapshot, context, helpers, blocked, blockedIds)
    local mission = context.g_currentMission or {}
    local system = mission.itemSystem
    local entries = type(system) == "table" and system.items
    snapshot.capabilities.inventoryBaleEnumeration = type(entries) == "table"
    snapshot.capabilities.inventoryBaleEnumerationSource = "mission.itemSystem.items [compatibility candidate: raw item or item record]"
    snapshot.capabilities.inventoryBaleClass = context.Bale ~= nil
    if type(entries) ~= "table" or context.Bale == nil then
        helpers.unknown(snapshot, "bales", "INVENTORY_BALES_UNAVAILABLE", "Bale item registry or native Bale class is unavailable.")
        snapshot.inventory.coverage.bales = "unavailable"
        return
    end
    snapshot.inventory.coverage.bales = "available"
    local seen, seenIds = {}, {}
    for key, entry in pairs(entries) do
        safe(snapshot, "bales", helpers, function()
            if type(entry) ~= "table" then error("Invalid item registry record") end
            local object = type(entry.item) == "table" and entry.item or entry
            local isNativeBale = isBale(snapshot, context, object, helpers)
            if isNativeBale == false then return end
            if isNativeBale ~= true then
                helpers.unknown(snapshot, "bales", "INVENTORY_BALE_TYPE_UNAVAILABLE", "Item registry entry " .. tostring(key) .. " could not be classified.")
                return
            end
            if type(helpers.registeredBales) == "table" then helpers.registeredBales[object] = true end
            local nativeId = uniqueId(snapshot, object, helpers)
            if seen[object] or blocked[object] or (nativeId ~= nil and (seenIds[nativeId] or blockedIds[nativeId])) then return end
            seen[object] = true
            if nativeId ~= nil then seenIds[nativeId] = true end
            local id = "bale:" .. (nativeId or tostring(key))
            collectBale(snapshot, context, object, {id = id, location = id, kind = "bale", objectCount = 1,
                source = "mission.itemSystem.items:getFillLevel()"}, "bales", helpers)
        end)
    end
end

function BankStoredObjectDataSource.collect(snapshot, context, helpers, blockedRealObjects)
    blockedRealObjects = blockedRealObjects or {}
    local blockedIds = helpers.blockedUniqueIds or {}
    snapshot.inventory.coverage.objectStorage = "unavailable"
    snapshot.inventory.coverage.bales = "unavailable"
    if type(snapshot.farm) ~= "table" or not finite(snapshot.farm.id) or snapshot.farm.id <= 0 then
        helpers.issue(snapshot, "INVENTORY_FARM_UNAVAILABLE", "Stored objects cannot be attributed without an active farm.")
        return blockedRealObjects
    end
    -- Fixed traversal order prevents physical/virtual counterparts being counted
    -- twice. The supplied set survives an outer collector pcall.
    collectStored(snapshot, context, helpers, blockedRealObjects, blockedIds)
    collectLoose(snapshot, context, helpers, blockedRealObjects, blockedIds)
    return blockedRealObjects
end
