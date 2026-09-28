-- Narrow retained-finance adapter. FS25 compatibility candidates never establish
-- calendar periods, complete history or cash flow. See docs/finance-sources.md.
BankFinanceDataSource = {}

local MAP_SOURCE = "lizardbank.finance-map.v1 (policy; native category matching unverified)"
local CATEGORY_MAP = {
    soldProducts = "operating", soldMilk = "operating", soldBales = "operating", soldWood = "operating",
    harvestIncome = "operating", missionIncome = "operating", fieldJobIncome = "operating",
    vehicleRunningCost = "operating", vehicleLeasingCost = "operating",
    propertyMaintenance = "operating", wagePayment = "operating",
    purchaseSeeds = "operating", purchaseFertilizer = "operating",
    purchaseSaplings = "operating", purchaseFuel = "operating", purchaseWater = "operating",
    newVehicles = "capital", soldVehicles = "capital", constructionCost = "capital",
    boughtFields = "capital", soldFields = "capital", soldBuildings = "capital",
    loanInterest = "financing", loanBorrowed = "financing", loanRepaid = "financing"
}
-- Exact runtime identity only: no numeric enum assumptions or fuzzy matching.
-- These are Lizard Bank's treatment of explicit native transaction categories,
-- not a claim that every named constant exists in every game build.
local MONEY_TYPE_MAP = {
    SOLD_PRODUCTS = {"soldProducts", "operating"}, SOLD_MILK = {"soldMilk", "operating"},
    SOLD_BALES = {"soldBales", "operating"}, SOLD_WOOD = {"soldWood", "operating"},
    MISSIONS = {"missionIncome", "operating"}, MISSION_REWARD = {"missionIncome", "operating"},
    PURCHASE_SEEDS = {"purchaseSeeds", "operating"}, PURCHASE_FERTILIZER = {"purchaseFertilizer", "operating"},
    PURCHASE_SAPLINGS = {"purchaseSaplings", "operating"}, PURCHASE_FUEL = {"purchaseFuel", "operating"},
    PURCHASE_WATER = {"purchaseWater", "operating"},
    VEHICLE_RUNNING_COSTS = {"vehicleRunningCost", "operating"},
    VEHICLE_LEASING_COSTS = {"vehicleLeasingCost", "operating"},
    PROPERTY_MAINTENANCE = {"propertyMaintenance", "operating"},
    WAGE_PAYMENT = {"wagePayment", "operating"},
    PURCHASE_VEHICLE = {"newVehicles", "capital"}, NEW_VEHICLES = {"newVehicles", "capital"},
    SOLD_VEHICLES = {"soldVehicles", "capital"}, VEHICLE_BUY = {"newVehicles", "capital"},
    VEHICLE_SELL = {"soldVehicles", "capital"}, BUILDING_BUY = {"constructionCost", "capital"},
    BUILDING_SELL = {"soldBuildings", "capital"}, CONSTRUCTION_COST = {"constructionCost", "capital"},
    PURCHASE_LAND = {"boughtFields", "capital"}, SOLD_LAND = {"soldFields", "capital"},
    LAND_BUY = {"boughtFields", "capital"}, LAND_SELL = {"soldFields", "capital"},
    LOAN_INTEREST = {"loanInterest", "interest"},
    LOAN_BORROWED = {"loanBorrowed", "financing"}, LOAN_REPAYMENT = {"loanRepaid", "financing"},
    NEW_ANIMALS_COST = {"newAnimals", "unclassified"}, SOLD_ANIMALS = {"soldAnimals", "unclassified"}
}
local METADATA_KEYS = {day = true, period = true, year = true, month = true, date = true,
    currentDay = true, currentPeriod = true, currentYear = true, currentMonotonicDay = true,
    startDay = true, endDay = true, isCurrent = true, isComplete = true, isPadding = true}
local MAX_BUCKETS, MAX_KEYS, MAX_RECORDS = 256, 512, 8192

local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function scalar(value)
    return type(value) == "string" or type(value) == "boolean" or finite(value)
end

local function key(value)
    return (type(value) == "string" and value ~= "") or finite(value)
end

