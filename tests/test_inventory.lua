dofile("scripts/BankStoredObjectDataSource.lua")
dofile("scripts/BankInventoryDataSource.lua")

local count = 0
local function test(name, callback)
    if _G.test ~= nil then _G.test("inventory: " .. name, callback); return end
    callback()
    count = count + 1
    print("PASS inventory: " .. name)
end

local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function hasIssue(snapshot, code)
    for _, item in ipairs(snapshot.issues) do if item.code == code then return true end end
    return false
end

local function fixture()
    return {farm = {id = 7}, issues = {}, capabilities = {}}, {
        g_currentMission = {placeableSystem = {placeables = {}}, storageSystem = {storages = {}}, vehicleSystem = {vehicles = {}}, itemSystem = {items = {}}},
        Bale = {},
        g_fillTypeManager = {getFillTypeByIndex = function(_, index)
            if index == 1 then return {name = "WHEAT", title = "Wheat"} end
            if index == 2 then return {name = "SEEDS", title = "Seeds"} end
            if index == 3 then return {name = "TREESAPLINGS", title = "Tree saplings"} end
        end},
        FillType = {UNKNOWN = 0},
        VehiclePropertyState = {OWNED = 11, LEASED = 12, MISSION = 13}
    }
end

local function storage(levels, owner)
    return {getOwnerFarmId = function() return owner or 7 end, getFillLevels = function() return levels end}
end

local function placeable(id, name, owner)
    return {uniqueId = id, getName = function() return name end, getOwnerFarmId = function() return owner or 7 end}
end

local function vehicle(id, units, state, owner)
    return {uniqueId = id, getName = function() return id end, getOwnerFarmId = function() return owner or 7 end,
        getPropertyState = function() return state or 11 end,
        getFillUnits = function() return units end,
        getFillUnitFillLevel = function(_, index) return units[index].fillLevel end,
        getFillUnitFillType = function(_, index) return units[index].fillType end}
end

