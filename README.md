# Lizard Bank 0.0.2

A single-player FS25 financial snapshot. The bank shows current cash, the native loan balance, owned farmland, equipment, building monetary values, and stored-goods quantities, with itemized coverage explanations.

The user confirmed the first build worked in FS25 1.23.1.0. This update adds buildings and stored goods; those additions need Windows verification. It does not change finances, create loans, calculate a credit grade, or write additional savegame data.

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
- **Partial asset subtotal:** known cash, farmland, owned-equipment quotes, and building monetary values. It is not complete farm equity or a credit assessment. Separate inventory values, animals, standing crops, timber, and other liabilities are not assessed. Bales, virtual bale/pallet storage, bunker/ground heaps and unsupported mod storage remain outside quantity coverage.
- **Unavailable:** missing or invalid data remains unavailable. Known zero is displayed as zero; unknown values are omitted from the explicitly partial subtotal.

## Next Windows check

Check a shed/silo/production building against the construction screen, allowing for the temporary undo refund. Check silo and production quantities, then transfer a known amount between a trailer and silo and Refresh. Inspect a pallet/big bag and a leased trailer. Buy/sell a building; save/reload and switch saves. The original cash, land, equipment and window behavior should still work.

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

`BankDataSource` coordinates collection, with `BankPropertyDataSource` and `BankInventoryDataSource` for the new coverage. `BankReport` formats snapshots and `BankScreen` presents them. `LizardBank:openReport()` is the common entry point for future integrations, including a physical bank location. Research references and engine assumptions are recorded in `docs/data-sources.md`, `docs/property-sources.md`, `docs/inventory-sources.md`, and `docs/gui-sources.md`.
