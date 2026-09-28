# Windows test: 0.0.5

**Version 0.0.5 runtime status: pending.** The user reported success through 0.0.4
on 2026-09-27. The first supplied log identifies FS25 1.23.1.0; the second shows
Arkansas 4X without new problem categories in its comparison view. Those overall
confirmations did not retain individual test-case results and do not validate
the new history, persistence, forecasting, or score pipeline.

Local tests exercise explicit engine stubs. They cannot verify native callback
timing, retained-finance layouts, save-directory promotion, or controller focus.
Record results as **Pass**, **Fail**, or **Not exercised**, with evidence.

## Install and record

1. Build with `python3 tools/build.py`; install `dist/FS25_LizardBank.zip` after
   exiting FS25. Use the active game's `mods` directory, normally
   `Documents\My Games\FarmingSimulator2025\mods` (Documents may be redirected).
   Remove older Lizard Bank copies from that directory.
2. Use a disposable new save and a separate copy of an established save. Enable
   version 0.0.5 in each save's mod selection. Keep the originals intact.
3. Record game version, map, active mods, native period/day, days per month,
   currency/area units, and ZIP SHA256. Pause time when comparing figures where
   possible; ordinary operating costs can otherwise change the balance.
4. Open with Right Ctrl+B, or the remapped **Open Lizard Bank** action. Capture
   the initial report and the game's Finance screen before making transactions.

## Financial pipeline checks

| Check | Expected result | Status |
| --- | --- | --- |
| First installation: new save | Cash/assets are available where supported. Observed history begins with a partial current period. No invented older activity, failed payment history, forecast, or score. | Pending |
| First installation: established save | Recoverable native records appear separately from new bank observations. The save's age and native archive slots do not establish twelve complete observed periods. | Pending |
| Retained records | Compare raw amounts/category labels with Finance, recording exact native slot keys and sources from diagnostics. Signs and verified zeros are preserved; missing figures remain unavailable. | Pending |
| Unverified slots | Order, dates, padding and retention window stay explicitly unverified. Slot 1 is not automatically January, yesterday, or a complete month. Record observed UI correspondence without assuming it applies to every save layout. | Pending |
| Operating activity | Sell some stored produce, then buy a supported consumable normally. Gross receipts and payments appear separately even when they offset. Unknown native categories remain unclassified. | Pending |
| Asset transactions | Buy/sell equipment or land. Classified capital receipts/payments are separate from operating earnings; valuation changes alone never become sales revenue. | Pending |
| Native loans | Borrow in Finance, then repay the same amount. Cash/debt match the game; gross financing receipts/payments each retain the movement although final net change is zero. Nested callbacks do not double-count. | Pending |
| Native interest | With native debt outstanding, allow an ordinary interest charge. Recognized interest is separate from principal and operating costs. Unrecognized charges remain unclassified and block eligibility where relevant. | Pending |
| Reconciliation | Opening cash plus all classified/unclassified inflows minus all outflows equals closing observed cash within displayed precision. A missed change creates a gap, not invented balancing revenue. | Pending |
| Refresh / reopening | Refresh and ten open/close cycles do not change money, debt, event counts or totals unless gameplay changed them. Retained records are not replayed as new transactions. | Pending |
| Policy | Mouse, keyboard and controller select Standard, Strict and Lenient through native controls. Thresholds change; source amounts, history counts, evidence requirements and forecast inputs do not. Ineligible farms remain unscored. | Pending |
| Model explanations | Eligible results show component values/formulas, points, policy and reasons. The 0–100 result is a provisional native-data simulation score; external liabilities, actual accounting profit and principal repayment capacity are not presented as verified. | Pending |
| Collateral | Known asset quotes remain separate from repayment scoring. Inventory quantities and separately presented animal values are not silently added to covered assets or operating receipts. | Pending |

For each transaction record cash/debt before and after, native category, bank
classification, event count and gross totals. Fees can make a buy/sell pair
unequal; compare actual charged amounts. An unknown category is evidence of
incomplete coverage, not proof the bank understands that transaction.

## Save, reload, and continuity

History now intentionally persists to `lizardBankHistory_<farmId>.xml` alongside
the native save. Opening the report and changing policy update memory; normal
game saving commits the sidecar. The bank must not edit native finance XML or
change money, debt, ownership, or the calendar.

1. Make known transactions and choose a policy. Save normally, wait for the game's
   completion, then record `lbSnapshot`. Check the sidecar exists in final
   `savegameN`. The save callback may write through `tempsavegame`; do not
   hard-code, move or modify that temporary folder.
2. Reload without deliberately playing forward. Totals, event counts, closed
   periods and policy should resume once, with matching farm/cash/debt/calendar
   anchors. An unexpected anchor mismatch on a clean save/reload is a failure to
   investigate, not successful persistence.
3. Continue playing, save again and reload. New observations replace the saved
   state without appending duplicate transactions.
4. Make another identifiable transaction, exit **without saving**, and reload.
   Native finances and bank history return to the last saved point; unsaved
   events must not survive in the sidecar.
5. Load the other test save from the main menu without restarting FS25. Only its
   farm/history appear; bindings and transaction/save callbacks do not multiply.
   Repeat a transaction/save/reload there.
6. On another disposable copy, disable the mod, make an identifiable money or
   calendar change, and save. Re-enable on the next load. Missing or mismatched
   history restarts partial observation or discloses broken continuity; the bank
   must not silently join disconnected histories.
