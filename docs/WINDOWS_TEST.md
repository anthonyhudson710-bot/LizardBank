# Windows validation: 0.0.6

**Audit reset: every Windows result begins UNVERIFIED.** Earlier overall success
reports are retained as feedback, not acceptance evidence. This diagnostic build
covers the complete 0.0.5 asset, finance, history, forecast and score implementation.

Use the [190-scenario matrix](VALIDATION_MATRIX.md) as the inventory. The short
route below produces useful evidence with about **10–15 minutes of active play,
plus map loading**. It is not a promise to exercise every path or a substitute for
the longer seasonal run. Missing assets, unavailable controllers and unobserved
boundaries remain NOT_EXERCISED.

## Preparation

1. Exit FS25, build with `python3 tools/build.py`, and install
   `dist/FS25_LizardBank.zip` in the active game's mods directory, normally
   `Documents\My Games\FarmingSimulator2025\mods`. Documents may be redirected.
   Remove duplicate older copies. Enable version 0.0.6 on each test save.
2. Use a disposable new save and a **whole-folder copy** of an established save.
   Prefer the established copy with a silo, loaded vehicle and some goods or
   livestock already present; do not spend the test building an entire farm.
3. Record the ZIP SHA256, FS25 version, map, other enabled mods, currency/area
   units, days per month and starting native period/day. The startup log records
   available versions, but map/mod/settings context still matters.
4. This validation release defaults to diagnostics **enabled with read tracing**.
   No console setup is required to obtain automatic captures: loading, opening,
   Refresh, settled transactions, save and period transitions supply evidence.
   When the developer console is already available, named markers make review
   easier. `lbDebug off` disables diagnostics; `lbDebug on` enables normal
   diagnostics; `lbDebug trace` enables read tracing; `lbDebug summary` prints
   current coverage. `scripts/BankDebugConfig.lua` can opt out at startup.
5. Preserve `log.txt` from the active FarmingSimulator2025 user directory before
   another launch overwrites it. Keep the original, not only copied warning lines.

The validation layer also runs safe, pure-Lua model/ledger probes once. Their
detached synthetic inputs never change native game time, money or history.
Probe events use `origin="synthetic"` and `SYNTHETIC_*` check IDs; normal observed
events use `origin="runtime"`. A synthetic twelve-period pass is fixture evidence
only and cannot qualify the actual farm or pass the real seasonal scenarios.

## One short route

Perform purchases/sales only on the disposable copies. Compare the **actual**
native cash change; fees, operating charges and different sale channels may make
buy/sell amounts unequal. Pause or use 1x time for comparisons where possible.
Use existing assets if purchasing a new test asset would take too long.

| Approximate time | Normal game action | Evidence and expected result |
| --- | --- | --- |
| 0–2 min | Load the established copy. Open with Right Ctrl+B or the remapped Open Lizard Bank action. Visit Finance, owned equipment and land screens, then Refresh the bank. Optional `lbMark baseline`. | Cash/debt and parcel/equipment counts reconcile with independently viewed screens. Check source/ownership decisions and partial coverage. Native retained rows remain raw, dated slots unverified, first observed period partial. No invented forecast/score. Matrix SNAP, LAND, VEH, FIN, HIST-001. |
| 2–4 min | Borrow one native increment, then repay it. Buy one inexpensive supported consumable and sell a small amount of existing produce if available. Refresh after settling. Optional `lbMark transactions`. | Both loan legs are financing, once each; gross receipts/payments remain separate. Actual cash/debt deltas reconcile. Unknown native category remains unclassified. A sale or operating-cost path not available here stays unexercised. HIST-002..009, FIN-009..012. |
| 4–6 min | Buy then sell one inexpensive implement, or sell an expendable existing one. Lease and return a small implement if affordable. Buy/sell a parcel only if a suitable affordable parcel is immediately available. | Fleet/land ownership updates after each operation. Sale quote has correct source/contents warning; actual capital cash is distinct. Lease/borrowed items never enter owned collateral. VEH-001..006, LAND-003. Deferred land/lease case remains explicit. |
| 6–8 min | Transfer a known small quantity between an existing silo and trailer; Refresh at settled endpoints. If already available, move a bale/pallet into or out of storage and inspect one animal group. | Quantities change location once; native units and ownership caveats persist. Compare native animal count/health and separate reference quote. Do not create absent bales, stores or livestock just to complete this short route. INV-001..008, BALE-001/003/005, ANI-001..003. |
| 8–9 min | Cycle Policy Standard → Strict → Lenient → Standard. Page first/last, Refresh, close/reopen several times; use mouse and keyboard and a controller if connected. Optional `lbMark controls`. | No unexplained economic changes or extra events; all controls reachable, Back returns normal movement. Missing evidence still withholds forecast/score. GUI, LIFE-012, SCORE-001. Controller absence stays unexercised. |
| 9–11 min | If a period boundary is close, let it cross naturally: fast normal time until near midnight, then 1x across midnight and inspect during the first game minute. Otherwise leave this for the extended route. Save normally and wait for the game's completion. Optional `lbValidate saved`. | One adjacent boundary closes correctly; installation period stays partial. Sidecar write is logged against the callback directory, possibly tempsavegame. Check final savegameN contains lizardBankHistory_<farmId>.xml after save completes. HIST-010, SAVE-001. |
| 11–13 min | Quit to menu and reload that save without deliberately advancing it. Open/Refresh; optional `lbValidate reloaded`. | Cash/debt/calendar anchors, gross totals, event count, policy and periods resume once. A clean reload mismatch is a failure to investigate. A logged sidecar write alone is insufficient. SAVE-002/003/016. |
| 13–15 min | Return to menu, load the disposable new save without restarting FS25, open/Refresh, then save once. Optional `lbMark secondSave` and `lbDebug summary`. | New mission/farm/history has no stale values or duplicate hooks; new-save insufficiency explained. Check controls again, then preserve the complete log. LIFE-004/005, SAVE-005, DEBUG-015. |

