-- Pure report presentation. Only the supplied i18n service may call game code.
BankReport = {}
BankReport.LINES_PER_PAGE = 14
BankReport.LINE_COLUMNS = 86

BankReport.ENGLISH = {
    lb_title = "Lizard Bank",
    lb_subtitle = "Farm financial snapshot | Partial coverage",
    lb_summary = "Financial summary",
    lb_farmland = "Owned farmland",
    lb_equipment = "Equipment and implements",
    lb_buildings = "Owned buildings and placeables",
    lb_inventory = "Stored goods and supplies",
    lb_basis = "How to read this report",
    lb_issues = "Coverage issues",
    lb_unavailable = "Unavailable",
    lb_none = "None",
    lb_farm = "Farm: %s (ID %s)",
    lb_date = "Game year %s | Period %s | Game day %s | %s",
    lb_cash = "Cash: %s",
    lb_debt = "Native loan balance: %s",
    lb_landValue = "Known farmland value: %s",
    lb_equipmentValue = "Known owned-equipment sale quotes: %s",
    lb_buildingValue = "Known owned-building monetary value: %s",
    lb_buildingCounts = "Owned placeables: %s | Unvalued: %s | Omitted records: %s",
    lb_buildingItem = "%s (ID %s)",
    lb_buildingDetail = "Game monetary value: %s",
    lb_buildingSaleBlocked = "This placeable currently blocks selling; value is not sale proceeds.",
    lb_noBuildings = "No owned buildings or placeables found.",
    lb_buildingsUnavailable = "Building coverage is unavailable or incomplete. Zero must not be assumed.",
    lb_inventoryCounts = "Containers checked: %s | Verified empty compartments: %s",
    lb_inventoryIssues = "Unavailable records: %s | Excluded containers or compartments: %s",
    lb_inventoryItem = "%s: %s",
    lb_inventoryLocation = "Location: %s | Container: %s",
    lb_inventoryKind = "Storage type: %s",
    lb_inventoryStorage = "Silo or registered storage",
    lb_inventoryProduction = "Production storage",
    lb_inventoryVehicle = "Equipment fill unit",
    lb_inventoryPallet = "Pallet or big bag",
    lb_inventoryUnavailable = "Stored-goods coverage is unavailable. Zero must not be assumed.",
    lb_inventoryNoItems = "No nonempty goods recorded in the containers checked; coverage is partial.",
    lb_inventoryBasis = "Quantities only; no separate inventory value is added to the asset subtotal.",
    lb_inventoryProvenance = "Container ownership does not prove cargo ownership, including contract crops.",
    lb_inventoryMissing = "Bales, virtual bale/pallet storage and unsupported mod storage are omitted.",
    lb_partialAssets = "Known covered assets, including cash (partial): %s",
    lb_area = "Known parcel area: %s",
    lb_landCount = "Owned parcels recorded: %s",
    lb_equipmentCounts = "Owned: %s | Leased: %s | Borrowed: %s",
    lb_unknownLand = "Unvalued parcels: %s | Parcels with unknown area: %s",
    lb_unknownEquipment = "Unvalued owned equipment: %s | Other excluded equipment: %s",
    lb_partialWarning = "Partial coverage: this is not net worth or a credit assessment.",
    lb_landItem = "Parcel %s: %s",
    lb_landDetail = "Area: %s | Game price: %s",
    lb_vehicleItem = "%s | %s",
    lb_vehicleDetail = "Game sale quote: %s",
    lb_vehicleExcluded = "Excluded from owned-equipment value.",
    lb_quoteContents = "Quote may include contents or animals; inventory is not added separately.",
    lb_quoteContentsIncluded = "As-is quote; any bundled contents are included.",
    lb_owned = "Owned",
    lb_leased = "Leased",
    lb_borrowed = "Borrowed",
    lb_unknown = "Ownership unavailable",
    lb_noLand = "No owned farmland found.",
    lb_noEquipment = "No equipment associated with this farm found.",
    lb_landUnavailable = "Farmland coverage is unavailable or incomplete. Zero must not be assumed.",
    lb_equipmentUnavailable = "Equipment coverage is unavailable or incomplete. Zero must not be assumed.",
    lb_noIssues = "No collection issues detected within this build's limited coverage.",
    lb_basisCash = "Cash and native debt are the current active farm balances.",
    lb_basisLand = "Land uses current game-configured parcel prices and total parcel area.",
    lb_basisVehicle = "Equipment uses the game's current sale quote, including specialization changes.",
    lb_basisBuilding = "Buildings use engine monetary values, not temporary construction undo refunds.",
    lb_basisBuildingSale = "Building value does not guarantee a sale is permitted or that proceeds match.",
    lb_basisQuote = "Sale location, condition changes and other mods may change the final proceeds.",
    lb_basisExclusions = "Leased, borrowed and unidentified ownership are excluded from owned assets.",
    lb_basisMissing = "Not separately valued: inventories, animals, crops and timber.",
    lb_basisDebt = "External financing and other liabilities are not included in native debt.",
    lb_basisSubtotal = "Known covered assets sum available cash, land, owned equipment and buildings.",
    lb_basisUnknown = "Unavailable values are omitted from subtotals; a verified zero is shown as zero.",
    lb_basisRefresh = "This is a dated snapshot. Refresh to read changes made since it was captured.",
    lb_basisNoGrade = "No financial history, payment forecast or credit grade is produced in this build.",
    lb_error = "The report could not be refreshed. Close and reopen it, then check log.txt.",
    lb_page = "Page %d / %d",
    lb_refresh = "Refresh",
    lb_previous = "Previous",
    lb_next = "Next",
    lb_back = "Back"
}

