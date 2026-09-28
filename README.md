# Lizard Bank 0.0.4

A single-player FS25 financial snapshot. The bank shows current cash, the native loan balance, owned farmland, equipment, building monetary values, stored-goods quantities, and livestock, with itemized coverage explanations.

Earlier builds have user-reported success through v0.0.3. This update adds livestock coverage, which needs Windows verification. It does not change finances, create loans, calculate a credit grade, or write additional savegame data.

## Install and open

1. Copy **`dist/FS25_LizardBank.zip`** into your FS25 mods folder, normally `Documents\My Games\FarmingSimulator2025\mods`. Keep the ZIP intact and avoid duplicate unpacked copies.
2. Activate **Lizard Bank** when loading a disposable new save or a copy of an existing single-player save.
3. In gameplay, press **Right Ctrl+B**. The **Open Lizard Bank** action can be reassigned in Controls, including to a controller button. Close other menus first.
4. Use **Previous**, **Next**, **Refresh**, and **Back**. Keyboard/controller menu actions and mouse buttons use the native GUI. Refresh captures current values; leaving the window open does not continuously rescan your farm.

The ZIP filename must stay `FS25_LizardBank.zip`.

## What the figures mean

- **Cash and native debt:** the active farm's current balances. Other mods' separate financing is outside this build's coverage.
- **Farmland:** current game-configured parcel prices and full parcel area, not just cultivated field area. Permission to work another farm's land does not imply ownership.
- **Equipment:** owned machinery and implements use game-provided sale quotes. Leased and mission equipment are listed separately and excluded from owned-equipment value. Attached implements are counted individually once.
- **Sale quotes:** as-is quotes can include contents or animals. No inventory or animal value is added separately. Selling location, changing condition, and other mods can affect actual proceeds.
- **Buildings/placeables:** the active farm's registered placeables use engine monetary values, excluding temporary construction undo refunds. Value does not guarantee permission to sell or equal final proceeds. A known sale veto is shown separately.
- **Stored goods:** quantities in supported silos, extensions, owned production storage, equipment fill units, and pallets/big bags. Containers belonging to the farm or leased by it are identified; container ownership does not prove title to cargo such as contract crops. No separate inventory money is added, so contents already bundled in asset quotes are not added twice.
- **Bales:** registered physical bales belonging to the active farm, excluding marked contract bales. Fermentation shows current contents and available progress, not future silage. Loader counts and blower quantities that mirror those bales are excluded. During round-baler discharge, an ambiguous chamber quantity is explicitly omitted until the bale is dropped and you Refresh.
- **Bale/pallet stores:** readable real counterparts are counted at the store location once. Virtual entries with no verified quantity interface show their object count and an unavailable quantity. The report does not estimate their contents from capacity or display text.
- **Livestock:** animal groups in supported owned husbandries, with readable counts, health and native reference values (per-animal quote times count, with no additional fee/transport adjustment). Age and reproduction remain unavailable until their native units are verified. Animal values are shown separately and do not increase covered assets. Loaded livestock trailer quotes already include animal value, and modded quotes may vary. Transported animals, ridden horses and unsupported animal systems are outside this section; ridden horses are also excluded from equipment valuation.
- **Partial asset subtotal:** known cash, farmland, owned-equipment quotes, and building monetary values. It is not complete farm equity or a credit assessment. Livestock reference values stay separate; inventory monetary values, standing crops, timber, and other liabilities are not assessed. Bunker/ground heaps, construction stock and unsupported mod storage remain outside quantity coverage.
- **Unavailable:** missing or invalid data remains unavailable. Known zero is displayed as zero; unknown values are omitted from the explicitly partial subtotal.

## Next Windows check

Compare the Livestock pages with the game's animal screen: groups, counts and health. Buy/sell animals and Refresh; check an empty husbandry and save/reload. Compare native reference values using the basis described in the report. Age/reproduction should remain unavailable; `lbSnapshot` can help verify their raw readings in a later build. Confirm livestock values stay outside the covered-assets subtotal.

The full test checklist is in `docs/WINDOWS_TEST.md` in the source workspace. Record the game version, tested map/mods, mismatches, and any `[LizardBank]` messages in `log.txt`.

## Optional diagnostics

With the game's developer console enabled:

- `lbSnapshot` writes a fresh, itemized snapshot and capability information to the game's `log.txt`.
- `lbOpen` opens the bank as a fallback for testing input bindings.

Both commands are available only while this mod is active in single-player. The snapshot contains in-game farm/asset names and financial values. No logs are uploaded automatically. The usual log location is `Documents\My Games\FarmingSimulator2025\log.txt`.

## Development

Run from the source directory:

```sh
python3 tools/validate.py
lua5.1 tests/run.lua
python3 tools/build.py
```

The runtime mod has no dependencies. The local logic tests require a Lua 5.1 interpreter and stub GIANTS APIs; use your interpreter's executable path if it is not named `lua5.1`. Python 3 builds a deterministic ZIP, checks its structure, and prints its SHA-256. The build excludes source tests and tooling.

`BankDataSource` coordinates dedicated property, inventory, stored-object and animal collectors. `BankReport` formats snapshots and `BankScreen` presents them. `LizardBank:openReport()` is the common entry point for future integrations, including a physical bank location. Research references and engine assumptions are recorded in `docs/data-sources.md` and the related source documents under `docs/`.