These time windows are a guide, not a requirement to rush. Loading, shop travel or
map setup can add time. If an action is unavailable, mark its IDs NOT_EXERCISED and
continue; the log analyzer must not translate absence into PASS. A native boundary
not crossed naturally in this route remains untested.

Optional independent comparisons use `lbExpect cash 12345`,
`lbExpect debt 5000`, `lbExpect landCount 2`,
`lbExpect equipmentOwned 3` or `lbExpect animalsCount 20`, replacing numbers
with values just read in native screens. The command records the entered oracle;
it cannot prove the number was read correctly. Do not populate expectations from
the bank's own output. Screenshots or a short note preserve that independent
comparison. Commands are optional: automatic captures still run.

## Turn the log into a reviewable result

On the development machine, with the captured log copied to a suitable location:

```sh
python3 tools/analyze_log.py /path/to/log.txt --output report.md --json report.json
```

Retain the raw log beside the output. Review failure, warning, unavailable and
truncation entries first, then the NOT_EXERCISED catalog inventory. A PASS for a
sum or ownership comparison is **internal consistency for captured inputs**, not
proof that the collector found all assets or matched native UI. A partial or
truncated log cannot establish complete coverage.

Record each manually checked scenario ID, checkpoint/label, independent native
figure, bank figure and outcome. Report the exact actions for discrepancies.
For save problems include the disposable save's sidecar, saved/read anchors and
whether FS25 itself reported completion. Never summarize an untested group as
passed because the report opened.

## Focused follow-ups for uncovered paths

The matrix lists the expected oracle for every case. These routes exercise the
cases that the short route commonly misses.

| Route | Actions and evidence | Matrix IDs |
| --- | --- | --- |
| Ownership and valuation | Borrow equipment through a normal contract; attach/detach an implement; compare empty/loaded trailer sale quotes; buy/sell land. Compare actual owner rather than field access. Inspect a building monetary value, temporary construction refund and native sale restriction. | LAND-001..007; VEH-001..011; PROP-001..009 |
| Goods and handlers | Inspect production storage, custom units, pallet/big bag, mounted tree-planter pallet, physical/virtual object storage, fermenting bale, loader, blower and round/square baler transitions. Refresh after discharge/settling. Verify independent buffers remain. | INV-001..013; BALE-001..012 |
| Animals | Compare several owned husbandry groups, empty barn, names/subtypes and native quote basis. Ride/return a horse or load/unload animals if present; document excluded transport. Raw age/reproduction never acquire invented units. | ANI-001..012 |
| Input and presentation | Remap action twice, test every native input mode, long names/large report, first/last page, localization fallback and return of vehicle/player controls. | LIFE-006/008/009; GUI-001..011 |
| Unsaved changes | Save, transact and change policy, quit without saving, reload. Both native finances and ledger return to saved anchor, without unsaved events. | SAVE-004/015 |
| Missing history | With game closed, remove only the bank sidecar from another disposable copy. Load: new partial history and a clear reason; save recreates it. | SAVE-006 |
| Interrupted observation | On another copy disable the mod, make a normal cash or calendar change, save, then re-enable. Discontinuity must be disclosed. Change days per month through normal settings on a separate branch and wait until effective. | SAVE-007/008; HIST-013/014 |
| Diagnostic controls | Compare diagnostics on/trace/off, a named validation capture, summary, an independently correct expectation and a deliberately wrong expectation. Check label/session attribution and analyzer output, then enter the correct native value again. Check that pure-Lua probes are labeled synthetic. | DEBUG-001..017 |

