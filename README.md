# Lizard Bank 0.0.5

A single-player FS25 farm financial report with retained game records, ongoing cash-flow history, seasonal cash scenarios and an explainable creditworthiness model. Asset coverage includes cash, native debt, owned farmland, equipment, buildings, stored-goods quantities and livestock.

Earlier builds have user-reported success through v0.0.4. **This release needs Windows verification.** It observes money movements and writes its own history alongside the normal game save. It does not change money, debt or ownership, or issue loans.

**A new save—and an established save without a verified observed cycle—shows insufficient history.** Native retained records are displayed when readable, but their FS25 dates, padding, ordering and retention window remain unverified. The mod does not turn those unknown slots into invented completed months or an immediate score.

## Install and open

1. Copy **`dist/FS25_LizardBank.zip`** into your FS25 mods folder, normally `Documents\My Games\FarmingSimulator2025\mods`. Keep the ZIP intact and avoid duplicate unpacked copies.
2. Activate **Lizard Bank** when loading a disposable new save or a copy of an existing single-player save.
3. In gameplay, press **Right Ctrl+B**. The **Open Lizard Bank** action can be reassigned in Controls, including to a controller button. Close other menus first.
4. Use **Previous**, **Next**, **Refresh**, **Policy**, and **Back**. Policy cycles Standard → Strict → Lenient. It changes scoring thresholds, never history or evidence requirements. Keyboard/controller menu actions and mouse buttons use the native GUI. Assets refresh on demand; lightweight cash/calendar observation runs once per second and around transactions.

The ZIP filename must stay `FS25_LizardBank.zip`.

## What the figures mean

- **Retained finance:** raw signed native records with original slot keys and category treatment. Unverified slots are not assigned calendar dates, summed as cash flow or treated as proof of a complete history. Compare them with the Finance screen and capture `lbSnapshot` to verify the running game's retained window.
- **Observed history:** gross operating receipts/payments, separate native interest, asset transactions, financing and unclassified movements. Actual before/after cash deltas are recorded; unexplained balance changes become evidence gaps. Each farm retains up to 36 closed periods in `lizardBankHistory_<farmId>.xml` beside its normal save files. The first period is partial. Local cycle numbers begin at installation and follow native periods 1–12; they are not Gregorian years. Saving/reloading requires matching calendar, cash and debt anchors; an unmatched or malformed sidecar starts a partial chain instead of reusing unsupported history.
- **Seasonal forecast:** after twelve consecutive complete, reconciled periods, the scenario repeats each matching seasonal period's operating receipts, payments and native interest. It covers the next twelve full periods and skips the current partial one. It does not forecast capital purchases, borrowing, principal repayments or closing bank balances. One cycle is limited evidence, not a calibrated prediction.
- **Creditworthiness:** a provisional native-data score from 0–100, with component points, formulas, thresholds and reasons. It weights operating cash margin (35), cash buffer (30), native interest coverage (20), and native debt relative to operating cash (15). Assets are separate and add no score points. Missing periods, unresolved gaps, unclassified flows, unknown balances, unobserved interest on outstanding debt or no operating activity withhold the score. Full repayment capacity remains unproven without principal schedules and external obligations. This is an internal simulation policy, not a bureau score, default probability or loan approval.
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

## Windows verification

Start with a disposable new save and a copy of an established save. Reconcile native Finance rows; sell produce, buy inputs, trade assets, borrow/repay and check the observed classifications. Confirm a new save has no invented history or score. Save/reload and load a second save in the same session. Verify the Policy button and normal Back/controller behavior.

Then use a disposable save to observe an initial partial period followed by twelve complete periods, with operating activity, to exercise forecasts and scoring. Do not edit the history file to manufacture eligibility. Unclassified livestock transactions, unknown mod money types, unsupported hooks, calendar skips and changing days per period can prevent a score; these are explicit coverage limits, not poor credit. The full checklist explains accelerated boundary testing and reconciliation.

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

`BankDataSource` coordinates separate asset and retained-finance collectors. `BankHistory` is the pure ledger; its runtime observer and XML store handle game hooks and persistence. `BankUnderwriting` performs deterministic analysis; `BankFinancialReport`/`BankReport` format snapshots and `BankScreen` presents them. `LizardBank:openReport()` remains the common entry point for future physical bank integrations.

See `docs/finance-sources.md`, `docs/history-sources.md`, `docs/underwriting-model.md`, and `docs/VALIDATION.md` in the source workspace for evidence boundaries, scoring policy and test status. Copy or restore the **whole save folder**, including its Lizard Bank sidecars. Deleting a sidecar discards that farm's observed history; it does not change native finances. History stores game financial data locally and is not uploaded.
