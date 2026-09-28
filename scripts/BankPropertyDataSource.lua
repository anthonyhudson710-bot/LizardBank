-- Registered placeable values, kept separate from contents and sale proceeds.
-- API evidence and accounting limits: docs/property-sources.md.
BankPropertyDataSource = {}

local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function identifier(value)
    return (type(value) == "string" and value ~= "") or finite(value)
end

local function issue(snapshot, code, detail)
    snapshot.issues[#snapshot.issues + 1] = {code = code, detail = tostring(detail)}
end

local function call(snapshot, object, name)
    if type(object[name]) ~= "function" then
        return nil
    end
    local ok, value = pcall(object[name], object)
    if not ok then
        snapshot.buildings.status = "partial"
        issue(snapshot, "PROPERTY_ACCESSOR_ERROR", name .. ": " .. tostring(value))
        return nil
    end
    return value
end

function BankPropertyDataSource.collect(snapshot, context)
    local section = {items = {}, ownedCount = 0, unknownValueCount = 0, excludedCount = 0, status = "unavailable"}
    snapshot.buildings = section
    local mission = context.g_currentMission
    local system = mission and mission.placeableSystem
    local capabilities = snapshot.capabilities
    capabilities.placeableSystem = type(system) == "table"
    capabilities.propertyMonetaryValueAvailableCount = 0
    capabilities.propertyMonetaryValueUnavailableCount = 0
    capabilities.propertySaleEligibilityAvailableCount = 0
    capabilities.propertySaleEligibilityUnavailableCount = 0
    capabilities.propertyDuplicateCount = 0
    local farmId = snapshot.farm and snapshot.farm.id
    if not finite(farmId) or farmId <= 0 or type(system) ~= "table" then
        issue(snapshot, "BUILDINGS_UNAVAILABLE", "Active farm or placeable system is unavailable.")
        return
    end

    local placeables = system.placeables
    capabilities.propertyEnumeration = "mission.placeableSystem.placeables"
    if type(placeables) ~= "table" then
        -- This spelling is used by GIANTS' PlaceableSystem:addPlaceable.
        placeables = system.placableByUniqueId
        capabilities.propertyEnumeration = "mission.placeableSystem.placableByUniqueId"
        if type(placeables) == "table" then
            issue(snapshot, "PROPERTY_ENUMERATION_FALLBACK", "Using the registered placeable lookup because the placeable list is unavailable.")
        end
    end
    if type(placeables) ~= "table" then
        issue(snapshot, "BUILDINGS_UNAVAILABLE", "Registered placeable enumeration is unavailable.")
        return
    end

    section.status = "available"
    local seenObjects, seenIds = {}, {}
    local valueSum, valueCount = 0, 0
    for _, placeable in pairs(placeables) do
        local ok, failure = pcall(function()
            if type(placeable) ~= "table" then
                error("Invalid registered placeable record")
            end
            if seenObjects[placeable] then
                capabilities.propertyDuplicateCount = capabilities.propertyDuplicateCount + 1
                return
            end
            seenObjects[placeable] = true
            local id = call(snapshot, placeable, "getUniqueId")
            if not identifier(id) then
                id = nil
            end
            local owner = call(snapshot, placeable, "getOwnerFarmId")
            if not finite(owner) then
                section.status = "partial"
                section.excludedCount = section.excludedCount + 1
                issue(snapshot, "PROPERTY_OWNER_UNAVAILABLE", "Placeable " .. tostring(id or "without ID") .. " omitted because its owner cannot be verified.")
                return
            end
            if owner ~= farmId then
                return
            end
            if placeable.markedForDeletion == true or placeable.isDeleting == true or placeable.isDeleted == true then
                section.status = "partial"
                section.excludedCount = section.excludedCount + 1
                issue(snapshot, "PROPERTY_REMOVING", "Placeable " .. tostring(id or "without ID") .. " is being removed; refresh when the operation finishes.")
                return
            end
            if id ~= nil then
                if seenIds[id] then
                    capabilities.propertyDuplicateCount = capabilities.propertyDuplicateCount + 1
                    return
                end
                seenIds[id] = true
            end

            -- No object reference, store item, or specialization table escapes.
            section.ownedCount = section.ownedCount + 1
            id = id or ("snapshot-property-" .. tostring(section.ownedCount))
            local name = call(snapshot, placeable, "getName")
            local item = {
                id = id,
                name = type(name) == "string" and name ~= "" and name or tostring(id),
                source = "placeable:getMonetaryValue() (engine monetary value; not a sale guarantee)",
                status = "unavailable"
            }
            section.items[#section.items + 1] = item

            local value = call(snapshot, placeable, "getMonetaryValue")
            if finite(value) and value >= 0 then
                item.value = value
                item.status = "available"
                valueSum, valueCount = valueSum + value, valueCount + 1
                capabilities.propertyMonetaryValueAvailableCount = capabilities.propertyMonetaryValueAvailableCount + 1
            else
                section.status = "partial"
                section.unknownValueCount = section.unknownValueCount + 1
                capabilities.propertyMonetaryValueUnavailableCount = capabilities.propertyMonetaryValueUnavailableCount + 1
                issue(snapshot, "PROPERTY_VALUE_UNAVAILABLE", "Placeable " .. tostring(id) .. " has no finite nonnegative monetary value.")
            end

            -- This is only the placeable's own veto check. Construction UI,
            -- ownership, map rules and specializations can impose other limits.
            local canBeSold = call(snapshot, placeable, "canBeSold")
            if type(canBeSold) == "boolean" then
                item.canBeSold = canBeSold
                capabilities.propertySaleEligibilityAvailableCount = capabilities.propertySaleEligibilityAvailableCount + 1
            else
                capabilities.propertySaleEligibilityUnavailableCount = capabilities.propertySaleEligibilityUnavailableCount + 1
            end
        end)
        if not ok then
            section.status = "partial"
            section.excludedCount = section.excludedCount + 1
            issue(snapshot, "PROPERTY_RECORD_ERROR", failure)
        end
    end

    if not finite(valueSum) then
        section.status = "partial"
        issue(snapshot, "BUILDINGS_TOTAL_OVERFLOW", "The buildings subtotal exceeded the supported numeric range and is unavailable.")
    elseif valueCount > 0 or (section.ownedCount == 0 and section.status == "available") then
        section.totalValue = valueSum
    end
    table.sort(section.items, function(a, b)
        if type(a.id) ~= type(b.id) then
            return type(a.id) < type(b.id)
        end
        if type(a.id) == "number" then
            return a.id < b.id
        end
        return a.id < b.id
    end)
end