Real failures caused by unusual mod assets should be captured with their map/mod
identity and native source trace. Missing/throwing accessors, malformed registries,
nonfinite values, XML write failures, disabled engine APIs and arbitrary wrapper
exceptions are primarily **local fixtures**. Do not fill disks, damage active
saves or inject hidden runtime state to manufacture those Windows cases. If no
legitimate native reproduction exists, retain the fixture result and mark engine
coverage NOT_EXERCISED. Passing a fixture does not establish callback timing or
actual GIANTS object shape.

## Extended seasonal qualification

This is the genuine engine path for forecasting and creditworthiness, not part
of the short route. Local twelve-period fixtures remain separate evidence.

1. Start a disposable branch with readable native categories, enough money and
   stock for small sales. Set one day per month through normal settings **before**
   the qualifying run, waiting until the setting takes effect. Confirm logging
   and the current calendar source; do not alter saved complete-period flags.
2. Use the fastest ordinary timescale between boundaries. Slow to 1x shortly
   before midnight, cross naturally and observe the next period within its first
   game minute. Sleeping to morning can miss the opening and must leave a partial
   period. If a boundary was missed, keep the gap and continue until the relevant
   twelve-period window genuinely becomes complete.
3. Make several small, recognizable operating receipts/payments across periods,
   varying their amounts so a seasonal repeat can be distinguished from a flat
   average. Observe normal native interest with debt outstanding. Unknown
   categories are useful evidence of incomplete mapping; never relabel them by
   hand to make a score appear.
4. Save/reload during the run and confirm continuity. Record adjacent boundaries,
   opening cash, closed completeness and the real native **12 → 1** rollover.
   Local cycle labels do not assert a Gregorian year.
5. Initial installation is partial. In the normal case, at least **thirteen
   period boundaries** are needed to leave twelve completed qualifying periods
   behind the current period. Before qualification every mode must explain the
   missing evidence and show no numeric score. Idle waiting does not invent
   operating activity or historical payment behavior.
6. Once evidence qualifies, compare each forecast row with its matching observed
   seasonal slot for the next twelve **full** periods. Current partial activity,
   capital and financing are excluded. Check gross values and annual sums. The
   result is a conditional repeat scenario, not a closing balance or safe payment.
7. Independently recalculate the four displayed score components, weights,
   thresholds, rounded total and band using
   [underwriting-model.md](underwriting-model.md). Compare all modes on unchanged
   evidence: Lenient ≥ Standard ≥ Strict. Check collateral stays separate and
   native-only/provisional scope is visible. Save/reload selected mode.
8. On a separate disposable branch, use ordinary sleep that misses an opening or
   change days per month. Confirm the resulting partial/gap and withholding.
   Keep the healthy branch for comparison.

If native categories, callback timing or legitimate play prevent qualification,
record the blocker and keep FORE-003/004 and SCORE-011 NOT_EXERCISED. Do not claim
real eligible forecast/score validation from the local integration fixture.

## What constitutes acceptance

Use the matrix to identify every applicable supported scenario and the required
kind of evidence. Current local results are recorded in [VALIDATION.md](VALIDATION.md).
A short-route pass means the exercised baseline paths reconciled; it does not
certify the whole feature set. Whole-build acceptance requires resolved failures,
real save/reload and save-switch evidence, correct ownership and financial
reconciliation, native controls, honest unavailable results, and the extended
eligible path if that path is claimed engine-validated. Preserve remaining unknown
or unsupported cases explicitly rather than calling the result universal.