local function issue(snapshot, code, detail)
    snapshot.issues[#snapshot.issues + 1] = {code = code, detail = tostring(detail)}
end

local function call(snapshot, object, method, ...)
    if type(object) ~= "table" then return nil end
    local ok, fn = pcall(function() return object[method] end)
    if not ok then
        issue(snapshot, "FINANCE_ACCESSOR_ERROR", method .. ": " .. tostring(fn))
        return nil
    end
    if type(fn) ~= "function" then return nil end
    local succeeded, value = pcall(fn, object, ...)
    if not succeeded then
        issue(snapshot, "FINANCE_ACCESSOR_ERROR", method .. ": " .. tostring(value))
        return nil
    end
    return value
end

local function field(snapshot, object, name)
    if type(object) ~= "table" then return nil end
    local ok, value = pcall(function() return object[name] end)
    if ok then return value end
    issue(snapshot, "FINANCE_FIELD_ERROR", tostring(name) .. ": " .. tostring(value))
    return nil
end

local function sortedKeys(snapshot, object, label)
    local result, visited = {}, 0
    for candidate in pairs(object) do
        visited = visited + 1
        if visited > MAX_KEYS then
            snapshot.finance.truncated = true
            issue(snapshot, "FINANCE_SCAN_LIMIT", label .. " exceeds the bounded key scan; remaining entries are omitted.")
            break
        end
        if key(candidate) then
            result[#result + 1] = candidate
        else
            snapshot.finance.ignoredKeyCount = snapshot.finance.ignoredKeyCount + 1
            issue(snapshot, "FINANCE_KEY_UNAVAILABLE", label .. " contains a non-scalar key; the entry is omitted.")
        end
    end
    table.sort(result, function(a, b)
        if type(a) ~= type(b) then return type(a) < type(b) end
        return a < b
    end)
    return result
end

function BankFinanceDataSource.classifyCategory(categoryKey)
    if type(categoryKey) == "string" and CATEGORY_MAP[categoryKey] ~= nil then
        return CATEGORY_MAP[categoryKey], MAP_SOURCE
    end
    return "unclassified", "No exact category match in lizardbank.finance-map.v1"
end

function BankFinanceDataSource.classifyMoneyType(moneyType, moneyTypes)
    if (not key(moneyType) and type(moneyType) ~= "table") or type(moneyTypes) ~= "table" then
        return nil, "unclassified", "MoneyType or its runtime registry is unavailable"
    end
    local unknownOk, unknownType = pcall(function() return moneyTypes.UNKNOWN end)
    if unknownOk and unknownType ~= nil and rawequal(unknownType, moneyType) then
        return nil, "unclassified", "Runtime MoneyType.UNKNOWN"
    end
    local matchedKey, matchedClass, matchedName
    for name, policy in pairs(MONEY_TYPE_MAP) do
        local ok, enumValue = pcall(function() return moneyTypes[name] end)
        -- rawequal also prevents a custom __eq metamethod from inventing a match.
        if ok and enumValue ~= nil and rawequal(enumValue, moneyType) then
            if matchedKey ~= nil and (matchedKey ~= policy[1] or matchedClass ~= policy[2]) then
                return nil, "unclassified", "Ambiguous runtime MoneyType identity matches different policy categories"
            end
            matchedKey, matchedClass = policy[1], policy[2]
            if matchedName == nil or name < matchedName then matchedName = name end
        end
    end
    if matchedKey ~= nil then
        return matchedKey, matchedClass, "lizardbank.finance-map.v1 exact runtime MoneyType." .. matchedName
    end
    return nil, "unclassified", "No exact runtime MoneyType identity match in lizardbank.finance-map.v1"
end

local function copyMetadata(snapshot, object)
    local result = {}
    for name in pairs(METADATA_KEYS) do
        local value = field(snapshot, object, name)
        if scalar(value) then result[name] = value end
    end
    return result
end

local function labelFor(snapshot, context, bucket, categoryKey)
    if type(categoryKey) ~= "string" then return "Native category " .. tostring(categoryKey), "raw key" end
    local names = field(snapshot, bucket, "statNamesI18n")
    if type(names) ~= "table" then names = field(snapshot, context.FinanceStats, "statNamesI18n") end
    local translated = field(snapshot, names, categoryKey)
    if type(translated) == "string" and translated ~= "" then return translated, "FinanceStats.statNamesI18n [compatibility candidate]" end
    local textKey = "finance_" .. categoryKey
    if call(snapshot, context.g_i18n, "hasText", textKey) == true then
        translated = call(snapshot, context.g_i18n, "getText", textKey)
        if type(translated) == "string" and translated ~= "" and translated ~= textKey then
            return translated, "g_i18n finance_ key [compatibility candidate]"
        end
    end
    return categoryKey, "raw category key"
end

local function readBucket(snapshot, context, bucket, bucketKind, periodKey, source, seen)
    local section = snapshot.finance
    if #section.buckets >= MAX_BUCKETS then
        section.truncated = true
        issue(snapshot, "FINANCE_SCAN_LIMIT", "Retained finance buckets exceed the scan limit; no missing periods are invented.")
        return
    end
    local descriptor = {id = "finance-bucket-" .. tostring(#section.buckets + 1), kind = bucketKind,
        periodKey = periodKey, periodKeyType = type(periodKey), source = source,
        status = "unavailable", periodStatus = "unverified", metadata = {}, knownValueCount = 0, unknownValueCount = 0}
    section.buckets[#section.buckets + 1] = descriptor
    if type(bucket) ~= "table" then
        section.unknownBucketCount = section.unknownBucketCount + 1
        issue(snapshot, "FINANCE_BUCKET_UNAVAILABLE", source .. " is not a readable retained-category map.")
        return
    end
    if seen[bucket] ~= nil then
        descriptor.status, descriptor.duplicateOf = "duplicate", seen[bucket]
        section.duplicateBucketCount = section.duplicateBucketCount + 1
        issue(snapshot, "FINANCE_BUCKET_ALIAS", source .. " aliases an already read category map; not counted twice.")
        return
    end
    seen[bucket] = descriptor.id
    descriptor.metadata = copyMetadata(snapshot, bucket)
    descriptor.status = "partial"
    local categories, categorySet = {}, {}
    local function include(categoryKey, declared)
        if key(categoryKey) and not categorySet[categoryKey] and (declared or not METADATA_KEYS[categoryKey])
            and categoryKey ~= "statNames" and categoryKey ~= "statNamesI18n" then
            categorySet[categoryKey] = true
            categories[#categories + 1] = categoryKey
        end
    end
    local nativeNames = field(snapshot, bucket, "statNames")
    if type(nativeNames) ~= "table" then nativeNames = field(snapshot, context.FinanceStats, "statNames") end
    if type(nativeNames) == "table" then
        for _, index in ipairs(sortedKeys(snapshot, nativeNames, source .. ".statNames")) do
            local name = field(snapshot, nativeNames, index)
            if type(name) == "string" and name ~= "" then include(name, true) end
        end
    end
    for _, categoryKey in ipairs(sortedKeys(snapshot, bucket, source)) do
        local value = field(snapshot, bucket, categoryKey)
        if type(value) ~= "function" then include(categoryKey) end
    end
    table.sort(categories, function(a, b)
        if type(a) ~= type(b) then return type(a) < type(b) end
        return a < b
    end)
    for _, categoryKey in ipairs(categories) do
        if #section.records >= MAX_RECORDS then
            section.truncated = true
            descriptor.truncated = true
            issue(snapshot, "FINANCE_SCAN_LIMIT", "Finance category rows exceed the scan limit; remaining rows are omitted.")
            break
        end
        local classification, classificationSource = BankFinanceDataSource.classifyCategory(categoryKey)
        local label, labelSource = labelFor(snapshot, context, bucket, categoryKey)
        local record = {bucketId = descriptor.id, bucketKind = bucketKind, periodKey = periodKey,
            periodKeyType = type(periodKey), periodStatus = "unverified", categoryKey = categoryKey,
            categoryKeyType = type(categoryKey), label = label, labelSource = labelSource,
            classification = classification, classificationSource = classificationSource,
            status = "unavailable", source = source .. "[" .. tostring(categoryKey) .. "]"}
        section.records[#section.records + 1] = record
        local value = field(snapshot, bucket, categoryKey)
        record.rawValueType = type(value)
        if finite(value) then
            record.rawSignedValue, record.status = value, "available"
            section.knownValueCount = section.knownValueCount + 1
            descriptor.knownValueCount = descriptor.knownValueCount + 1
        else
            if type(value) == "boolean" or type(value) == "string" then record.rawNonNumericValue = value end
            section.unknownValueCount = section.unknownValueCount + 1
            descriptor.unknownValueCount = descriptor.unknownValueCount + 1
        end
        if classification == "unclassified" then section.unclassifiedCount = section.unclassifiedCount + 1 end
    end
    if #categories == 0 then
        descriptor.status = "emptyObservedMap"
        issue(snapshot, "FINANCE_BUCKET_EMPTY", source .. " has no readable category rows; this is not proof of a zero-activity period.")
    elseif descriptor.knownValueCount > 0 and descriptor.unknownValueCount == 0 and not descriptor.truncated then
        descriptor.status = "available"
    end
end

function BankFinanceDataSource.collect(snapshot, context)
    local section = {status = "unavailable", verification = "unverified", windowStatus = "unverified",
        classificationSource = MAP_SOURCE, records = {}, buckets = {}, metadata = {}, knownValueCount = 0,
        unknownValueCount = 0, unclassifiedCount = 0, unknownBucketCount = 0, duplicateBucketCount = 0,
        ignoredKeyCount = 0, truncated = false, source = "unavailable"}
    snapshot.finance = section
    local capabilities = snapshot.capabilities
    local mission, manager = context.g_currentMission, context.g_farmManager
    local farmId = snapshot.farm and snapshot.farm.id
    capabilities.financeMissionFarmStats = type(field(snapshot, mission, "farmStats")) == "function"
    capabilities.financeFarmManager = type(field(snapshot, manager, "getFarmById")) == "function"
    capabilities.financeStatsClass = type(context.FinanceStats) == "table"
    issue(snapshot, "FINANCE_NATIVE_UNVERIFIED", "Retained finance rows preserve native signed values. FS25 category layout, sign convention, calendar order, current/completed periods, padding and retained window require Finance-screen reconciliation; no historical cash-flow totals are inferred.")
    if not finite(farmId) or farmId <= 0 then
        issue(snapshot, "FINANCE_FARM_UNAVAILABLE", "No resolved active farm; retained finances cannot be attributed.")
        return
    end

    local farm = call(snapshot, manager, "getFarmById", farmId)
    local candidates = {
        {value = call(snapshot, mission, "farmStats", farmId), source = "mission:farmStats(activeFarmId)"},
        {value = field(snapshot, farm, "stats"), source = "activeFarm.stats"},
        {value = field(snapshot, farm, "farmStats"), source = "activeFarm.farmStats"}
    }
    local stats
    for index, candidate in ipairs(candidates) do
        capabilities["financeStatsCandidate" .. tostring(index) .. "Type"] = type(candidate.value)
        if type(candidate.value) == "table" then
            local candidateOwner = field(snapshot, candidate.value, "farmId")
            local current = field(snapshot, candidate.value, "finances")
            local history = field(snapshot, candidate.value, "financesHistory")
            if finite(candidateOwner) and candidateOwner ~= farmId then
                issue(snapshot, "FINANCE_OWNER_MISMATCH", candidate.source .. " reports a different farm ID and is excluded.")
            elseif stats == nil and (type(current) == "table" or type(history) == "table") then
                stats, section.source = candidate.value, candidate.source .. " [FS25 compatibility candidate]"
            end
        end
    end
    if stats == nil then
        issue(snapshot, "FINANCE_STATS_UNAVAILABLE", "No candidate farm stats exposes finances or financesHistory; missing data is not zero.")
        return
    end
    section.status = "partial"
    section.metadata = copyMetadata(snapshot, stats)
    for _, name in ipairs({"financesVersionCounter", "financesHistoryVersionCounter", "financesHistoryVersionCounterLocal"}) do
        local value = field(snapshot, stats, name)
        if scalar(value) then section.metadata[name] = value end
    end
    local current, history = field(snapshot, stats, "finances"), field(snapshot, stats, "financesHistory")
    capabilities.financeCurrentType, capabilities.financeHistoryType = type(current), type(history)
    local seen = {}
    if current ~= nil then
        local ok, failure = pcall(readBucket, snapshot, context, current, "currentCandidate", "current", section.source .. ".finances", seen)
        if not ok then
            section.unknownBucketCount = section.unknownBucketCount + 1
            issue(snapshot, "FINANCE_BUCKET_ERROR", failure)
        end
    else
        issue(snapshot, "FINANCE_CURRENT_UNAVAILABLE", "The candidate current finance map is absent.")
    end
    if type(history) == "table" then
        for _, periodKey in ipairs(sortedKeys(snapshot, history, section.source .. ".financesHistory")) do
            local ok, failure = pcall(readBucket, snapshot, context, field(snapshot, history, periodKey), "historyCandidate", periodKey,
                section.source .. ".financesHistory[" .. tostring(periodKey) .. "]", seen)
            if not ok then
                section.unknownBucketCount = section.unknownBucketCount + 1
                issue(snapshot, "FINANCE_BUCKET_ERROR", failure)
            end
        end
    else
        issue(snapshot, "FINANCE_HISTORY_UNAVAILABLE", "The candidate retained finance history map is absent or unreadable.")
    end
    if section.unknownValueCount > 0 then
        issue(snapshot, "FINANCE_VALUES_UNAVAILABLE", tostring(section.unknownValueCount) .. " category rows are missing or nonnumeric; none are replaced with zero.")
    end
    if section.unclassifiedCount > 0 then
        issue(snapshot, "FINANCE_UNCLASSIFIED", tostring(section.unclassifiedCount) .. " rows have no exact classification policy match and remain unclassified.")
    end
end
