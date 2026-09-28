# Windows test: 0.0.4

Status: **earlier builds user-confirmed through 0.0.3; 0.0.4 additions pending**.
The confirmations were received on 2026-09-27. The first supplied log identifies
FS25 1.23.1.0; the second shows Arkansas 4X and no new problem categories in its
comparison view. Individual test-case results were not retained. The checklist
below is for this update. Local tests cannot establish in-game behavior.

## Focus for this update

1. Compare owned husbandries and their animal groups with the game's animal
   screen: type, count and health. Age/reproduction are currently unavailable
   because their native units are unverified. Include an
   empty husbandry and an unowned one to check empty versus excluded coverage.
2. Compare native animal reference quotes without additional fee/transport adjustments.
   Group values should equal native per-animal quote times count. These figures
   remain separate and never increase the covered-assets subtotal.
3. Buy/sell animals, then Refresh. Split or merge compatible groups if supported;
   counts must still reconcile without duplicates. Save/reload and switch saves.
4. Load animals into a livestock trailer or ride a horse. The livestock section
   explicitly excludes these cases. A ridden horse must not appear as ordinary
   equipment. A loaded trailer's native equipment quote can include animals.
5. Check existing cash, land, equipment, buildings, goods and bale figures, and
   confirm the window still opens/refreshes/closes normally.

## Install and record

1. Build with `python3 tools/build.py` and use `dist/FS25_LizardBank.zip`.
2. Exit FS25. Copy the ZIP into the active game's `mods` directory, usually
   `Documents\My Games\FarmingSimulator2025\mods`. The Documents folder may be
   redirected by OneDrive. Remove older Lizard Bank copies from that folder.
3. Use a disposable new save and a separate copy of an established save. Enable
   Lizard Bank in each save's mod selection screen.
4. Record FS25 version, map, save age, active mods, selected currency/area units,
   and the ZIP's SHA256 from the build output. Keep game time paused where possible
   when comparing figures so normal operating expenses do not skew results.

## Pass/fail checklist

| Check | Expected result | Status |
| --- | --- | --- |
| Mod selection | Lizard Bank 0.0.4 and its icon appear; save loads without new errors. | Pending |
| Open / close | Right Ctrl+B (remappable Open Lizard Bank action) opens the window; Back/Escape closes it; normal player controls resume. | Pending |
| Controller | Bind Open Lizard Bank in Controls; navigate controls, change report page, Refresh and close without the mouse. | Pending |
| Repeated opening | Ten open/close cycles produce no duplicate input callbacks, stuck controls, or extra windows. | Pending |
| Cash and debt | Figures match the active farm's balance and native finance screen; a verified zero displays as zero. | Pending |
| Land | Owned parcel IDs match the map; total area and configured prices are consistent with the game. Access-only/contract land is absent. | Pending |
| Equipment | Owned, leased, and contract/borrowed entries are distinguished; other farms' and shop preview vehicles are absent. | Pending |
| Valuation | Sale quote is compared at the same moment, location, and condition as the game's quote. Record remote versus workshop sale if they differ. | Pending |
| Attached implements | Tractor plus attached implements each appear once; detaching them does not change ownership totals. | Pending |
| Loaded trailers | Compare empty versus loaded equipment. Included contents are disclosed and are not counted again as separate inventory. | Pending |
| Buildings | Owned registered placeables appear once with monetary values; missing values remain unavailable and known sale vetoes are disclosed. | Pending |
| Livestock groups | Owned husbandry groups/counts match the animal screen; missing metadata or values stay unavailable. Empty supported barns show zero. | Pending |
| Animal condition | Health matches the current game value, including zero. Age/reproduction remain unavailable; optional raw diagnostic readings are not interpreted as percentages or months. | Pending |
| Animal reference value | Native per-animal quotes times count are shown separately, without additional fee/transport adjustments; they do not increase covered assets. | Pending |
| Transport and riding | Deferred coverage is explicit; ridden horses are excluded from equipment; loaded trailer quotes retain their contents disclosure. | Pending |
| Stored goods | Supported storage and fill-unit quantities reconcile, use correct units, and identify the container; leased equipment value is still excluded. | Pending |
| Physical bales | Owned loose/loaded bales appear once with current quantity and type; contract bales are excluded. | Pending |
| Object stores | Stored counterparts appear at the store once; unsupported virtual quantities stay unavailable with known object counts. | Pending |
| Fermentation | Current contents and progress match the game; future silage is not invented. | Pending |
| Bale handlers | Loader/blower proxies do not duplicate bales; round-chamber transitions are disclosed and settle after dropping/Refresh. | Pending |
| Stock transfers | Moving goods between supported containers changes location without duplication; zero and unavailable data remain distinct. | Pending |
| Removal | Sold buildings and removed containers disappear on Refresh, including their lingering storage registry aliases. | Pending |
| Refresh | Borrow/repay; buy/sell equipment and land; lease/return equipment. Each deliberate change appears after Refresh. | Pending |
| Partial coverage | Inventory is quantity-only and livestock reference values are separate; unsupported stock/animals, crops, timber and external finance gaps are visible. No full-net-worth or credit-grade claim. | Pending |
| Save / reload | Save and reload the same game; report matches current finances and does not contain stale items. | Pending |
| Second save | Return to the main menu and load another farm without restarting FS25; report reflects that save only, with one working action binding. | Pending |
| Read-only behavior | Opening or refreshing the report does not move money, change debt/ownership, or add custom savegame files. Normal simulation expenses may continue. | Pending |
| Unsupported data | If a modded vehicle cannot produce a quote, the item is unvalued with a coverage issue; the report still opens and no invented zero is used. | Pending |
| Multiplayer | Mod is not selectable as multiplayer-supported; any forced loading disables the bank functionality cleanly. | Pending |

## Diagnostics and reporting

Use the opt-in `lbSnapshot` console command if a value is wrong or unavailable;
`lbOpen` provides a second way to open the window when diagnosing an input binding.
Developer console setup is optional; ordinary testing does
not require it. After reproducing, exit the game and copy the current `log.txt`
from the active FarmingSimulator2025 user directory before the next launch
overwrites it. The diagnostic contains the financial snapshot and capability
checks; inspect it before sharing if the save contains private names.

For each failure provide: the checklist row, expected and actual values, exact
actions, game version, relevant vehicle/map/mod names, and the associated log.
Attach screenshots of both the game figure and bank figure for mismatches.
Record unavailable-data behavior as **not exercised** when no such item exists;
do not mark it passed based only on stub tests.

This update passes after new coverage reconciles and the existing window and
save lifecycle still work without new errors. Record **not exercised** for
unavailable scenarios. GIANTS TestRunner remains a useful additional check,
not a substitute for runtime results.
