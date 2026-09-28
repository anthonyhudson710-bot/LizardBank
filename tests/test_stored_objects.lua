dofile("scripts/BankStoredObjectDataSource.lua")

local count = 0
local function test(name, callback)
    if _G.test ~= nil then _G.test("stored objects: " .. name, callback); return end
    callback(); count = count + 1; print("PASS stored objects: " .. name)
end
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function issueExists(snapshot, code)
    for _, issue in ipairs(snapshot.issues) do if issue.code == code then return true end end
    return false
end
local BaleClass = {}
local function fixture()
    local snapshot = {farm = {id = 7}, issues = {}, capabilities = {}, inventory = {
        items = {}, sourceCount = 0, unknownCount = 0, zeroCount = 0, excludedCount = 0, coverage = {}
    }}
    local context = {Bale = BaleClass, VehiclePropertyState = {OWNED = 11, LEASED = 12, MISSION = 13},
        g_currentMission = {placeableSystem = {placeables = {}}, itemSystem = {items = {}}}}
    local helpers = {registeredBales = {}, blockedUniqueIds = {}}
    helpers.issue = function(s, code, detail) s.issues[#s.issues + 1] = {code = code, detail = detail} end
    helpers.unknown = function(s, category, code, detail)
        s.inventory.unknownCount = s.inventory.unknownCount + 1
        s.inventory.coverage[category] = "partial"
        helpers.issue(s, code, detail)
    end
    helpers.call = function(s, object, method, ...)
        if type(object) ~= "table" or type(object[method]) ~= "function" then return nil end
        local ok, value = pcall(object[method], object, ...)
        if ok then return value end
        helpers.issue(s, "INVENTORY_ACCESSOR_ERROR", tostring(value))
    end
    helpers.addQuantity = function(s, _, category, item)
        if item.quantity == 0 then s.inventory.zeroCount = s.inventory.zeroCount + 1; return end
        if type(item.quantity) ~= "number" or item.quantity < 0 or item.quantity ~= item.quantity
            or item.quantity == math.huge then
            item.quantity = nil
            item.quantityStatus = "unavailable"
            helpers.unknown(s, category, "INVENTORY_QUANTITY_UNAVAILABLE", item.id)
        else item.quantityStatus = "available" end
        item.includedInAssetQuote, item.cargoOwnership = "unknown", "unverified"
        s.inventory.items[#s.inventory.items + 1] = item
    end
    return snapshot, context, helpers, {}
end
local function bale(id, quantity, owner)
    return {uniqueId = id, isMissionBale = false,
        isa = function(_, class) return class == BaleClass end,
        getOwnerFarmId = function() return owner or 7 end,
        getFillLevel = function() return quantity end, getFillType = function() return 1 end,
        getIsFermenting = function() return false end}
end
local function pallet(id, units, owner)
    return {uniqueId = id, isPallet = true, isa = function() return false end,
        getOwnerFarmId = function() return owner or 7 end, getPropertyState = function() return 11 end,
        getFillUnits = function() return units end,
        getFillUnitFillLevel = function(_, index) return units[index].quantity end,
        getFillUnitFillType = function(_, index) return units[index].fillType end}
end
local function abstract(real, className)
    return {REFERENCE_CLASS_NAME = className or "Bale", getRealObject = function() return real end,
        getDialogText = function() return "Native object description" end}
end
local function store(objects, owner)
    return {uniqueId = "barn", getOwnerFarmId = function() return owner or 7 end,
        getName = function() return "Bale barn" end, spec_objectStorage = {storedObjects = objects}}
end

test("registered real bales support raw and wrapped item records and reject unrelated items", function()
    local s, c, h, blocked = fixture()
    local one, two = bale("a", 2000), bale("b", 3000)
    c.g_currentMission.itemSystem.items = {one, {item = two}, one,
        bale("a", 99999), {isa = function() return false end}}
    BankStoredObjectDataSource.collect(s, c, h, blocked)
    equal(#s.inventory.items, 2); equal(s.inventory.sourceCount, 2)
    equal(s.inventory.items[1].quantity, 2000); equal(s.inventory.items[2].quantity, 3000)
    assert(h.registeredBales[one] and h.registeredBales[two])
    equal(s.inventory.coverage.bales, "available")
end)

test("other farms and mission bales do not become farm stock", function()
    local s, c, h, blocked = fixture()
    local mission, other, own = bale("contract", 4000), bale("other", 6000, 8), bale("own", 1000)
    mission.isMissionBale = true
    mission.getFillLevel = function() error("Do not measure contract goods") end
    c.g_currentMission.itemSystem.items = {mission, other, own}
    BankStoredObjectDataSource.collect(s, c, h, blocked)
    equal(#s.inventory.items, 1); equal(s.inventory.items[1].quantity, 1000)
    equal(s.inventory.excludedCount, 1)
    assert(h.registeredBales[mission] and h.registeredBales[other])
    assert(issueExists(s, "INVENTORY_MISSION_BALE_EXCLUDED"))
end)

test("loaded unsellable bales remain quantities and use actual current fermentation fill type", function()
    local s, c, h, blocked = fixture()
    local item = bale("loaded", 3500)
    item.getNeedsSaving = function() return false end
    item.getCanBeSold = function() return false end
    item.getIsFermenting = function() return true end
    item.getFermentingPercentage = function() return 0.35 end
    item.getFillType = function() return 42 end
    c.g_currentMission.itemSystem.items = {item}
    BankStoredObjectDataSource.collect(s, c, h, blocked)
    local row = s.inventory.items[1]
    equal(row.fillTypeIndex, 42); equal(row.quantity, 3500)
    equal(row.isFermenting, true); equal(row.fermentationProgress, 0.35)
    equal(row.value, nil)
end)

test("stored bale counterpart and every registry identity alias count once", function()
    local s, c, h, blocked = fixture()
    local real = bale("same", 4500)
    local wrapped = abstract(real)
    c.g_currentMission.placeableSystem.placeables = {store({wrapped, wrapped, abstract(real)})}
    c.g_currentMission.itemSystem.items = {real, bale("same", 4500)}
    BankStoredObjectDataSource.collect(s, c, h, blocked)
    equal(#s.inventory.items, 1); equal(s.inventory.sourceCount, 1)
    equal(s.inventory.items[1].kind, "storedBale"); equal(s.inventory.items[1].objectCount, 1)
    assert(blocked[real]); assert(h.blockedUniqueIds.same)
end)

test("stored pallets preserve all units custom text and one object count", function()
    local s, c, h, blocked = fixture()
    local real = pallet("pallet", {{quantity = 40, fillType = 2, unitText = "pieces"}, {quantity = 70, fillType = 3}})
    c.g_currentMission.placeableSystem.placeables = {store({abstract(real, "Vehicle")})}
    BankStoredObjectDataSource.collect(s, c, h, blocked)
    equal(#s.inventory.items, 2); equal(s.inventory.sourceCount, 1)
    equal(s.inventory.items[1].unit, "units"); equal(s.inventory.items[1].unitText, "pieces")
    equal(s.inventory.items[2].unit, "l")
    equal((s.inventory.items[1].objectCount or 0) + (s.inventory.items[2].objectCount or 0), 1)
    assert(blocked[real])
end)

test("pure virtual records show object count and unavailable quantity without parsing UI text", function()
    local s, c, h, blocked = fixture()
    local virtual = abstract(nil)
    virtual.getDialogText = function() return "Hay bale 9,000 liters" end
    virtual.fillLevel = 9000 -- undocumented field must not be guessed
    virtual.baleAttributes = {fillLevel = 9000, fillType = 1, farmId = 7}
    c.g_currentMission.placeableSystem.placeables = {store({virtual})}
    BankStoredObjectDataSource.collect(s, c, h, blocked)
    local row = s.inventory.items[1]
    equal(row.quantity, nil); equal(row.quantityStatus, "unavailable"); equal(row.objectCount, 1)
    equal(row.ownership, "unknown"); equal(row.objectName, "Hay bale 9,000 liters")
    assert(issueExists(s, "INVENTORY_VIRTUAL_QUANTITY_UNAVAILABLE"))
    assert(s.capabilities.inventoryAbstractObjectSample1:find("baleAttributes:table", 1, true))
    assert(not s.capabilities.inventoryAbstractObjectSample1:find("9000", 1, true))
end)

test("unknown object class retains unavailable entry rather than inventing a bale", function()
    local s, c, h, blocked = fixture()
    c.g_currentMission.placeableSystem.placeables = {store({abstract(nil, "CustomCargo")})}
    BankStoredObjectDataSource.collect(s, c, h, blocked)
    equal(s.inventory.items[1].kind, "objectStorage")
    equal(s.inventory.items[1].objectClass, "CustomCargo")
    equal(s.inventory.items[1].quantity, nil)
end)

test("removed storage blocks its counterparts even when other adapters still register them", function()
    local s, c, h, blocked = fixture()
    local real = bale("removed", 6000)
    local barn = store({abstract(real)})
    barn.markedForDeletion = true
    c.g_currentMission.placeableSystem.placeables = {barn}
    c.g_currentMission.itemSystem.items = {real, bale("healthy", 1500)}
    BankStoredObjectDataSource.collect(s, c, h, blocked)
    equal(#s.inventory.items, 1); equal(s.inventory.items[1].quantity, 1500)
    assert(blocked[real]); assert(issueExists(s, "INVENTORY_SOURCE_REMOVING"))
end)

test("deleted and unknown-owner loose bales are omitted while healthy sources survive", function()
    local s, c, h, blocked = fixture()
    local deleted, unknown = bale("deleted", 9000), bale("unknown", 9000)
    deleted.isDeleted = true
    deleted.getFillLevel = function() error("Removed source touched") end
    unknown.getOwnerFarmId = function() return nil end
    c.g_currentMission.itemSystem.items = {deleted, unknown, bale("healthy", 350)}
    BankStoredObjectDataSource.collect(s, c, h, blocked)
    equal(#s.inventory.items, 1); equal(s.inventory.items[1].quantity, 350)
    assert(issueExists(s, "INVENTORY_OWNER_UNAVAILABLE"))
    assert(not issueExists(s, "INVENTORY_ACCESSOR_ERROR"))
end)

test("preblocked transient bales remain registered for proxy reconciliation", function()
    local s, c, h, blocked = fixture()
    local transient = bale("chamber", 8000)
    blocked[transient] = true
    c.g_currentMission.itemSystem.items = {transient}
    BankStoredObjectDataSource.collect(s, c, h, blocked)
    equal(#s.inventory.items, 0)
    assert(h.registeredBales[transient]); assert(blocked[transient])
end)

test("missing registries and missing native Bale class differ from empty supported data", function()
    local s, c, h, blocked = fixture()
    BankStoredObjectDataSource.collect(s, c, h, blocked)
    equal(s.inventory.coverage.bales, "available"); equal(s.inventory.coverage.objectStorage, "available")
    c.g_currentMission.itemSystem = nil; c.g_currentMission.placeableSystem = nil
    BankStoredObjectDataSource.collect(s, c, h, blocked)
    equal(s.inventory.coverage.bales, "unavailable"); equal(s.inventory.coverage.objectStorage, "unavailable")
    c.g_currentMission.itemSystem = {items = {bale("known", 500)}}
    c.Bale = nil
    BankStoredObjectDataSource.collect(s, c, h, blocked)
    equal(s.inventory.coverage.bales, "unavailable")
    equal(#s.inventory.items, 0)
end)

test("invalid and throwing quantity getters keep a useful partial report", function()
    local s, c, h, blocked = fixture()
    local broken = bale("broken", 5)
    broken.getFillLevel = function() error("mod error") end
    c.g_currentMission.itemSystem.items = {bale("empty", 0), bale("negative", -1), bale("infinite", math.huge),
        broken, bale("good", 125)}
    BankStoredObjectDataSource.collect(s, c, h, blocked)
    equal(s.inventory.zeroCount, 1); equal(#s.inventory.items, 4)
    equal(s.inventory.items[1].quantity, nil); equal(s.inventory.items[4].quantity, 125)
    equal(s.inventory.coverage.bales, "partial")
    assert(issueExists(s, "INVENTORY_ACCESSOR_ERROR"))
end)

test("stored counterparts with another owner are blocked and never attributed by building ownership", function()
    local s, c, h, blocked = fixture()
    local other = bale("foreign", 8000, 8)
    c.g_currentMission.placeableSystem.placeables = {store({abstract(other)})}
    c.g_currentMission.itemSystem.items = {other}
    BankStoredObjectDataSource.collect(s, c, h, blocked)
    equal(#s.inventory.items, 0); assert(blocked[other])
end)

test("diagnostic shape samples are capped and never retain native objects", function()
    local s, c, h, blocked = fixture()
    local entries = {}
    for n = 1, 8 do
        local item = abstract(nil)
        for i = 1, 30 do item["field" .. tostring(i)] = {} end
        entries[n] = item
    end
    c.g_currentMission.placeableSystem.placeables = {store(entries)}
    BankStoredObjectDataSource.collect(s, c, h, blocked)
    equal(s.capabilities.inventoryAbstractObjectSample4, nil)
    local _, commas = s.capabilities.inventoryAbstractObjectSample1:gsub(",", "")
    assert(commas <= 11)
    local function detached(value)
        if type(value) == "table" then
            for key, item in pairs(value) do
                assert(type(key) ~= "table"); detached(item)
            end
        else assert(type(value) ~= "function" and type(value) ~= "userdata") end
    end
    detached(s)
end)

test("documented placableByUniqueId fallback reads stored entries", function()
    local s, c, h, blocked = fixture()
    local real = bale("stored", 1200)
    c.g_currentMission.placeableSystem = {placableByUniqueId = {barn = store({abstract(real)})}}
    BankStoredObjectDataSource.collect(s, c, h, blocked)
    equal(#s.inventory.items, 1); equal(s.inventory.items[1].quantity, 1200)
    equal(s.inventory.items[1].objectCount, 1)
end)

test("bad fermentation progress is unavailable without changing current crop quantity", function()
    local s, c, h, blocked = fixture()
    local real = bale("fermenting", 1400)
    real.getIsFermenting = function() return true end
    real.getFermentingPercentage = function() return math.huge end
    c.g_currentMission.itemSystem.items = {real}
    BankStoredObjectDataSource.collect(s, c, h, blocked)
    equal(s.inventory.items[1].quantity, 1400); equal(s.inventory.items[1].fillTypeIndex, 1)
    equal(s.inventory.items[1].fermentationProgress, nil)
    equal(s.inventory.items[1].objectCount, 1)
    assert(issueExists(s, "INVENTORY_FERMENTATION_UNAVAILABLE"))
end)

if _G.test == nil then print(string.format("%d stored-object tests passed", count)) end
