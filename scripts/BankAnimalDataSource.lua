-- Current animals in strictly owned, registered husbandries.
-- Native reference quotes remain separate from the combined asset subtotal.
-- Confirmed APIs and deliberately unsupported fields: docs/animal-sources.md.
BankAnimalDataSource = {}

local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function nonnegative(value)
    return finite(value) and value >= 0
end

local function text(value)
    return type(value) == "string" and value ~= "" and value or nil
end

local function identifier(value)
    if text(value) ~= nil or finite(value) then return value end
    return nil
end

local function issue(snapshot, code, detail)
    snapshot.issues[#snapshot.issues + 1] = {code = code, detail = tostring(detail)}
end

local function partial(snapshot, code, detail)
    snapshot.animals.status = "partial"
    issue(snapshot, code, detail)
end

local function call(snapshot, object, name, ...)
    if type(object) ~= "table" or type(object[name]) ~= "function" then return nil end
    local ok, result = pcall(object[name], object, ...)
    if not ok then
        partial(snapshot, "ANIMAL_ACCESSOR_ERROR", name .. ": " .. tostring(result))
        return nil
    end
    return result
end

local function removing(object)
    return object.markedForDeletion == true or object.isDeleting == true or object.isDeleted == true
end

local QUOTE_SOURCE = "cluster:getSellPrice() per animal x verified count; native reference quote, no additional fee/transport calculation"

local function unknownRow(snapshot, location, code, detail)
    local section = snapshot.animals
    section.items[#section.items + 1] = {
        id = "snapshot-animal-" .. tostring(#section.items + 1),
        location = location,
        name = "Animal group unavailable",
        status = "unavailable",
        valueSource = QUOTE_SOURCE
    }
    partial(snapshot, code, detail)
end

local function collectCluster(snapshot, context, cluster, location)
    local section, capabilities = snapshot.animals, snapshot.capabilities
    local item = {
        id = "snapshot-animal-" .. tostring(#section.items + 1),
        location = location,
        name = "Animal group",
        status = "unavailable",
        valueSource = QUOTE_SOURCE
    }
    local count
    if type(cluster.getNumAnimals) == "function" then
        capabilities.animalCountGetterCount = capabilities.animalCountGetterCount + 1
        count = call(snapshot, cluster, "getNumAnimals")
    else
        -- PlaceableHusbandryAnimals:getNumOfAnimals reads this same native field.
        count = cluster.numAnimals
        capabilities.animalCountFieldCount = capabilities.animalCountFieldCount + 1
    end
    if nonnegative(count) and count == math.floor(count) then
        item.count = count
    else
        partial(snapshot, "ANIMAL_COUNT_UNAVAILABLE", location .. ": animal group has no valid current whole-animal count.")
    end

    local unitValue = call(snapshot, cluster, "getSellPrice")
    if nonnegative(unitValue) then
        item.unitValue = unitValue
        if item.count ~= nil and nonnegative(unitValue * item.count) then
            item.value = unitValue * item.count
            item.status = "available"
        end
    end
    if item.value == nil then
        partial(snapshot, "ANIMAL_VALUE_UNAVAILABLE", location .. ": native per-animal quote or counted group value is unavailable.")
    end

    -- GIANTS formats cluster.health directly as a percent in husbandry info.
    if nonnegative(cluster.health) and cluster.health <= 100 then
        item.healthPercent = cluster.health
        capabilities.animalHealthAvailableCount = capabilities.animalHealthAvailableCount + 1
    else
        capabilities.animalHealthUnavailableCount = capabilities.animalHealthUnavailableCount + 1
        partial(snapshot, "ANIMAL_HEALTH_UNAVAILABLE", location .. ": current group health is unavailable.")
    end

    -- These observations are diagnostics only. The published specialization
    -- docs do not establish the units of age or reproduction; never guess.
    if type(cluster.getAge) == "function" then
        capabilities.animalAgeGetterCount = capabilities.animalAgeGetterCount + 1
        local rawAge = call(snapshot, cluster, "getAge")
        if finite(rawAge) then
            item.ageRaw = rawAge
            item.ageSource = "cluster:getAge() (unit unverified)"
            if capabilities.animalAgeRawExample == nil then capabilities.animalAgeRawExample = rawAge end
        end
    end
    if finite(cluster.reproduction) then
        capabilities.animalReproductionFieldCount = capabilities.animalReproductionFieldCount + 1
        item.reproductionRaw = cluster.reproduction
        item.reproductionSource = "cluster.reproduction (unit and meaning unverified; diagnostic only)"
        if capabilities.animalReproductionRawExample == nil then
            capabilities.animalReproductionRawExample = cluster.reproduction
        end
    end

    -- getName is an individual horse name where supported, not a breed label.
    local individualName = text(call(snapshot, cluster, "getName"))
    local subTypeIndex
    if type(cluster.getSubTypeIndex) == "function" then
        subTypeIndex = call(snapshot, cluster, "getSubTypeIndex")
    else
        subTypeIndex = cluster.subTypeIndex
    end
    local animalSystem = context.g_currentMission and context.g_currentMission.animalSystem
    local subType = finite(subTypeIndex) and call(snapshot, animalSystem, "getSubTypeByIndex", subTypeIndex) or nil
    local localizedName
    if type(subType) == "table" then
        item.subtypeKey = text(subType.name)
        if finite(subType.fillTypeIndex) then
            local fillType = call(snapshot, context.g_fillTypeManager, "getFillTypeByIndex", subType.fillTypeIndex)
            if type(fillType) == "table" then localizedName = text(fillType.title) end
        end
    end
    item.name = individualName or localizedName or item.name
    if localizedName ~= nil then
        item.nativeTypeName = localizedName
        capabilities.animalLocalizedNameCount = capabilities.animalLocalizedNameCount + 1
    elseif individualName == nil then
        capabilities.animalNameUnavailableCount = capabilities.animalNameUnavailableCount + 1
        partial(snapshot, "ANIMAL_NAME_UNAVAILABLE", location .. ": localized animal label is unavailable; see subtypeKey in diagnostics when supplied.")
    end
    section.items[#section.items + 1] = item
    section.clusterCount = section.clusterCount + 1
end

function BankAnimalDataSource.collect(snapshot, context)
    local section = {
        items = {}, ownedHusbandryCount = 0, clusterCount = 0,
        unknownCountCount = 0, unknownValueCount = 0, excludedCount = 0,
        status = "unavailable", transportedStatus = "excluded", riddenStatus = "excluded"
    }
    snapshot.animals = section
    local mission = context.g_currentMission
    local system = mission and mission.placeableSystem
    local capabilities = snapshot.capabilities
    capabilities.animalPlaceableSystem = type(system) == "table"
    capabilities.animalSystem = mission ~= nil and type(mission.animalSystem) == "table"
    capabilities.animalFillTypeManager = type(context.g_fillTypeManager) == "table"
    capabilities.animalAgeUnitsVerified = false
    capabilities.animalReproductionUnitsVerified = false
    for _, name in ipairs({"animalDuplicateHusbandryCount", "animalDuplicateClusterCount", "animalCountGetterCount", "animalCountFieldCount", "animalHealthAvailableCount", "animalHealthUnavailableCount", "animalAgeGetterCount", "animalReproductionFieldCount", "animalLocalizedNameCount", "animalNameUnavailableCount"}) do
        capabilities[name] = 0
    end
    capabilities.animalAgeRawExample = nil
    capabilities.animalReproductionRawExample = nil
    issue(snapshot, "ANIMAL_COVERAGE_PARTIAL", "Only animals in owned registered husbandries are covered. Transported and currently ridden animals are excluded; native reference quotes stay separate from combined assets with no additional fee/transport calculation.")
    issue(snapshot, "ANIMAL_OPTIONAL_DETAILS_UNVERIFIED", "Age in months and reproduction percentages are unavailable until their native units are verified. Raw diagnostic observations are not normalized or displayed as confirmed measurements.")

    local farmId = snapshot.farm and snapshot.farm.id
    if not finite(farmId) or farmId <= 0 or type(system) ~= "table" then
        issue(snapshot, "ANIMALS_UNAVAILABLE", "Active farm or registered placeable system is unavailable.")
        return
    end
    local placeables = system.placeables
    capabilities.animalEnumeration = "mission.placeableSystem.placeables"
    if type(placeables) ~= "table" then
        placeables = system.placableByUniqueId
        capabilities.animalEnumeration = "mission.placeableSystem.placableByUniqueId"
        if type(placeables) == "table" then
            issue(snapshot, "ANIMAL_ENUMERATION_FALLBACK", "Using GIANTS' registered placeable lookup because the primary list is unavailable.")
        end
    end
    if type(placeables) ~= "table" then
        issue(snapshot, "ANIMALS_UNAVAILABLE", "Registered placeable enumeration is unavailable.")
        return
    end

    section.status = "available"
    local seenHusbandries, seenIds, seenClusters = {}, {}, {}
    local enumerationComplete = true
    for _, placeable in pairs(placeables) do
        local ok, failure = pcall(function()
            if type(placeable) ~= "table" then error("Invalid registered placeable record") end
            if type(placeable.spec_husbandryAnimals) ~= "table" then return end
            if seenHusbandries[placeable] then
                capabilities.animalDuplicateHusbandryCount = capabilities.animalDuplicateHusbandryCount + 1
                return
            end
            seenHusbandries[placeable] = true
            local id = identifier(call(snapshot, placeable, "getUniqueId"))
            local owner = call(snapshot, placeable, "getOwnerFarmId")
            if not finite(owner) then
                enumerationComplete = false
                section.excludedCount = section.excludedCount + 1
                partial(snapshot, "ANIMAL_OWNER_UNAVAILABLE", "Husbandry " .. tostring(id or "without ID") .. " omitted because ownership cannot be verified.")
                return
            end
            if owner ~= farmId then return end
            if removing(placeable) then
                enumerationComplete = false
                section.excludedCount = section.excludedCount + 1
                partial(snapshot, "ANIMAL_HUSBANDRY_REMOVING", "Owned husbandry is being removed; refresh after the operation finishes.")
                return
            end
            if id ~= nil and seenIds[id] then
                capabilities.animalDuplicateHusbandryCount = capabilities.animalDuplicateHusbandryCount + 1
                return
            end
            if id ~= nil then seenIds[id] = true end
            section.ownedHusbandryCount = section.ownedHusbandryCount + 1
            local location = text(call(snapshot, placeable, "getName")) or "Owned husbandry"
            local clusters = call(snapshot, placeable, "getClusters")
            if type(clusters) ~= "table" then
                enumerationComplete = false
                unknownRow(snapshot, location, "ANIMAL_CLUSTERS_UNAVAILABLE", location .. ": cluster enumeration is unavailable.")
                return
            end
            for _, cluster in pairs(clusters) do
                local clusterOk, clusterFailure = pcall(function()
                    if type(cluster) ~= "table" then error("Invalid animal cluster record") end
                    if seenClusters[cluster] then
                        capabilities.animalDuplicateClusterCount = capabilities.animalDuplicateClusterCount + 1
                        return
                    end
                    seenClusters[cluster] = true
                    if removing(cluster) then
                        enumerationComplete = false
                        unknownRow(snapshot, location, "ANIMAL_CLUSTER_REMOVING", location .. ": a group is being removed; refresh after the operation finishes.")
                        return
                    end
                    collectCluster(snapshot, context, cluster, location)
                end)
                if not clusterOk then
                    enumerationComplete = false
                    unknownRow(snapshot, location, "ANIMAL_CLUSTER_ERROR", clusterFailure)
                end
            end
        end)
        if not ok then
            enumerationComplete = false
            section.excludedCount = section.excludedCount + 1
            partial(snapshot, "ANIMAL_HUSBANDRY_ERROR", failure)
        end
    end

    local countSum, valueSum, knownCounts, knownValues = 0, 0, 0, 0
    for _, item in ipairs(section.items) do
        if item.count ~= nil then
            countSum, knownCounts = countSum + item.count, knownCounts + 1
        else
            section.unknownCountCount = section.unknownCountCount + 1
        end
        if item.value ~= nil then
            valueSum, knownValues = valueSum + item.value, knownValues + 1
        else
            section.unknownValueCount = section.unknownValueCount + 1
        end
    end
    local verifiedEmpty = #section.items == 0 and enumerationComplete
    if finite(countSum) and (knownCounts > 0 or verifiedEmpty) then
        section.totalCount = countSum
    elseif not finite(countSum) then
        partial(snapshot, "ANIMAL_COUNT_OVERFLOW", "Count subtotal exceeds the supported numeric range.")
    end
    if finite(valueSum) and (knownValues > 0 or verifiedEmpty) then
        section.totalValue = valueSum
    elseif not finite(valueSum) then
        partial(snapshot, "ANIMAL_VALUE_OVERFLOW", "Native livestock quote subtotal exceeds the supported numeric range.")
    end
    table.sort(section.items, function(a, b)
        for _, field in ipairs({"location", "name", "subtypeKey", "ageRaw", "count", "id"}) do
            local left, right = a[field], b[field]
            if left ~= right then
                if left == nil then return false end
                if right == nil then return true end
                return left < right
            end
        end
        return false
    end)
end
