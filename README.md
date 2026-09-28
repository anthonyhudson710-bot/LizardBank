# Lizard Bank 0.0.8 — validation build

A single-player FS25 farm financial report with retained game records, ongoing cash-flow history, seasonal cash scenarios and an explainable creditworthiness model. Asset coverage includes cash, native debt, owned farmland, equipment, buildings, stored-goods quantities and livestock.

**Audit reset: all earlier in-game success reports are treated as unverified.** This release adds structured validation throughout the existing financial pipeline. It observes money movements and writes its own history alongside the normal game save. It does not change money, debt or ownership, or issue loans. Debug logging starts automatically in this validation package; `lbDebug off` disables it.

Version 0.0.8 addresses the [September 27 log findings](docs/log-review-2026-09-27.md): exact recurring property-income classification, blank trailing report pages, a history-start fallback blocked by an undispatched callback, and an analyzer false alarm for an absent first-use history file. The tested log was 0.0.6; these fixes still need Windows confirmation. Native loan-hook and loose-bale enumeration support remain unresolved on that setup.

Start with [test.md](test.md) for the complete ordered test run, all **190 validation scenarios**, detailed category/boundary subcases, a code/resource map and the named local-test inventory. [docs/VALIDATION_MATRIX.md](docs/VALIDATION_MATRIX.md) retains the scenario reference. The catalog covers the explicitly listed current contracts; it cannot prove every unknown map/mod combination. **A clean log is not an automatic pass:** missing gameplay paths remain NOT_EXERCISED, unavailable values stay unavailable, and truncated logs remain incomplete.

## Minimal validation run

1. Install this ZIP and load a disposable copy of an established single-player save. Automatic checkpoints begin after initialization and capture changes, GUI activity, transactions, save/reload and period boundaries. A new save alone cannot exercise assets it does not contain.
2. Open/refresh/close the bank, change Policy, borrow/repay, sell some produce and buy inputs. Where already available, trade/lease/return equipment and transfer stock. Save normally, wait for completion, reload, then load a second save. The [short Windows route](docs/WINDOWS_TEST.md) covers roughly 10–15 minutes of active play plus loading; larger scenarios are listed separately.
3. Optionally use `lbMark beforeLoan` / `lbMark afterLoan` for named full checkpoints. `lbValidate final` writes a fresh snapshot, invariant results and coverage summary. `lbExpect cash 123456` compares a native-screen value you checked manually; cash/debt must use unformatted numbers and counts must be whole numbers. Manual observations are labeled user-supplied rather than independently proven.
4. Exit normally and preserve `log.txt` before another launch overwrites it. In the source workspace run:

   ```sh
   python3 tools/analyze_log.py /path/to/log.txt --output validation-report.md --json validation-report.json
   ```

The analyzer separates internal checks, synthetic probes, manual comparisons, transport gaps, failures and unexercised scenarios. It retains failures even if a later observation passes. No log upload occurs automatically.

Logs include raw scalar reads, selected sources, ownership/exclusion decisions, captured items and totals, before/after cash and debt, transaction nesting, XML handle-release results, save readback, resume anchors, forecast sources, scoring gates/formulas, every prepared GUI page and lifecycle events. The analyzer correlates transaction/native-call stages to expose duplicate, orphaned and missing events. This can expose wrong totals and broken assumptions with little manual bookkeeping. It cannot independently verify missing native registries, a truthful manual value, actual visual clipping/controller feel, or an unplayed full seasonal cycle.

Pure ledger/model probes run once in the game's Lua host with **origin=synthetic** and **SYNTHETIC_** check IDs. They touch no mission, time, money or save files and never count as real seasonal/save coverage. Runtime observations use **origin=runtime**. Collection remains observational; debug-only XML readback reads the bank's own sidecar after a save acknowledgement.

For quiet play, use `lbDebug off`. `lbDebug on` enables checkpoints/checks; `lbDebug trace` also logs individual accessor reads; `lbDebug summary` writes coverage. Before rebuilding, defaults and bounded event/byte limits can be edited in `scripts/BankDebugConfig.lua`. Debug captures settle for two seconds and normally occur no faster than every fifteen seconds, with a sixty-second fallback; opening/Refresh/manual commands also capture. Explicit limit notices and a bounded emergency summary reserve prevent silent truncation or unlimited logging. Asset scans add debug overhead on large saves, and the logs contain in-game names and financial figures.

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

With the game's developer console enabled (automatic validation logging does not require it):

- `lbSnapshot` writes a fresh, itemized snapshot and capability information to the game's `log.txt`.
- `lbOpen` opens the bank as a fallback for testing input bindings.
- `lbDebug on|trace|off|summary` controls structured validation.
- `lbValidate [label]` or `lbMark [label]` captures and checks a named checkpoint.
- `lbExpect cash|debt|landCount|equipmentOwned|animalsCount NUMBER` records a comparison with a manually checked native figure. Cash/debt tolerance follows entered display precision: `1000` allows half a currency unit; `1000.00` allows half a cent. Counts must match exactly; incomplete counts remain unavailable.

Commands are available only while this mod is active in single-player. The snapshot contains in-game farm/asset names and financial values. No logs are uploaded automatically. The usual log location is `Documents\My Games\FarmingSimulator2025\log.txt`.

## Development

Run from the source directory:

```sh
python3 tools/validate.py
lua5.1 tests/run.lua
python3 -m unittest discover -s tests -p 'test_*.py'
python3 tools/build.py
```

The runtime mod has no dependencies. The local logic tests require a Lua 5.1 interpreter and stub GIANTS APIs; use your interpreter's executable path if it is not named `lua5.1`. Python 3 builds a deterministic ZIP, checks its structure, and prints its SHA-256. The build excludes source tests and tooling.

`BankDataSource` coordinates separate asset and retained-finance collectors. `BankHistory` is the pure ledger; its runtime observer and XML store handle game hooks and persistence. `BankUnderwriting` performs deterministic analysis; `BankFinancialReport`/`BankReport` format snapshots and `BankScreen` presents them. `LizardBank:openReport()` remains the common entry point for future physical bank integrations.

See `docs/finance-sources.md`, `docs/history-sources.md`, `docs/underwriting-model.md`, and `docs/VALIDATION.md` in the source workspace for evidence boundaries, scoring policy and test status. Copy or restore the **whole save folder**, including its Lizard Bank sidecars. Deleting a sidecar discards that farm's observed history; it does not change native finances. History stores game financial data locally and is not uploaded.