7. Optional missing-file check: with the game closed, remove only the bank sidecar
   from a disposable copy. Reload; native finances remain intact and bank history
   starts partial. A normal save recreates its sidecar. Do not fabricate amounts
   or complete-period flags to obtain an in-game score.

A sidecar write does not prove the entire native save completed. Final-file
presence and clean reload are required. Disk-full/native-save failures, malformed
XML, missing hooks and unreadable calendar accessors have local failure fixtures
where available. Mark Windows cases **Not exercised** unless a real reproducible
case occurs. Do not damage an active save or inject hidden runtime test state.

## Accelerated seasonal test on a disposable save

Use a simple farm with readable native categories, enough cash, and produce that
can be sold in small batches. Keep other mods minimal for the first run, then
repeat relevant checks on the established modded save.

1. Set one day per month through normal game settings before the qualifying run.
   Wait for the setting to take effect if necessary. Changing days per month
   during tracked history must invalidate comparability.
2. Use the fastest ordinary timescale between boundaries. Slow to 1x shortly
   before midnight, let time cross naturally, and observe the next period during
   its opening minute before accelerating again. Sleeping until morning can miss
   that opening and must not establish a complete period.
3. In several periods, make small known operating sales/payments. Vary their
   amounts so seasonal repetition differs visibly from a flat average. Keep a
   transaction record. Observe native interest if debt is outstanding.
4. At each boundary check native period, monotonic day, closed-period completeness
   and current opening cash. The installation period remains partial. At native
   **12 → 1**, the local cycle increments once; local cycles are not Gregorian years.
5. Continue until the latest twelve closed periods are complete, reconciled and
   classified. Starting with a partial installation period generally requires at
   least **thirteen period boundaries**. Save/reload during the run, then continue
   from the saved observation anchor.
6. Before twelve qualifying periods, every policy withholds a score and explains
   missing evidence. Idle farms do not acquire invented repayment history by
   waiting. Gaps, unclassified transactions and unavailable native cash/debt remain
   visible eligibility blockers.
7. Once eligible, compare each of the next twelve **full** forecast periods with
   its displayed matching observed seasonal source. Receipts, operating payments
   and interest reproduce that source. Capital transactions, financing and the
   current incomplete period are excluded. Sum forecast amounts to check the
   annual total. Cash before principal is not a forecast closing balance or safe
   loan payment.
8. Recalculate score components/total using the displayed formulas and weights.
   For the same eligible evidence, Standard should fall between Lenient and
   Strict; equal scores can be valid at saturated thresholds. Save/reload the
   selected policy and confirm source data stays unchanged.
9. On a separate disposable branch, change days per month or use normal sleep
   that misses a period opening. Confirm gap/partial status and withheld
   assessment. Keep the healthy branch for comparison.

Acceleration exercises actual native transitions. If normal simulation or unknown
categories prevent qualification, record the blocker and mark eligible forecast/
score checks **Not exercised**. Passing local twelve-period fixtures does not
make these Windows checks passed.

## Existing coverage and controls regression

| Check | Expected result | Status |
| --- | --- | --- |
| Load / controls | Version 0.0.5/icon appear without new errors. Open, page, Refresh, Policy and Back work with mouse, keyboard and controller; player controls resume after closing. | Pending |
| Cash / land / equipment | Cash/debt match Finance; only owned land is counted. Owned/leased/borrowed equipment remain distinct, attachments appear once, and quotes disclose included contents. | Pending |
| Buildings | Owned registered placeables appear once; known sale vetoes/unavailable quotes stay disclosed. Sold buildings and stale storage aliases disappear on Refresh. | Pending |
| Goods / bales / object stores | Quantities/units reconcile; transfers change location without duplication. Contract bales and loader proxies stay excluded; unknown virtual stock remains unavailable. | Pending |
| Fermentation / handlers | Current contents/progress match the game; future silage is not invented. Chamber transitions settle after dropping and Refresh. | Pending |
| Livestock | Owned groups/counts and health match the animal screen, including empty supported barns and zero health. Age/reproduction units stay unverified; native reference quotes remain separate from covered assets. | Pending |
| Transport / riding | Transport exclusions remain explicit; ridden horses do not become ordinary equipment. Loaded trailers retain their contents warning. | Pending |
| Unsupported assets | Failed custom getters leave unavailable values and a useful partial report, never invented zeroes. | Pending |
| Multiplayer | Manifest remains single-player only; forced multiplayer loading disables functionality cleanly. | Pending |

## Diagnostics and acceptance

Use `lbSnapshot` to log a fresh report, retained records, ledger capabilities,
save/load notes, reconciliation gaps and model reasons. `lbOpen` is an alternative
when diagnosing bindings. Console setup is optional for ordinary testing. Copy
`log.txt` from the active FarmingSimulator2025 user directory before another
launch overwrites it.

For failures provide the step, expected/actual figures, exact actions, game
version, map/mod names, Finance/report screenshots and log. Include the disposable
save's bank sidecar for persistence failures and whether the game reported save
completion. Report native slot/category keys rather than guessed dates.

Version 0.0.5 passes when observed categories reconcile, loans are not duplicated,
history survives real save/reload and save switches, insufficient evidence
correctly withholds results, the eligible twelve-period forecast/score path is
exercised, and prior coverage/controls have no new errors. Keep untested cases
explicit. GIANTS TestRunner supplements these checks; it cannot establish
financial correctness or persistence continuity.
