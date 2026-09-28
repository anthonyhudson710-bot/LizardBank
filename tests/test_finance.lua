dofile("scripts/BankFinanceDataSource.lua")

local function contextFor(stats, farmId)
    return {
        g_currentMission = {farmStats = function(_, requested)
            assertEqual(requested, farmId or 8)
            return stats
        end},
        g_farmManager = {getFarmById = function(_, requested)
            assertEqual(requested, farmId or 8)
            return {stats = stats}
        end}
    }
end

local function capture(stats, context)
    local snapshot = {farm = {id = 8}, capabilities = {}, issues = {}}
    BankFinanceDataSource.collect(snapshot, context or contextFor(stats))
    return snapshot
end

local function row(snapshot, categoryKey, periodKey)
    for _, record in ipairs(snapshot.finance.records) do
        if record.categoryKey == categoryKey and record.periodKey == (periodKey or "current") then return record end
    end
end

local function hasIssue(snapshot, code)
    for _, entry in ipairs(snapshot.issues) do
        if entry.code == code then return true end
    end
    return false
end

test("finance preserves raw signed categories and separates retained buckets without inferred periods", function()
    local result = capture({finances = {soldProducts = 200, purchaseSeeds = -30, newVehicles = -1000, loanInterest = -5},
        financesHistory = {[0] = {soldProducts = 90}, [3] = {soldProducts = 0}}})
    assertEqual(result.finance.knownValueCount, 6)
    assertEqual(row(result, "purchaseSeeds").rawSignedValue, -30)
    assertEqual(row(result, "newVehicles").classification, "capital")
    assertEqual(row(result, "loanInterest").classification, "financing")
    assertEqual(row(result, "soldProducts", 0).rawSignedValue, 90)
    assertEqual(row(result, "soldProducts", 3).rawSignedValue, 0)
    assertEqual(row(result, "soldProducts", 3).periodKeyType, "number")
    assertEqual(result.finance.status, "partial")
    assertEqual(result.finance.verification, "unverified")
    assertEqual(result.finance.windowStatus, "unverified")
    assertEqual(result.finance.totalValue, nil)
    assertEqual(result.finance.completedPeriodCount, nil)
    assertEqual(#result.finance.buckets, 3)
    assertTrue(hasIssue(result, "FINANCE_NATIVE_UNVERIFIED"))
end)

test("finance does not treat empty missing or zero-padded maps as completed zero-activity months", function()
    local empty = capture({finances = {}, financesHistory = {{soldProducts = 0}, {soldProducts = 0}}})
    assertEqual(empty.finance.buckets[1].status, "emptyObservedMap")
    assertEqual(empty.finance.knownValueCount, 2)
    assertEqual(row(empty, "soldProducts", 1).periodStatus, "unverified")
    assertEqual(empty.finance.totalValue, nil)
    local missing = capture(nil)
    assertEqual(missing.finance.status, "unavailable")
    assertEqual(#missing.finance.records, 0)
    assertTrue(hasIssue(missing, "FINANCE_STATS_UNAVAILABLE"))
end)

test("finance resolves the supplied farm dynamically and excludes mismatched stats ownership", function()
    local wrong = {farmId = 3, finances = {soldProducts = 999}}
    local right = {farmId = 8, finances = {soldProducts = 25}}
    local context = contextFor(wrong)
    context.g_farmManager.getFarmById = function(_, farmId) assertEqual(farmId, 8) return {stats = right} end
    local result = capture(nil, context)
    assertEqual(row(result, "soldProducts").rawSignedValue, 25)
    assertContains(result.finance.source, "activeFarm.stats")
    assertTrue(hasIssue(result, "FINANCE_OWNER_MISMATCH"))
    local absent = {farm = {}, capabilities = {}, issues = {}}
    BankFinanceDataSource.collect(absent, context)
    assertEqual(absent.finance.status, "unavailable")
    assertTrue(hasIssue(absent, "FINANCE_FARM_UNAVAILABLE"))
end)

test("finance uses narrow farm candidates when a mission accessor is absent or fails", function()
    local stats = {finances = {soldProducts = 10}}
    local context = contextFor(stats)
    context.g_currentMission.farmStats = function() error("custom mission accessor failed") end
    context.g_farmManager.getFarmById = function() return {farmStats = stats} end
    local result = capture(nil, context)
    assertEqual(row(result, "soldProducts").rawSignedValue, 10)
    assertContains(result.finance.source, "activeFarm.farmStats")
    assertTrue(hasIssue(result, "FINANCE_ACCESSOR_ERROR"))
end)

test("finance never merges different candidate sources or follows arbitrary object graphs", function()
    local source = {finances = {soldProducts = 10}, financesHistory = {}}
    local context = contextFor(source)
    context.g_farmManager.getFarmById = function()
        return {stats = {finances = {soldProducts = 999}}, arbitrary = {secret = source}}
    end
    local result = capture(nil, context)
    assertEqual(result.finance.knownValueCount, 1)
    assertEqual(row(result, "soldProducts").rawSignedValue, 10)
    context.g_currentMission = {arbitrary = {stats = source}}
    context.g_farmManager.getFarmById = function() return {arbitrary = {stats = source}} end
    assertEqual(capture(nil, context).finance.status, "unavailable")
end)

test("finance deduplicates aliased buckets but preserves identical independent retained maps", function()
    local current = {soldProducts = 10}
    local result = capture({finances = current, financesHistory = {current, {soldProducts = 10}, {soldProducts = 10}}})
    assertEqual(result.finance.knownValueCount, 3)
    assertEqual(result.finance.duplicateBucketCount, 1)
    assertEqual(result.finance.buckets[2].status, "duplicate")
    assertEqual(result.finance.buckets[2].duplicateOf, result.finance.buckets[1].id)
    assertTrue(hasIssue(result, "FINANCE_BUCKET_ALIAS"))
end)

test("finance preserves native period metadata as unverified scalars instead of manufacturing dates", function()
    local result = capture({currentDay = 50, financesVersionCounter = 19, finances = {soldProducts = 10, year = 3},
        financesHistory = {["native-slot"] = {soldProducts = 20, day = 8, period = 4, isComplete = true, isPadding = false}}})
    assertEqual(result.finance.metadata.currentDay, 50)
    assertEqual(result.finance.metadata.financesVersionCounter, 19)
    assertEqual(result.finance.buckets[2].metadata.day, 8)
    assertEqual(result.finance.buckets[2].metadata.period, 4)
    assertTrue(result.finance.buckets[2].metadata.isComplete)
    assertEqual(result.finance.buckets[2].periodStatus, "unverified")
    assertEqual(row(result, "soldProducts", "native-slot").year, nil)
    assertEqual(#result.finance.records, 2)
end)

test("finance keeps declared missing categories unavailable and rejects nonfinite or nonnumeric values", function()
    local stats = {finances = {soldProducts = 0, purchaseSeeds = "20", other = false, broken = {}, huge = math.huge, nan = 0/0}}
    local context = contextFor(stats)
    context.FinanceStats = {statNames = {"soldProducts", "purchaseSeeds", "loanInterest", "soldProducts"}}
    local result = capture(nil, context)
    assertEqual(result.finance.knownValueCount, 1)
    assertEqual(result.finance.unknownValueCount, 6)
    assertEqual(row(result, "soldProducts").rawSignedValue, 0)
    assertEqual(row(result, "loanInterest").status, "unavailable")
    assertEqual(row(result, "purchaseSeeds").rawNonNumericValue, "20")
    assertEqual(row(result, "broken").rawSignedValue, nil)
    assertTrue(hasIssue(result, "FINANCE_VALUES_UNAVAILABLE"))
end)

test("finance preserves unknown and numeric categories without substring or case classification", function()
    local result = capture({finances = {customSoldProducts = 25, SOLDPRODUCTS = 30, other = -5, [9] = 40}})
    assertEqual(result.finance.unclassifiedCount, 4)
    assertEqual(row(result, 9).categoryKeyType, "number")
    assertEqual(row(result, "customSoldProducts").classification, "unclassified")
    assertTrue(hasIssue(result, "FINANCE_UNCLASSIFIED"))
end)

test("finance uses runtime native labels and respects explicit declared metadata-name collisions", function()
    local stats = {finances = {soldProducts = 10, day = 30}}
    local context = contextFor(stats)
    context.FinanceStats = {statNames = {"day"}, statNamesI18n = {soldProducts = "Native crop sales"}}
    local result = capture(nil, context)
    assertEqual(row(result, "soldProducts").label, "Native crop sales")
    assertEqual(row(result, "day").classification, "unclassified")
    assertEqual(row(result, "day").rawSignedValue, 30)
end)

test("finance isolates unavailable history buckets and failing labels while preserving raw rows", function()
    local context = contextFor({finances = {soldProducts = 10}, financesHistory = {false, {soldProducts = 20}}})
    context.g_i18n = {hasText = function() error("translation failed") end}
    local result = capture(nil, context)
    assertEqual(result.finance.knownValueCount, 2)
    assertEqual(result.finance.unknownBucketCount, 1)
    assertEqual(row(result, "soldProducts").label, "soldProducts")
    assertTrue(hasIssue(result, "FINANCE_BUCKET_UNAVAILABLE"))
    assertTrue(hasIssue(result, "FINANCE_ACCESSOR_ERROR"))
end)

test("finance ignores non-scalar keys explicitly and bounds oversized retained histories", function()
    local values = {soldProducts = 10, [{}] = 123}
    local result = capture({finances = values})
    assertEqual(result.finance.ignoredKeyCount, 1)
    assertEqual(result.finance.knownValueCount, 1)
    assertTrue(hasIssue(result, "FINANCE_KEY_UNAVAILABLE"))
    local history = {}
    for index = 1, 300 do history[index] = {soldProducts = index} end
    result = capture({finances = {}, financesHistory = history})
    assertTrue(result.finance.truncated)
    assertEqual(#result.finance.buckets, 256)
    assertTrue(hasIssue(result, "FINANCE_SCAN_LIMIT"))
end)

test("finance returns detached DTOs and never invokes economic history or mutation methods", function()
    local stats = {finances = {soldProducts = 10}, financesHistory = {{soldProducts = 20}}}
    stats.archiveFinances = function() error("must not archive") end
    stats.changeFinanceStats = function() error("must not modify") end
    local old = capture(stats)
    stats.finances.soldProducts = 99
    local new = capture(stats)
    assertEqual(row(old, "soldProducts").rawSignedValue, 10)
    assertEqual(row(new, "soldProducts").rawSignedValue, 99)
    local function check(value)
        if type(value) == "table" then
            assertFalse(value == stats)
            assertFalse(value == stats.finances)
            assertFalse(value == stats.financesHistory)
            for k, v in pairs(value) do assertTrue(type(k) == "string" or type(k) == "number"); check(v) end
        else
            assertTrue(type(value) == "string" or type(value) == "number" or type(value) == "boolean")
        end
    end
    check(old.finance)
end)

test("finance classifies live MoneyType only by exact runtime identity and isolates interest", function()
    local sold, fuel, purchase, interest = {}, {}, {}, {}
    local registry = {SOLD_PRODUCTS = sold, PURCHASE_FUEL = fuel, PURCHASE_VEHICLE = purchase, LOAN_INTEREST = interest}
    local category, class, source = BankFinanceDataSource.classifyMoneyType(sold, registry)
    assertEqual(category, "soldProducts")
    assertEqual(class, "operating")
    assertContains(source, "MoneyType.SOLD_PRODUCTS")
    category, class = BankFinanceDataSource.classifyMoneyType(fuel, registry)
    assertEqual(category, "purchaseFuel")
    assertEqual(class, "operating")
    category, class = BankFinanceDataSource.classifyMoneyType(purchase, registry)
    assertEqual(category, "newVehicles")
    assertEqual(class, "capital")
    category, class = BankFinanceDataSource.classifyMoneyType(interest, registry)
    assertEqual(category, "loanInterest")
    assertEqual(class, "interest")
    assertEqual(BankFinanceDataSource.classifyCategory("loanInterest"), "financing")
end)

test("finance MoneyType classification rejects guessed fields unknown values and conflicting identities", function()
    local sold = {}
    local category, class = BankFinanceDataSource.classifyMoneyType({statistic = "soldProducts"}, {SOLD_PRODUCTS = sold})
    assertEqual(category, nil)
    assertEqual(class, "unclassified")
    category, class = BankFinanceDataSource.classifyMoneyType(0, {UNKNOWN = 0, SOLD_PRODUCTS = 0})
    assertEqual(category, nil)
    assertEqual(class, "unclassified")
    category, class = BankFinanceDataSource.classifyMoneyType(sold, {SOLD_PRODUCTS = sold, LOAN_INTEREST = sold})
    assertEqual(category, nil)
    assertEqual(class, "unclassified")
    category, class = BankFinanceDataSource.classifyMoneyType(nil, {})
    assertEqual(category, nil)
    assertEqual(class, "unclassified")
    category, class = BankFinanceDataSource.classifyMoneyType(false, {SOLD_PRODUCTS = false})
    assertEqual(category, nil)
    assertEqual(class, "unclassified")
end)

test("finance MoneyType same-policy aliases coalesce and custom equality cannot invent a match", function()
    local category, class = BankFinanceDataSource.classifyMoneyType(7, {VEHICLE_BUY = 7, PURCHASE_VEHICLE = 7})
    assertEqual(category, "newVehicles")
    assertEqual(class, "capital")
    local mt = {__eq = function() return true end}
    local first, second = setmetatable({}, mt), setmetatable({}, mt)
    category, class = BankFinanceDataSource.classifyMoneyType(first, {SOLD_PRODUCTS = second})
    assertEqual(category, nil)
    assertEqual(class, "unclassified")
end)