test("silos and extensions use contents owner and deduplicate registry aliases", function()
    local snapshot, context = fixture()
    local own, other, extension = storage({[1] = 600, [2] = 0}), storage({[1] = 9000}, 8), storage({[2] = 200})
    local silo = placeable("silo", "Shared silo", 8)
    silo.spec_silo = {storages = {own, other}}
    silo.getCanAccess = function() error("Access is not ownership") end
    local ext = placeable("ext", "Extension")
    ext.spec_siloExtension = {storage = extension}
    context.g_currentMission.placeableSystem.placeables = {silo, ext, silo}
    context.g_currentMission.storageSystem.storages = {[own] = own, [extension] = extension, [other] = other}
    local section = BankInventoryDataSource.collect(snapshot, context)
    equal(#section.items, 2)
    equal(section.sourceCount, 2)
    equal(section.zeroCount, 1)
    equal(section.items[1].quantity, 200)
    equal(section.items[2].quantity, 600)
    equal(section.items[2].fillTypeTitle, "Wheat")
    equal(section.unknownCount, 0)
end)

test("dedicated production storage belongs to owned finalized placeable", function()
    local snapshot, context = fixture()
    local grain = storage({[1] = 450}, 0)
    local mill, other, unfinished = placeable("mill", "Mill"), placeable("foreign", "Foreign", 8), placeable("unfinished", "Unfinished")
    mill.spec_productionPoint = {productionPoint = {storage = grain}, isFinalized = true}
    other.spec_productionPoint = {productionPoint = {storage = storage({[1] = 9000}, 8)}}
    unfinished.spec_productionPoint = {productionPoint = {storage = storage({[1] = 5000})}, isFinalized = false}
    context.g_currentMission.placeableSystem.placeables = {mill, other, unfinished}
    context.g_currentMission.storageSystem.storages = {grain}
    local section = BankInventoryDataSource.collect(snapshot, context)
    equal(#section.items, 1)
    equal(section.items[1].kind, "production")
    equal(section.items[1].quantity, 450)
    equal(section.sourceCount, 1)
    equal(section.excludedCount, 1)
end)

test("loaded units, pallets and leased containers disclose unverified cargo title", function()
    local snapshot, context = fixture()
    local tractor = vehicle("tractor", {{fillLevel = 30, fillType = 2}})
    local trailer = vehicle("trailer", {{fillLevel = 1000, fillType = 1}, {fillLevel = 50, fillType = 2}}, 12)
    local pallet = vehicle("pallet", {{fillLevel = 200, fillType = 2}})
    pallet.isPallet = true
    local borrowed = vehicle("borrowed", {{fillLevel = 9999, fillType = 1}}, 13)
    borrowed.getFillUnits = function() error("Do not inspect borrowed cargo") end
    context.g_currentMission.vehicleSystem.vehicles = {tractor, trailer, pallet, borrowed, tractor,
        vehicle("tractor", {{fillLevel = 30, fillType = 2}}), vehicle("foreign", {{fillLevel = 8000, fillType = 1}}, 11, 8)}
    local section = BankInventoryDataSource.collect(snapshot, context)
    equal(section.sourceCount, 3)
    equal(#section.items, 4)
    equal(section.excludedCount, 1)
    equal(section.items[1].kind, "pallet")
    for _, item in ipairs(section.items) do
        equal(item.cargoOwnership, "unverified")
        equal(item.includedInAssetQuote, "unknown")
        equal(item.value, nil)
    end
    equal(section.items[3].ownership, "leased")
end)

test("native custom unit text is preserved without inventing liters", function()
    local snapshot, context = fixture()
    context.g_currentMission.vehicleSystem.vehicles = {vehicle("saplings", {{fillLevel = 20, fillType = 3, unitText = "pieces"}})}
    local item = BankInventoryDataSource.collect(snapshot, context).items[1]
    equal(item.quantity, 20)
    equal(item.unit, "units")
    equal(item.unitText, "pieces")
end)

test("tree planter proxy does not duplicate the mounted sapling pallet", function()
    local snapshot, context = fixture()
    local pallet = vehicle("pallet", {{fillLevel = 20, fillType = 3, unitText = "pieces"}})
    pallet.isPallet = true
    local planter = vehicle("planter", {{fillLevel = 20, fillType = 3}, {fillLevel = 7, fillType = 2}})
    planter.spec_treePlanter = {fillUnitIndex = 1, mountedSaplingPallet = pallet}
    context.g_currentMission.vehicleSystem.vehicles = {planter, pallet}
    local section = BankInventoryDataSource.collect(snapshot, context)
    equal(#section.items, 2)
    equal(section.items[1].quantity, 20)
    equal(section.items[2].quantity, 7)
    equal(section.excludedCount, 1)
end)

test("missing registered mounted pallet is an explicit coverage gap", function()
    local snapshot, context = fixture()
    local pallet = vehicle("pallet", {{fillLevel = 20, fillType = 3}})
    local planter = vehicle("planter", {{fillLevel = 20, fillType = 3}})
    planter.spec_treePlanter = {fillUnitIndex = 1, mountedSaplingPallet = pallet}
    context.g_currentMission.vehicleSystem.vehicles = {planter}
    local section = BankInventoryDataSource.collect(snapshot, context)
    equal(#section.items, 0)
    equal(section.unknownCount, 1)
    assert(hasIssue(snapshot, "INVENTORY_MOUNTED_PALLET_UNAVAILABLE"))
end)

test("verified zero and unavailable quantities remain different", function()
    local snapshot, context = fixture()
    context.g_currentMission.vehicleSystem.vehicles = {vehicle("bad", {
        {fillLevel = 0, fillType = 0}, {fillLevel = -1, fillType = 1},
        {fillLevel = math.huge, fillType = 1}, {fillLevel = 0/0, fillType = 1},
        {fillType = 1}, {fillLevel = 70, fillType = 1}
    })}
    local section = BankInventoryDataSource.collect(snapshot, context)
    equal(section.zeroCount, 1)
    equal(#section.items, 5)
    equal(section.unknownCount, 4)
    for i = 1, 4 do
        equal(section.items[i].quantity, nil)
        equal(section.items[i].quantityStatus, "unavailable")
    end
    equal(section.items[5].quantity, 70)
end)

test("missing metadata preserves known quantity and discloses identification gap", function()
    local snapshot, context = fixture()
    context.g_currentMission.storageSystem.storages = {storage({[999] = 45, [0] = 10})}
    local section = BankInventoryDataSource.collect(snapshot, context)
    equal(#section.items, 2)
    equal(section.items[1].quantity, 10)
    equal(section.items[1].fillTypeIndex, nil)
    equal(section.items[2].quantity, 45)
    equal(section.items[2].fillTypeName, "Fill type 999")
    equal(section.unknownCount, 2)
end)

test("bad accessor does not prevent neighboring sources or fill units", function()
    local snapshot, context = fixture()
    local badStorage = storage({})
    badStorage.getFillLevels = function() error("broken silo") end
    context.g_currentMission.storageSystem.storages = {badStorage, storage({[1] = 10})}
    local badVehicle = vehicle("mixed", {{fillLevel = 5, fillType = 1}, {fillLevel = 10, fillType = 2}})
    badVehicle.getFillUnitFillLevel = function(_, index) if index == 1 then error("broken unit") end; return 10 end
    context.g_currentMission.vehicleSystem.vehicles = {badVehicle}
    local section = BankInventoryDataSource.collect(snapshot, context)
    equal(#section.items, 3)
    equal(section.sourceCount, 3)
    assert(hasIssue(snapshot, "INVENTORY_ACCESSOR_ERROR"))
    equal(section.coverage.storage, "partial")
    equal(section.coverage.vehicle, "partial")
end)

test("missing farm, systems, and an empty supported inventory are distinguishable", function()
    local snapshot, context = fixture()
    local section = BankInventoryDataSource.collect(snapshot, context)
    equal(section.status, "partial")
    equal(section.coverage.storage, "available")
    equal(section.coverage.vehicle, "available")
    equal(section.sourceCount, 0)
    equal(section.unknownCount, 0)
    equal(section.coverage.bales, "available")
    equal(section.coverage.objectStorage, "available")
    section = BankInventoryDataSource.collect(snapshot, {})
    equal(section.status, "unavailable")
    equal(section.coverage.vehicle, "unavailable")
    snapshot.farm.id = nil
    section = BankInventoryDataSource.collect(snapshot, context)
    equal(section.status, "unavailable")
    equal(#section.items, 0)
    assert(hasIssue(snapshot, "INVENTORY_FARM_UNAVAILABLE"))
end)

test("owned object storage counts the held pallet once at its storage location", function()
    local snapshot, context = fixture()
    local pallet = vehicle("storedPallet", {{fillLevel = 300, fillType = 1}})
    pallet.isPallet = true
    local barn = placeable("barn", "Bale and pallet barn")
    barn.spec_objectStorage = {storedObjects = {{getRealObject = function() return pallet end}}}
    context.g_currentMission.placeableSystem.placeables = {barn}
    context.g_currentMission.vehicleSystem.vehicles = {pallet}
    local section = BankInventoryDataSource.collect(snapshot, context)
    equal(#section.items, 1)
    equal(section.items[1].quantity, 300)
    equal(section.items[1].kind, "storedPallet")
    equal(section.items[1].location, "Bale and pallet barn")
    equal(section.excludedCount, 0)
end)

test("unknown owners and property states never become attributed holdings", function()
    local snapshot, context = fixture()
    local unknownStorage = storage({[1] = 20})
    unknownStorage.getOwnerFarmId = nil
    local unknownVehicle = vehicle("unknown", {{fillLevel = 30, fillType = 1}})
    unknownVehicle.getOwnerFarmId = function() return nil end
    context.g_currentMission.storageSystem.storages = {unknownStorage}
    context.g_currentMission.vehicleSystem.vehicles = {unknownVehicle, vehicle("state", {{fillLevel = 70, fillType = 1}}, 99)}
    local section = BankInventoryDataSource.collect(snapshot, context)
    equal(#section.items, 0)
    equal(section.unknownCount, 3)
    assert(hasIssue(snapshot, "INVENTORY_OWNER_UNAVAILABLE"))
    assert(hasIssue(snapshot, "INVENTORY_PROPERTY_UNAVAILABLE"))
end)

test("refresh snapshots are detached and have deterministic row order", function()
    local snapshot, context = fixture()
    local levels = {[1] = 100}
    local firstStorage = storage(levels)
    context.g_currentMission.storageSystem.storages = {z = firstStorage, a = storage({[2] = 20})}
    local before = BankInventoryDataSource.collect(snapshot, context)
    equal(before.items[1].id, "storage:a:fill:2")
    levels[1] = 5
    local after = BankInventoryDataSource.collect(snapshot, context)
    equal(before.items[2].quantity, 100)
    equal(after.items[2].quantity, 5)
    local function check(value)
        if type(value) == "table" then for key, child in pairs(value) do
            assert(type(key) ~= "table" and type(key) ~= "function")
            check(child)
        end
        else assert(type(value) ~= "function" and type(value) ~= "userdata") end
    end
    check(after)
end)

test("removed placeable stores cannot reappear through registry or sibling aliases", function()
    local snapshot, context = fixture()
    local siloStorage, extensionStorage, productionStorage = storage({[1] = 100}), storage({[1] = 200}), storage({[1] = 300})
    local silo, extension, production = placeable("silo", "Silo"), placeable("extension", "Extension"), placeable("production", "Production")
    silo.spec_silo = {storages = {siloStorage}}
    silo.markedForDeletion = true
    extension.spec_siloExtension = {storage = extensionStorage}
    extension.isDeleting = true
    production.spec_productionPoint = {productionPoint = {storage = productionStorage}}
    production.isDeleted = true
    local liveAlias = placeable("alias", "Alias")
    liveAlias.spec_silo = {storages = {siloStorage}}
    local live = storage({[1] = 50})
    local accessorDeleted = placeable("method", "Method removed")
    accessorDeleted.spec_silo = {storages = {}}
    accessorDeleted.getIsBeingDeleted = function() return true end
    -- No quantity or ownership accessor on removed sources should execute.
    for _, record in ipairs({silo, extension, production, accessorDeleted, siloStorage, extensionStorage, productionStorage}) do
        record.getOwnerFarmId = function() error("Removed source accessed") end
    end
    context.g_currentMission.placeableSystem.placeables = {liveAlias, silo, extension, production, accessorDeleted}
    context.g_currentMission.storageSystem.storages = {siloStorage, extensionStorage, productionStorage, live}
    local section = BankInventoryDataSource.collect(snapshot, context)
    equal(#section.items, 1)
    equal(section.items[1].quantity, 50)
    equal(section.sourceCount, 1)
    equal(section.excludedCount, 4)
    equal(section.coverage.storage, "partial")
    assert(hasIssue(snapshot, "INVENTORY_SOURCE_REMOVING"))
    assert(not hasIssue(snapshot, "INVENTORY_ACCESSOR_ERROR"))
end)

test("all deletion signals exclude vehicle cargo while preserving healthy quantities", function()
    local snapshot, context = fixture()
    local vehicles = {}
    for _, flag in ipairs({"markedForDeletion", "isDeleting", "isDeleted", "method"}) do
        local record = vehicle(flag, {{fillLevel = 500, fillType = 1}})
        if flag == "method" then record.getIsBeingDeleted = function() return true end else record[flag] = true end
        record.getFillUnits = function() error("Removed vehicle accessed") end
        vehicles[#vehicles + 1] = record
    end
    vehicles[#vehicles + 1] = vehicle("healthy", {{fillLevel = 25, fillType = 1}})
    context.g_currentMission.vehicleSystem.vehicles = vehicles
    local section = BankInventoryDataSource.collect(snapshot, context)
    equal(#section.items, 1)
    equal(section.items[1].quantity, 25)
    equal(section.excludedCount, 4)
    equal(section.sourceCount, 1)
    equal(section.coverage.vehicle, "partial")
    assert(hasIssue(snapshot, "INVENTORY_SOURCE_REMOVING"))
    assert(not hasIssue(snapshot, "INVENTORY_ACCESSOR_ERROR"))
end)

test("standalone registered storage respects deletion without a placeable", function()
    local snapshot, context = fixture()
    local removed = storage({[1] = 400})
    removed.isDeleted = true
    removed.getFillLevels = function() error("Removed registry storage accessed") end
    context.g_currentMission.storageSystem.storages = {removed, storage({[1] = 20})}
    local section = BankInventoryDataSource.collect(snapshot, context)
    equal(#section.items, 1)
    equal(section.items[1].quantity, 20)
    equal(section.excludedCount, 1)
    assert(not hasIssue(snapshot, "INVENTORY_ACCESSOR_ERROR"))
end)

test("deleted virtual store display objects never become loose inventory", function()
    local snapshot, context = fixture()
    local pallet = vehicle("display", {{fillLevel = 600, fillType = 1}})
    local barn = placeable("barn", "Removed barn")
    barn.markedForDeletion = true
    barn.spec_objectStorage = {storedObjects = {{getRealObject = function() return pallet end}}}
    context.g_currentMission.placeableSystem.placeables = {barn}
    context.g_currentMission.vehicleSystem.vehicles = {pallet}
    local section = BankInventoryDataSource.collect(snapshot, context)
    equal(#section.items, 0)
    equal(section.sourceCount, 0)
    assert(hasIssue(snapshot, "INVENTORY_SOURCE_REMOVING"))
end)

local function bale(context, id, amount)
    return {uniqueId = id, isa = function(_, class) return class == context.Bale end,
        getOwnerFarmId = function() return 7 end,
        getFillLevel = function() return amount end, getFillType = function() return 1 end}
end

test("bale loader counts and straw blower mirrors never duplicate physical bale quantities", function()
    local snapshot, context = fixture()
    local held = bale(context, "held", 4000)
    local loader = vehicle("loader", {{fillLevel = 1, fillType = 1}, {fillLevel = 10, fillType = 2}})
    loader.spec_baleLoader = {fillUnitIndex = 1}
    local blower = vehicle("blower", {{fillLevel = 4000, fillType = 1}})
    blower.spec_strawBlower = {fillUnitIndex = 1, currentBale = held}
    context.g_currentMission.itemSystem.items = {held}
    context.g_currentMission.vehicleSystem.vehicles = {loader, blower}
    local section = BankInventoryDataSource.collect(snapshot, context)
    equal(#section.items, 2)
    local wheat, seeds = 0, 0
    for _, item in ipairs(section.items) do
        if item.fillTypeIndex == 1 then wheat = wheat + item.quantity else seeds = seeds + item.quantity end
    end
    equal(wheat, 4000)
    equal(seeds, 10)
    assert(not hasIssue(snapshot, "INVENTORY_BALE_PROXY_UNAVAILABLE"))
    context.g_currentMission.itemSystem.items = {}
    BankInventoryDataSource.collect(snapshot, context)
    assert(hasIssue(snapshot, "INVENTORY_BALE_PROXY_UNAVAILABLE"))
end)

test("round baler transition is omitted while independent buffer and square-baler material remain", function()
    local snapshot, context = fixture()
    local chamber = bale(context, "chamber", 6000)
    local chamberAlias = bale(context, "chamber", 6000)
    local round = vehicle("round", {{fillLevel = 6000, fillType = 1}, {fillLevel = 70, fillType = 1}})
    round.spec_baler = {fillUnitIndex = 1, hasUnloadingAnimation = true,
        lastBaleFillLevel = 1800, bales = {{baleObject = chamber}}}
    local dropped = bale(context, "square", 5000)
    local square = vehicle("square-baler", {{fillLevel = 150, fillType = 1}})
    square.spec_baler = {fillUnitIndex = 1, hasUnloadingAnimation = false, bales = {{baleObject = dropped}}}
    context.g_currentMission.itemSystem.items = {chamber, chamberAlias, dropped}
    context.g_currentMission.vehicleSystem.vehicles = {round, square}
    local section = BankInventoryDataSource.collect(snapshot, context)
    local sum = 0
    for _, item in ipairs(section.items) do sum = sum + item.quantity end
    equal(sum, 5220)
    assert(hasIssue(snapshot, "INVENTORY_BALE_CHAMBER_TRANSITION"))
    round.spec_baler.bales = {}
    round.spec_baler.lastBaleFillLevel = nil
    round.getFillUnitFillLevel = function(_, index) return index == 1 and 0 or 70 end
    chamber.getFillLevel = function() return 1800 end
    chamberAlias.getFillLevel = function() return 1800 end
    section = BankInventoryDataSource.collect(snapshot, context)
    sum = 0
    for _, item in ipairs(section.items) do sum = sum + item.quantity end
    equal(sum, 7020)
end)

test("an owned bale in a borrowed baler retains a visible chamber omission", function()
    local snapshot, context = fixture()
    local held = bale(context, "held", 6000)
    local borrowed = vehicle("borrowed", {{fillLevel = 6000, fillType = 1}}, 13)
    borrowed.spec_baler = {fillUnitIndex = 1, hasUnloadingAnimation = true, bales = {{baleObject = held}}}
    context.g_currentMission.itemSystem.items = {held}
    context.g_currentMission.vehicleSystem.vehicles = {borrowed}
    local section = BankInventoryDataSource.collect(snapshot, context)
    equal(#section.items, 0)
    equal(section.coverage.bales, "partial")
    assert(hasIssue(snapshot, "INVENTORY_BALE_CHAMBER_TRANSITION"))
end)

if _G.test == nil then print(string.format("%d inventory tests passed", count)) end
