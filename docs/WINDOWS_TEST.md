# First playable Windows test

Status: **pending actual FS25 testing**. Local Lua tests use engine stubs. XML,
resource, and ZIP checks cannot establish in-game behavior, controller navigation,
or whether the current game patch exposes every expected API.

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
| Mod selection | Lizard Bank 0.0.1 and its icon appear; save loads without new errors. | Pending |
| Open / close | Right Ctrl+B (remappable Open Lizard Bank action) opens the window; Back/Escape closes it; normal player controls resume. | Pending |
| Controller | Bind Open Lizard Bank in Controls; navigate controls, change report page, Refresh and close without the mouse. | Pending |
| Repeated opening | Ten open/close cycles produce no duplicate input callbacks, stuck controls, or extra windows. | Pending |
| Cash and debt | Figures match the active farm's balance and native finance screen; a verified zero displays as zero. | Pending |
| Land | Owned parcel IDs match the map; total area and configured prices are consistent with the game. Access-only/contract land is absent. | Pending |
| Equipment | Owned, leased, and contract/borrowed entries are distinguished; other farms' and shop preview vehicles are absent. | Pending |
| Valuation | Sale quote is compared at the same moment, location, and condition as the game's quote. Record remote versus workshop sale if they differ. | Pending |
| Attached implements | Tractor plus attached implements each appear once; detaching them does not change ownership totals. | Pending |
| Loaded trailers | Compare empty versus loaded equipment. Included contents are disclosed and are not counted again as separate inventory. | Pending |
| Refresh | Borrow/repay; buy/sell equipment and land; lease/return equipment. Each deliberate change appears after Refresh. | Pending |
| Partial coverage | Building, animal, inventory, standing crop, timber, and external finance exclusions are visible; report makes no full-net-worth or credit-grade claim. | Pending |
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

The first milestone passes only after both saves reconcile, the lifecycle and
controller checks pass, and newly introduced log errors are resolved. Keep this
file's status pending until real Windows evidence exists. GIANTS TestRunner is a
useful additional check, not a substitute for these runtime checks.
