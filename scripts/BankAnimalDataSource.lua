-- Current animals in strictly owned, registered husbandries.
-- Native reference quotes remain separate from the combined asset subtotal.
-- Confirmed APIs and deliberately unsupported fields: docs/animal-sources.md.
BankAnimalDataSource = {}

-- Opt-in evidence only. No extra game accessors or live references in events.
local function diagnosticScalar(value)
    if type(value) == "string" or type(value) == "boolean" then return value end
    if type(value) == "number" and value == value and math.abs(value) < math.huge then return value end
    return nil
end

local function diagnosticRead(name, ok, value, reason)
    if BankDiagnostics ~= nil and BankDiagnostics.isEnabled() then
        BankDiagnostics.read("animals", name, ok, value, {reason = reason})
    end
end

local function diagnosticField(object, name)
    local value = object[name]
    diagnosticRead(name, true, value, "raw_field")
    return value
end

local function diagnosticDecision(checkId, outcome, id, value, reason, expected)
    if BankDiagnostics ~= nil and BankDiagnostics.isEnabled() then
        BankDiagnostics.check(checkId, outcome, {section = "animals", id = diagnosticScalar(id),
            value = diagnosticScalar(value), valueType = type(value), reason = reason,
            expected = diagnosticScalar(expected)})
    end
end

local function diagnosticBoundary(stage, name, ok, status, detail)
    if BankDiagnostics ~= nil and BankDiagnostics.isEnabled() then
        BankDiagnostics.emit("collector." .. stage, {section = "animals", name = name,
            ok = ok, status = status, detail = diagnosticScalar(detail)})
    end
end

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
    diagnosticBoundary("issue", code, false, "reported", detail)
end

local function partial(snapshot, code, detail)
    snapshot.animals.status = "partial"
    issue(snapshot, code, detail)
end

local function call(snapshot, object, name, ...)
    if type(object) ~= "table" or type(object[name]) ~= "function" then
        diagnosticRead(name, false, nil, "missing_accessor")
        return nil
    end
    local ok, result = pcall(object[name], object, ...)
    diagnosticRead(name, ok, result, ok and "accessor_return" or "accessor_error")
    if not ok then
        partial(snapshot, "ANIMAL_ACCESSOR_ERROR", name .. ": " .. tostring(result))
        return nil
    end
    return result
end

local function removing(object)
    return diagnosticField(object, "markedForDeletion") == true or diagnosticField(object, "isDeleting") == true or diagnosticField(object, "isDeleted") == true
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
        diagnosticRead("cluster.numAnimals", true, count, "raw_count_fallback")
        capabilities.animalCountFieldCount = capabilities.animalCountFieldCount + 1
    end
    if nonnegative(count) and count == math.floor(count) then
        item.count = count
    else
        partial(snapshot, "ANIMAL_COUNT_UNAVAILABLE", location .. ": animal group has no valid current whole-animal count.")
    end
    diagnosticDecision("ANIMAL_COUNT", item.count ~= nil and "PASS" or "UNAVAILABLE", item.id, count, "Whole nonnegative animal count.")

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
    diagnosticDecision("ANIMAL_VALUE", item.value ~= nil and "PASS" or "UNAVAILABLE", item.id, item.value, QUOTE_SOURCE, item.unitValue)

    -- GIANTS formats cluster.health directly as a percent in husbandry info.
    local rawHealth = cluster.health
    diagnosticRead("cluster.health", true, rawHealth, "raw_field")
    if nonnegative(rawHealth) and cluster.health <= 100 then
        item.healthPercent = cluster.health
        capabilities.animalHealthAvailableCount = capabilities.animalHealthAvailableCount + 1
    else
        capabilities.animalHealthUnavailableCount = capabilities.animalHealthUnavailableCount + 1
        partial(snapshot, "ANIMAL_HEALTH_UNAVAILABLE", location .. ": current group health is unavailable.")
    end
    diagnosticDecision("ANIMAL_HEALTH", item.healthPercent ~= nil and "PASS" or "UNAVAILABLE", item.id, item.healthPercent, "Verified raw percent scale.")

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
    local rawReproduction = cluster.reproduction
    diagnosticRead("cluster.reproduction", true, rawReproduction, "unverified_raw_diagnostic")
    if finite(rawReproduction) then
        capabilities.animalReproductionFieldCount = capabilities.animalReproductionFieldCount + 1
        item.reproductionRaw = cluster.reproduction
        item.reproductionSource = "cluster.reproduction (unit and meaning unverified; diagnostic only)"
        if capabilities.animalReproductionRawExample == nil then
            capabilities.animalReproductionRawExample = cluster.reproduction
        end
    end
    diagnosticDecision("ANIMAL_OPTIONAL_UNITS", "UNAVAILABLE", item.id, item.ageRaw,
        "Age and reproduction remain raw diagnostics, not confirmed units.", item.reproductionRaw)

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
    diagnosticBoundary("enter", "collect", true)
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
        diagnosticBoundary("exit", "collect", true, section.status)
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
        diagnosticBoundary("exit", "collect", true, section.status)
        return
    end

    section.status = "available"
    diagnosticRead(capabilities.animalEnumeration, true, placeables, "selected_registry")
    local seenHusbandries, seenIds, seenClusters = {}, {}, {}
    local enumerationComplete = true
    for _, placeable in pairs(placeables) do
        local ok, failure = pcall(function()
            if type(placeable) ~= "table" then error("Invalid registered placeable record") end
            if type(placeable.spec_husbandryAnimals) ~= "table" then return end
            if seenHusbandries[placeable] then
                diagnosticDecision("ANIMAL_HUSBANDRY_DEDUP", "PASS", nil, true, "Duplicate husbandry reference excluded.")
                capabilities.animalDuplicateHusbandryCount = capabilities.animalDuplicateHusbandryCount + 1
                return
            end
            seenHusbandries[placeable] = true
            local id = identifier(call(snapshot, placeable, "getUniqueId"))
            local owner = call(snapshot, placeable, "getOwnerFarmId")
            diagnosticDecision("ANIMAL_OWNER", finite(owner) and "PASS" or "UNAVAILABLE", id, owner,
                owner == farmId and "Exact owned husbandry." or "Excluded: owner mismatch or unavailable.", farmId)
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
                diagnosticDecision("ANIMAL_HUSBANDRY_DEDUP", "PASS", id, true, "Duplicate husbandry ID excluded.")
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
                        diagnosticDecision("ANIMAL_CLUSTER_DEDUP", "PASS", location, true, "Duplicate cluster reference excluded.")
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
                    diagnosticBoundary("recordError", "cluster", false, "partial", clusterFailure)
                    enumerationComplete = false
                    unknownRow(snapshot, location, "ANIMAL_CLUSTER_ERROR", clusterFailure)
                end
            end
        end)
        if not ok then
            diagnosticBoundary("recordError", "husbandry", false, "partial", failure)
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
    diagnosticBoundary("exit", "collect", true, section.status)
end
