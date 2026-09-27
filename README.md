# Lizard Bank 0.0.1

A single-player FS25 financial snapshot. The bank shows current cash, the native loan balance, owned farmland, and equipment, with itemized values and coverage explanations.

This is the first test build. Local checks do not establish in-game compatibility; Windows validation is pending. It does not change finances, create loans, calculate a credit grade, or write additional savegame data.

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
- **Partial asset subtotal:** only known cash, farmland, and owned-equipment quotes. It is not complete farm equity or a credit assessment. Buildings, separate inventories, animals, standing crops, timber, and other liabilities are not assessed.
- **Unavailable:** missing or invalid data remains unavailable. Known zero is displayed as zero; unknown values are omitted from the explicitly partial subtotal.

## First Windows check

Compare the bank against the game's finance, farmland, and vehicle screens. Then borrow/repay, buy/sell, lease/return, and press Refresh. Check attached implements and a loaded trailer. Save/reload, and load another save in the same session. Open/close the window with both keyboard and controller; gameplay controls must work normally after closing.

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

`BankDataSource` collects evidence, `BankReport` formats it, and `BankScreen` presents it. `LizardBank:openReport()` is the common entry point for future integrations, including a physical bank location. Research references and unverified engine assumptions are recorded in `docs/data-sources.md` and `docs/gui-sources.md`.