local function isNumber(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function BankReport.getText(i18n, key, customEnvironment, ...)
    local value
    if i18n ~= nil and type(i18n.getText) == "function" then
        local ok, result = pcall(i18n.getText, i18n, key, customEnvironment)
        if ok and type(result) == "string" and result ~= key and not result:find("Missing", 1, true) then
            value = result
        end
    end
    value = value or BankReport.ENGLISH[key] or key
    if select("#", ...) > 0 then
        local ok, formatted = pcall(string.format, value, ...)
        if ok then
            return formatted
        end
        return string.format(BankReport.ENGLISH[key] or key, ...)
    end
    return value
end

local function clean(value)
    return tostring(value):gsub("[%c]", " ")
end

local function characters(value)
    local result = {}
    for character in value:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        result[#result + 1] = character
    end
    return result
end

-- Bound physical lines so a large save or long mod name never loses entries.
local function wrap(value)
    local lines, line, length = {}, "", 0
    for word in clean(value):gmatch("%S+") do
        local chars = characters(word)
        if length > 0 and length + #chars + 1 > BankReport.LINE_COLUMNS then
            lines[#lines + 1], line, length = line, "", 0
        end
        if #chars > BankReport.LINE_COLUMNS then
            for _, character in ipairs(chars) do
                if length == BankReport.LINE_COLUMNS then
                    lines[#lines + 1], line, length = line, "", 0
                end
                line, length = line .. character, length + 1
            end
        else
            line = line .. (length > 0 and " " or "") .. word
            length = length + #chars + (length > 0 and 1 or 0)
        end
    end
    lines[#lines + 1] = line
    return lines
end

function BankReport.buildPages(snapshot, i18n, customEnvironment)
    snapshot = snapshot or {}
    local function t(key, ...)
        return BankReport.getText(i18n, key, customEnvironment, ...)
    end
    local function money(value)
        if not isNumber(value) then return t("lb_unavailable") end
        if i18n ~= nil and type(i18n.formatMoney) == "function" then
            local ok, formatted = pcall(i18n.formatMoney, i18n, value, 0, true, false)
            if ok and type(formatted) == "string" then return formatted end
        end
        return string.format("%.0f", value)
    end
    local function area(value)
        if not isNumber(value) then return t("lb_unavailable") end
        if i18n ~= nil and type(i18n.formatArea) == "function" then
            local ok, formatted = pcall(i18n.formatArea, i18n, value, 2)
            if ok and type(formatted) == "string" then return formatted end
        end
        return string.format("%.2f ha", value)
    end
    local function quantity(item)
        if item.quantityStatus == "unavailable" or not isNumber(item.quantity) then
            return t("lb_unavailable")
        end
        if item.unit == "l" and i18n ~= nil and type(i18n.formatVolume) == "function" then
            local ok, formatted = pcall(i18n.formatVolume, i18n, item.quantity, 1)
            if ok and type(formatted) == "string" then return formatted end
        end
        local number = string.format("%.1f", item.quantity)
        if i18n ~= nil and type(i18n.formatNumber) == "function" then
            local ok, formatted = pcall(i18n.formatNumber, i18n, item.quantity, 1)
            if ok and type(formatted) == "string" then number = formatted end
        end
        return number .. " " .. clean(item.unitText or item.unit or t("lb_unavailable"))
    end
    local function known(value)
        return value ~= nil and clean(value) or t("lb_unavailable")
    end
    local function amount(record)
        if type(record) ~= "table" or record.status == "unavailable" then return nil end
        return record.value
    end
    local function total(record, key)
        if type(record) ~= "table" or record.status == "unavailable" then return nil end
        return record[key]
    end
    local pages = {}
    local function section(title, lines)
        local wrapped = {}
        for _, line in ipairs(lines) do
            for _, physicalLine in ipairs(wrap(line)) do
                wrapped[#wrapped + 1] = physicalLine
            end
        end
        for first = 1, #wrapped, BankReport.LINES_PER_PAGE do
            local pageLines = {}
            for index = first, math.min(first + BankReport.LINES_PER_PAGE - 1, #wrapped) do
                pageLines[#pageLines + 1] = wrapped[index]
            end
            pages[#pages + 1] = {title = t(title), text = table.concat(pageLines, "\n")}
        end
    end

    local farm, capturedAt = snapshot.farm or {}, snapshot.capturedAt or {}
    local land, equipment = snapshot.land or {}, snapshot.equipment or {}
    local buildings, inventory = snapshot.buildings or {}, snapshot.inventory or {}
    local landItems, equipmentItems = land.items or {}, equipment.items or {}
    local cash, debt = amount(snapshot.cash), amount(snapshot.debt)
    local landValue, vehicleValue = total(land, "totalValue"), total(equipment, "ownedValue")
    local buildingValue = total(buildings, "totalValue")
    local partialValue, hasValue = 0, false
    -- An array would stop at its first unavailable (nil) member.
    for _, value in pairs({cash = cash, land = landValue, equipment = vehicleValue, buildings = buildingValue}) do
        if isNumber(value) then
            partialValue, hasValue = partialValue + value, true
        end
    end
    local time = t("lb_unavailable")
    if isNumber(capturedAt.dayTime) then
        local minutes = math.floor(capturedAt.dayTime / 60000) % (24 * 60)
        time = string.format("%02d:%02d", math.floor(minutes / 60), minutes % 60)
    end
    section("lb_summary", {
        t("lb_farm", known(farm.name), known(farm.id)),
        t("lb_date", known(capturedAt.year), known(capturedAt.period), known(capturedAt.day), time),
        "",
        t("lb_cash", money(cash)),
        t("lb_debt", money(debt)),
        t("lb_landValue", money(landValue)),
        t("lb_equipmentValue", money(vehicleValue)),
        t("lb_buildingValue", money(buildingValue)),
        t("lb_partialAssets", money(hasValue and partialValue or nil)),
        "",
        t("lb_partialWarning")
    })

    local landKnown = land.status == "available" or land.status == "partial"
    local equipmentKnown = equipment.status == "available" or equipment.status == "partial"
    local landLines = {
        t("lb_landCount", landKnown and tostring(#landItems) or t("lb_unavailable")),
        t("lb_landValue", money(landValue)),
        t("lb_area", area(total(land, "totalAreaHa"))),
        t("lb_unknownLand", known(landKnown and land.unknownValueCount or nil), known(landKnown and land.unknownAreaCount or nil)),
        ""
    }
    if land.status ~= "available" then landLines[#landLines + 1] = t("lb_landUnavailable") end
    if #landItems == 0 and land.status == "available" then landLines[#landLines + 1] = t("lb_noLand") end
    for _, item in ipairs(landItems) do
        landLines[#landLines + 1] = t("lb_landItem", known(item.id), known(item.name))
        landLines[#landLines + 1] = t("lb_landDetail", area(item.areaHa), money(item.value))
        landLines[#landLines + 1] = ""
    end
    section("lb_farmland", landLines)

    local equipmentLines = {
        t("lb_equipmentCounts", known(equipmentKnown and equipment.ownedCount or nil),
            known(equipmentKnown and equipment.leasedCount or nil), known(equipmentKnown and equipment.borrowedCount or nil)),
        t("lb_equipmentValue", money(vehicleValue)),
        t("lb_unknownEquipment", known(equipmentKnown and equipment.unknownValueCount or nil), known(equipmentKnown and equipment.excludedCount or nil)),
        t("lb_quoteContents"),
        ""
    }
    if equipment.status ~= "available" then equipmentLines[#equipmentLines + 1] = t("lb_equipmentUnavailable") end
    if #equipmentItems == 0 and equipment.status == "available" then equipmentLines[#equipmentLines + 1] = t("lb_noEquipment") end
    local ownershipKeys = {owned = "lb_owned", leased = "lb_leased", borrowed = "lb_borrowed", unknown = "lb_unknown"}
    for _, item in ipairs(equipmentItems) do
        equipmentLines[#equipmentLines + 1] = t("lb_vehicleItem", known(item.name), t(ownershipKeys[item.ownership] or "lb_unknown"))
        if item.ownership == "owned" then
            equipmentLines[#equipmentLines + 1] = t("lb_vehicleDetail", money(item.value))
            if item.quoteIncludesContents == true then
                equipmentLines[#equipmentLines + 1] = t("lb_quoteContentsIncluded")
            end
        else
            equipmentLines[#equipmentLines + 1] = t("lb_vehicleExcluded")
        end
        equipmentLines[#equipmentLines + 1] = ""
    end
    section("lb_equipment", equipmentLines)

    local buildingsKnown = buildings.status == "available" or buildings.status == "partial"
    local buildingItems = buildings.items or {}
    local buildingLines = {
        t("lb_buildingCounts", known(buildingsKnown and buildings.ownedCount or nil),
            known(buildingsKnown and buildings.unknownValueCount or nil), known(buildingsKnown and buildings.excludedCount or nil)),
        t("lb_buildingValue", money(buildingValue)),
        t("lb_basisBuilding"), t("lb_basisBuildingSale"), ""
    }
    if buildings.status ~= "available" then buildingLines[#buildingLines + 1] = t("lb_buildingsUnavailable") end
    if #buildingItems == 0 and buildings.status == "available" then buildingLines[#buildingLines + 1] = t("lb_noBuildings") end
    for _, item in ipairs(buildingItems) do
        buildingLines[#buildingLines + 1] = t("lb_buildingItem", known(item.name), known(item.id))
        buildingLines[#buildingLines + 1] = t("lb_buildingDetail", money(amount(item)))
        if item.canBeSold == false then buildingLines[#buildingLines + 1] = t("lb_buildingSaleBlocked") end
        buildingLines[#buildingLines + 1] = ""
    end
    section("lb_buildings", buildingLines)

    local inventoryKnown = inventory.status == "available" or inventory.status == "partial"
    local inventoryLines = {
        t("lb_inventoryCounts", known(inventoryKnown and inventory.sourceCount or nil), known(inventoryKnown and inventory.zeroCount or nil)),
        t("lb_inventoryIssues", known(inventoryKnown and inventory.unknownCount or nil), known(inventoryKnown and inventory.excludedCount or nil)),
        t("lb_inventoryBasis"), t("lb_inventoryProvenance"), t("lb_inventoryMissing"), ""
    }
    local inventoryItems = inventory.items or {}
    if not inventoryKnown then
        inventoryLines[#inventoryLines + 1] = t("lb_inventoryUnavailable")
    elseif #inventoryItems == 0 then
        inventoryLines[#inventoryLines + 1] = t("lb_inventoryNoItems")
    end
    local storageKeys = {storage = "lb_inventoryStorage", production = "lb_inventoryProduction",
        vehicle = "lb_inventoryVehicle", pallet = "lb_inventoryPallet"}
    for _, item in ipairs(inventoryItems) do
        inventoryLines[#inventoryLines + 1] = t("lb_inventoryItem", known(item.fillTypeTitle or item.fillTypeName), quantity(item))
        inventoryLines[#inventoryLines + 1] = t("lb_inventoryLocation", known(item.location), t(ownershipKeys[item.ownership] or "lb_unknown"))
        inventoryLines[#inventoryLines + 1] = t("lb_inventoryKind", t(storageKeys[item.kind] or "lb_unavailable"))
        inventoryLines[#inventoryLines + 1] = ""
    end
    section("lb_inventory", inventoryLines)

    section("lb_basis", {
        t("lb_basisCash"), t("lb_basisLand"), t("lb_basisVehicle"), t("lb_basisQuote"),
        t("lb_basisBuilding"), t("lb_basisBuildingSale"), t("lb_inventoryBasis"),
        t("lb_basisExclusions"), t("lb_basisMissing"), t("lb_basisDebt"),
        t("lb_basisSubtotal"), t("lb_basisUnknown"), t("lb_basisRefresh"), t("lb_basisNoGrade")
    })
    local issueLines = {}
    for _, issue in ipairs(snapshot.issues or {}) do
        -- Diagnostics are data, not format strings; a mod name may contain '%'.
        issueLines[#issueLines + 1] = clean(issue.detail or issue.code or t("lb_unavailable"))
        issueLines[#issueLines + 1] = ""
    end
    if #issueLines == 0 then issueLines[1] = t("lb_noIssues") end
    section("lb_issues", issueLines)
    return pages
end
