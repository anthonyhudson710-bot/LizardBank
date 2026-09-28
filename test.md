# Lizard Bank: complete validation run

This is the executable manual runbook for the current **0.0.8** validation build. Start
here. It covers the shipped code, resources, development tools, 190 catalog
scenarios, their boundary/category variants, and every named local test.
Previous reports of success are not acceptance evidence.

**Completion means every applicable row has evidence and every remaining gap is
named.** This is a complete inventory of the current declared behavior, not a
claim of 100% branch coverage, universal compatibility, or mathematical proof.
An arbitrary future map, patch, mod, malformed save or hardware configuration
cannot be certified by one playthrough. Missing fixtures and unplayed paths stay
open; a clean log never fills them in.

## Contents

1. [Evidence rules and preparation](#1-evidence-rules-and-preparation)
2. [Local checks before Windows](#2-local-checks-before-windows)
3. [One efficient gameplay run](#3-one-efficient-gameplay-run)
4. [Asset-specific extensions](#4-asset-specific-extensions)
5. [Persistence and seasonal qualification](#5-persistence-and-seasonal-qualification)
6. [Diagnostic negative tests and log review](#6-diagnostic-negative-tests-and-log-review)
7. [Code and resource ownership](#7-code-and-resource-ownership)
8. [Every catalog scenario](#8-every-catalog-scenario)
9. [Every existing named local test](#9-every-existing-named-local-test)
10. [Closeout and evidence to return](#10-closeout-and-evidence-to-return)

The shortest useful route is section 2 once, then section 3 on existing assets.
Sections 4–6 close uncovered paths. Native lifecycle tests, controller/visual
checks, genuine seasonal history and missing asset types cannot all be replaced
with logging. Do not spend hours creating assets when an existing disposable
save can exercise the same adapter.

## 1. Evidence rules and preparation

### Keep results separate

For each scenario/subcase, record one of:

| Result | Meaning |
| --- | --- |
| PASS | Its actual expected result was checked against the stated oracle. |
| FAIL | Actual behavior contradicts that expectation; keep the original evidence. |
| PARTIAL | Some required subcases passed; list the ones still open. Human record only. |
| UNAVAILABLE | Required native data/device/tool is absent; safe handling can pass independently. |
| NOT_EXERCISED | No evidence for this path. Never infer a pass from related activity. |
| WARN | Something needs review, such as an unsupported source or intentional limitation. |

A low-level logged PASS checks its own predicate only. A synthetic test passing
in the game’s Lua host is still a synthetic test. An entered lbExpect value is
a user-supplied observation, not an independently authenticated native value.
The analyzer intentionally does **not** certify the 190 scenarios automatically.

### Prepare saves and evidence

- [ ] Keep an untouched original; copy the **whole save folder**, including
  lizardBankHistory_<farmId>.xml. Use only disposable copies for purchases,
  deletions, unsaved changes, mod disabling and setting changes.
- [ ] Prepare **A: established**, with as many existing supported assets as
  possible; **B: new**, with no bank history; **C: seasonal**, a disposable branch
  for a complete observed cycle. Use additional copies for destructive fixtures.
- [ ] Install one FS25_LizardBank.zip only. Remove duplicate active versions and
  unpacked copies. Record the selected mod version and archive SHA256.
- [ ] Record game version, map/version, active mods, save label, native farm ID
  if known, currency/units, days per month, starting seasonal period/day,
  input devices, resolution and UI scale. A minimal-mod baseline and the actual
  modded map are separate compatibility runs.
- [ ] Use 1x time around comparisons and pause where the native UI permits.
  Close native screens before opening the bank. Account for time-dependent
  operating charges between observations; do not invent a balancing adjustment.
- [ ] Create an evidence folder outside the game’s active save/mod folders.
  Keep the full original log, screenshots or brief native-value notes, sidecar
  copies, fixture outputs, analyzer outputs and your result ledger there.
- [ ] Do not require a developer console just to start testing. Automatic
  diagnostics are enabled by default. If a console is already available, use
  the commands below to label checkpoints and compare selected values.

Suggested result ledger; copy one row per scenario **and per applicable subcase**:

| ID/subcase | Save/run/checkpoint | Setup/action | Independent expected | Actual | Result | Evidence file/line | Open limitation |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SNAP-001 / getter | A / main / baseline | Native Finance cash, then bank | Enter observed native amount | Enter actual | NOT_EXERCISED | Pending | Display precision/time elapsed |

Optional console commands; replace example amounts with native observations:

~~~text
lbDebug trace
lbMark baseline
lbExpect cash 123456
lbExpect debt 5000
lbExpect landCount 2
lbExpect equipmentOwned 3
lbExpect animalsCount 20
lbValidate final
lbDebug summary
~~~

Cash/debt use unformatted decimal numbers. Enter the precision actually shown:
123456 allows half a currency unit; 123456.00 allows half a cent. Counts must be
nonnegative whole numbers and match exactly. Incomplete counts stay unavailable.
Never copy the bank’s own output into lbExpect as the independent expectation.

### Preserve logs without gaps

Diagnostics currently allow 120,000 ordinary records and 64 MiB per **game
process**, with a bounded emergency reserve. Check [configuration](scripts/BankDebugConfig.lua)
for the artifact being tested. Full snapshots on large farms can consume this
before a long seasonal route finishes. The ordinary line limit is 12,000 bytes;
string/depth/node bounds can also mark individual evidence truncated.

**Changing saves or toggling lbDebug does not reset budgets.** If a limit occurs,
the session is incomplete. Save normally, quit FS25, copy its log before another
launch, then relaunch and verify saved-anchor continuity. For long seasonal
testing, proactively split runs at normal saves and preserve every segment.
Do not disable logging for an interval and later claim that interval was observed.
History tracking is independent of debug mode; an unlogged tracking interval is
still an evidence gap in this audit.

Typical Windows log: Documents\My Games\FarmingSimulator2025\log.txt. Use the
actual game user directory if Documents is redirected. Archive only after the
game has flushed the required events; a still-running log legitimately lacks
mission-end evidence. Never overwrite an earlier log with a later launch.

## 2. Local checks before Windows

Run from the repository root. These are developer checks; the Windows tester
does not need to install Python or Lua just to play and return a log.

~~~sh
python3 tools/validate.py
lua5.1 tests/run.lua
python3 -m unittest discover -s tests -p 'test_*.py'
python3 tools/build.py
~~~

Use the actual Lua **5.1** executable path if it is named differently. Keep each
command’s output and exit status. A missing interpreter or GIANTS TestRunner is
NOT_EXERCISED, not PASS. Do not substitute a synthetic engine for Windows results.

- [ ] All required suites load; no failed tests or zero-test false success.
- [ ] Inspect individual named tests in section 9. The suite’s aggregate count
  does not establish an unasserted matrix boundary.
- [ ] Manifest version matches the bootstrap and catalog; every shipped Lua
  file parses and is declared in dependency order; GUI callbacks/resources and
  English keys resolve. Native inherited behavior still requires Windows.
- [ ] Build twice without edits. Compare printed SHA256 and byte size; verify
  the ZIP root contains modDesc.xml and the expected runtime resources only.
- [ ] Verify the icon in mod selection. DDS header/mip validity alone cannot
  prove recognizable artwork.
- [ ] Run GIANTS TestRunner if available using its supplied instructions.
  Keep its output/version and distinguish native static findings from gameplay.
- [ ] Check this document’s scenario and test inventory against current source
  after any changes; add new behaviors before calling the inventory complete.

Developer fault checks belong in temporary directories or isolated fixtures.
Never damage the installed ZIP or a real save to test validator/XML faults.
The tooling requirements include missing/malformed manifest, mismatched version,
missing/exact-case resources, relative path traversal, symlinks/case collisions,
duplicate/missing localization, missing runtime folders, inherited callback
warnings, and invalid DDS header/dimensions/mips/payload. Also check icon
determinism/unsupported input, package validation failure, exact allowlist and
archive integrity. Record which assertions exist; an unimplemented negative
fixture remains a test gap even if the ordinary build passes.

## 3. One efficient gameplay run

Use A first, B at the end, without restarting until the save-switch test is done.
Allow roughly 15–30 minutes of active play **when suitable assets are already
present**, plus loading. This is baseline evidence, not the complete 190-case run.
Optional markers label settled checkpoints. Opening/Refresh captures immediately;
automatic event captures settle for two seconds, normally coalesce within a
15-second minimum interval, and have a 60-second fallback. Use Refresh after
**each** intermediate state you need to preserve: a fast buy/sell pair could
otherwise be captured only after both operations.

### R01 — Installation, first open and baseline

- [ ] Check the mod’s name, icon, version and single enabled entry in selection.
- [ ] Load A, wait until normal player control, open with Right Ctrl+B or the
  assigned action, and Refresh. Optional marker: baseline.
- [ ] Independently read native Finance cash/debt, owned parcels and garage.
  Record those observations or use the matching lbExpect commands.
- [ ] Compare all owned identities/counts, not just the subtotal. Verify partial
  coverage labels, zero versus unavailable, current game date and farm identity.
- [ ] On a save with no existing accepted sidecar, verify the current observation
  starts partial even when native Finance has old rows. A genuinely resumable
  sidecar is a different case; its prior history must not disappear.
- [ ] Check there is no invented score, repayment capacity or historic payment
  record. Existing eligible history must identify its actual source periods.

Evidence: mission/capture IDs; read and collector decisions; complete snapshot;
source/capability fields; model gates. Independent oracle: native screens.
Covers baseline PKG, LIFE, SNAP, FIN, HIST-001 and insufficient-evidence cases.

### R02 — Controls, denial paths and geometry

- [ ] Click every button; go to first and last pages and attempt one step beyond
  each. Back closes, and movement/driving resumes normally.
- [ ] Reopen, navigate with keyboard only, then controller if available. Confirm
  focus/glyphs and reachability of Back, Previous, Next, Refresh and Policy.
- [ ] Rebind Open Lizard Bank, apply, rebind again, apply. Confirm one press opens
  once; the old binding no longer opens it unless still assigned.
- [ ] With a native menu visible, try the bank binding. If console access allows,
  call lbOpen while a native menu, dialog and the bank itself are visible.
  Expect a reasoned denial and intact native controls. A native context that
  never dispatches the binding is distinct from the API denial test.
- [ ] At **1280×720 render size** and the user’s actual UI scale, inspect the
  longest available page, title, page counter and all buttons. Repeat at another
  supported scale/resolution if relevant. Record the actual rendering size,
  not just the desktop monitor’s resolution. No clipped/unreadable text.
- [ ] Refresh at the last page; shrinking reports clamp to a valid page. Close
  and reopen; the new view starts at page 1. Page navigation alone adds no
  asset scan; allow separately scheduled debug captures when comparing counts.

Logs expose focus-link setup, prepared page text, selected pages, captures,
errors and close/cleanup. They cannot prove pixel geometry, cursor restoration,
physical button response or controller feel. Covers GUI and LIFE-006/008/011.

### R03 — Borrow and repay

- [ ] Read native cash/debt, borrow one native increment, then Refresh immediately.
  Optional marker: borrowed. Record actual cash and debt changes.
- [ ] Repay that increment, Refresh again; marker: repaid.
- [ ] Verify both movements appear once in financing gross flows, with matching
  actual cash/debt deltas. Loan principal is not operating revenue/expense.
- [ ] Inspect nested transaction IDs/native-call counts for duplicate recording.
  A no-op or clamped request records the actual effect, not the requested amount.

Do not assume the round trip restores identical cash if native charges occur
between actions. Attribute those using evidence. Covers HIST-004, SNAP-002,
nativeLoan classification and relevant SAVE continuation later.

### R04 — Operating receipts, costs and retained Finance

- [ ] Sell a small recognizable quantity of existing produce and buy a supported
  consumable such as seed or fertilizer. Capture after each action.
- [ ] Record exact native before/after cash and corresponding Finance rows/signs.
  Gross receipt and expense remain distinct even if their net is zero.
- [ ] Inspect raw retained slot keys, labels and values. Do not equate array
  position with a confirmed month/date or import retained rows into the ledger.
- [ ] At unchanged state, open/Refresh twice: native retained rows do not replay
  transactions or increase observed event count.
- [ ] If unknown native categories occur, retain the unclassified movement and
  eligibility blocker. Do not relabel it just to obtain a score.
- [ ] Other supported money categories are individually listed in section 8.
  One produce sale does not test milk, wood, bales or mission rewards.

Logs carry requested/actual amount, native identity, classification, gross
flows and reconciliation. Native screen readings establish correspondence.
Covers FIN-001/002/009/011/012, HIST-002 and category subcases.

### R05 — Capital transactions and ownership

- [ ] Buy an inexpensive implement, Refresh, sell it, Refresh; or use an expendable
  existing implement and record the missing purchase leg.
- [ ] Attach/detach an implement and Refresh: each registered item appears once.
- [ ] Lease an implement, Refresh, return it, Refresh: it is labeled leased and
  never contributes to owned equipment value.
- [ ] Buy/sell an affordable parcel if available, capturing both owned states.
  Access permission to a contract field never counts as ownership.
- [ ] Compare a native ordinary remote sale quote with the bank’s quote; record
  location/channel, condition and contents. A workshop bonus is another basis.
- [ ] Capital proceeds/purchases remain separate from operations and financing;
  asset appreciation or a changed sale quote does not become cash income.

If funds or assets are absent, continue and retain those legs NOT_EXERCISED;
use an asset-rich disposable save for section 4. Covers LAND/VEH, HIST-003.

### R06 — Quantity transfer and livestock sample

- [ ] With existing silo and trailer, record native amounts, move a known small
  quantity, then Refresh at each settled endpoint. The same material changes
  location once. Account for independent consumption/production/rounding.
- [ ] If already present, inspect a pallet/bale and move it into/out of a store.
  Physical counterparts count once; unreadable virtual quantity stays unknown.
- [ ] If already present, compare one animal group’s count and health, and its
  native per-animal reference quote with the multiplied reference total.
- [ ] Confirm cargo ownership remains qualified, custom units remain correct,
  inventory is not separately valued, and animal references do not inflate
  covered assets or the score.

This samples adapters; section 4 covers other storage/handler/animal variants.
Evidence: identity/location/quantity/unit, ownership/dedup/proxy decisions and
native readings. Covers INV/BALE/ANI baseline.

### R07 — Policy and observational behavior

- [ ] At a quiescent state, record native finances; cycle Standard → Strict →
  Lenient → Standard and Refresh several times.
- [ ] Source balances, ownership and history do not change because of bank
  actions. Explain any native elapsed-time charges separately.
- [ ] Missing evidence withholds results in every mode. With eligible evidence,
  compare policy component thresholds and resulting points, as in section 5.
- [ ] Close/reopen twice, including once while driving. No stuck controls or
  additional money events arise from bank presentation.

Logs distinguish preparation, policy, source snapshots and native transactions;
the native comparison is still required. Covers LIFE-012, GUI-010, SCORE.

### R08 — Save, reload and second save

- [ ] Save A normally; wait for FS25’s completion. Optional marker: saved.
  Record the sidecar in the **final** savegame folder, not only tempsavegame.
- [ ] Return to menu, reload A promptly, open/Refresh. Marker: reloaded.
  Cash, debt, exact calendar anchors, gross events, periods and policy resume
  once. Compare the saved and read sidecar; readback alone is not native completion.
- [ ] Return to menu and load B in the **same process**. Marker: newSave.
  Confirm no A figures/history/GUI pages, duplicate actions or callbacks leak.
- [ ] B has insufficient history with no invented prior events. Save B normally.
- [ ] End the mission normally and exit FS25; preserve its complete log.
  A separate open-screen unload can use normal permitted menu/quit behavior;
  if the game requires closing the screen first, the unavailable variant is
  fixture-only rather than a forced hidden call.

Covers LIFE-002/004/005, SAVE-001/002/003/005/016, HIST-001 and DEBUG session IDs.

## 4. Asset-specific extensions

Use the same refresh-at-each-state pattern; independent observations can be a
short screenshot/note while the log preserves the detailed bank side. Each row
may require a different existing save. Do not mark absent asset types passed.

| Route | Actions and independent observations | Required outcome / log evidence |
| --- | --- | --- |
| A01 Land | Compare several native parcel IDs/whole parcel areas/configured prices; include contracted access-only land, buy/sell and zero-owned save. | Strict owner only, each ID once, configured price source; partial missing data disclosed. |
| A02 Equipment | Owned tractor/implement, attachment, leased item, borrowed contract equipment; complete/return the contract and Refresh. | State labels/counters and inclusion are correct; borrowed/leased excluded from owned totals. |
| A03 Quote contents | Compare empty/loaded grain trailer and, when present, livestock trailer; record ordinary sale channel and native quote before each state. | Whole native quote preserved; contents inclusion disclosed; no separate cargo/animal double value. |
| A04 Excluded vehicles | Observe pallet, big bag, native train and ridden horse representations where present. | They do not become ordinary equipment collateral; supported quantity/animal sections behave independently. |
| A05 Buildings | Owned preplaced and purchased building; compare monetary value and native sale restriction; inspect immediately after construction and later. | Monetary quote excludes temporary undo refund; ownership independent of land access; a sale veto does not become a guaranteed sale. |
| A06 Silos/extensions | Transfer between silo/extension and trailer; inspect storage shared through supported registries. | Correct storage owner and one quantity per source; loading-station totals do not duplicate holdings. |
| A07 Productions | Owned production input/output storage, different goods and a live processing interval. | Actual current holdings only; output forecasts not holdings; ownership/source and simultaneous consumption explained. |
| A08 Fill units | Owned/leased loaded trailers, ordinary independent chambers, pallet/big bag, custom unit where available. | Item/quantity/unit/container state correct; leased container does not imply title to its cargo. |
| A09 Tree planter | Inspect mounted sapling pallet and any independent implement buffer before/after planting. | Same physical pallet not duplicated; independent buffer retained; actual consumption distinguished. |
| A10 Bales | Loose owned bale, another owner’s bale if naturally available, contract bale, fermenting bale at two progress points. | Only supported owned non-contract holdings included; current fill and progress, never invented future silage. |
| A11 Object storage | Move physical bale/pallet through store/loader and out; inspect real counterparts and genuinely virtual entries. | Physical identity once through transitions; unreadable virtual entries expose object count with unavailable quantity. |
| A12 Baler/handler transitions | Round baler before ejection, during discharge and after drop; square baler, loader and blower with actual bales. | Ambiguous round chamber omitted explicitly until settled; proxy mirrors excluded, independent material retained. |
| A13 Animal groups | Empty barn, multiple groups/subtypes, valid zero health, named horse and large group where naturally present. | Known zero differs from unknown; group count and per-animal multiplication once; raw age/reproduction never acquire guessed units. |
| A14 Animals in motion | Buy/sell animals; transport load/unload; ride/return a horse. | Supported husbandry holdings update; excluded transport/riding disclosed; unknown finance purpose stays unclassified. |
| A15 Scope omissions | Inspect bunker/ground heaps, crop fields, timber, construction stock or unsupported mod storage/financing if present. | These do not become invented assessed values; supported-subtotal and business-coverage limitations stay explicit. |

For every applicable asset adapter, section 8 additionally lists numeric extremes,
missing sources, getter exceptions, alias registries and deletion markers. Most
are safer and faster as local fixtures. The correct graceful failure of an
unsupported mod adapter does not validate its holdings.

## 5. Persistence and seasonal qualification

### S01 — Save branches and faults

Use separate whole-folder disposable branches so one deliberate discontinuity
does not contaminate a valid qualifying run.

| Branch | Action | Expected result |
| --- | --- | --- |
| Clean continuation | Save/reload with no intentional time or balance change; repeat after transactions and a policy change. | Accepted exact farm/cash/debt/calendar anchors; gross history and saved policy persist once. |
| Unsaved changes | Save, transact/change policy, quit without saving, reload the saved branch. | Both native finances and bank ledger return to saved state; no unsaved event replay. |
| Missing sidecar | With game closed, remove only the bank sidecar from a disposable copy, then load/save. | Explicit new partial chain; native finances unchanged; normal save recreates bank history. |
| Mod disabled interval | On another branch disable the bank, transact or advance the calendar, save, then re-enable. | Discontinuity disclosed; unsupported interval not reconstructed as complete history. |
| Changed days/month | Change via normal settings; wait until effective. | Comparability gap/reset disclosed; old calendar regime not silently mixed into eligible history. |
| Save-slot/copy isolation | Load complete save copies in different slots and two saves in one process. | Current callback directory/farm used; no cross-save sidecar or cached ledger contamination. |
| Missing/corrupt/failed APIs | Isolated fixtures for malformed XML, wrong farm/version, failed save/read/delete and callback wrappers. | Useful failure and gaps, released handles where possible, unchanged native return/exception semantics. No live-file corruption needed. |

Keep native save completion, callback-time directory, sidecar write acknowledgement,
XML release/readback and subsequent exact resume as **separate** evidence.
A logged successful sidecar write cannot establish final temporary-save promotion.

### S02 — Real seasonal history

This cannot be completed truthfully by an immediate synthetic probe.

1. Use C with bank enabled and readable native cash/calendar/categories. If
   shortening the run, select one day/month through normal settings **before**
   the qualifying observation, and wait for it to take effect.
2. Start with the current partial period. Use ordinary fast time between
   boundaries; return to 1x before midnight, cross naturally and observe within
   the first native game minute. Sleeping to morning or skipping boundaries
   must leave partial/gapped evidence.
3. Make small recognizable operating receipts/payments with varying amounts
   across the cycle. Observe real native interest with outstanding debt.
   Keep recorded stock and cash feasible; do not fabricate economic events.
4. At each boundary capture the closed period and native Finance screen:
   exact labels/slot keys/signs, date context, zero/missing distinctions,
   opening/closing cash, each gross classification and reconciliation.
5. Save/reload during the run and across a native 12 → 1 rollover. Archive every
   log segment before relaunch, with sidecars and the exact continuation chain.
6. Normally at least **13 boundaries** leave 12 full periods after the initial
   partial one. Verify the immediate 12 preceding periods, not just 12 rows.
   No gaps, duplicate dates, unknown gross flows or missing current coverage
   may be silently removed.
7. Before qualification: withheld reasons, no invented score/band. At qualifying
   evidence: inspect source provenance and recompute as below. If legitimate
   native categories remain unknown, insufficient evidence is the right result;
   keep the issue instead of editing the sidecar.
8. For retention beyond one cycle, continue on a separate long-lived branch to
   the 36-period cap; local fixtures test the cap immediately but cannot certify
   that native long-run lifecycle path.

Retained-native Finance-window verification is a **separate longitudinal result**.
Compare successive captures before/after multiple days in one period, adjacent
period boundaries, 12 → 1 and save/reload. Identify which raw slot corresponds
to which actual visible period; observe when old rows actually disappear.
Until enough distinct observations settle ordering, padding, duration and window
length, retain unverified semantics. Never infer a retention window from a single
old save or prefilled zeros; this build does not import those rows into history.

### S03 — Independent calculation sheet

Use raw amounts from archived snapshots/sidecars and native observations, not
only rounded GUI totals. Record each operand and your calculator result.

- Closed cash = opening cash + operating receipts − operating payments −
  native interest + capital inflow − capital outflow + financing inflow −
  financing outflow + unclassified inflow − unclassified outflow.
- Operating cash before interest = annual operating receipts − operating payments.
- Cash before principal = operating cash before interest − native interest.
- Covered asset subtotal = known cash + owned land values + owned equipment
  quotes + building monetary values. Livestock reference values and inventory
  values are not added. Separate collateral excludes cash.
- Animal reference total = verified whole animal count × native per-animal quote,
  without invented transport/fee adjustments.
- Forecast: for each of the next 12 **full** seasonal slots, match its source
  completed seasonal slot, copy operating receipt/payment/interest, recompute
  cash before principal and annual sum. Current partial month is skipped;
  there is no projected closing cash or principal-payment capacity.
- Score components: margin = operating cash / receipts (35 points); cash buffer =
  current cash / ((payments + interest)/12) (30); interest coverage =
  operating cash / interest (20); debt ratio = native debt / operating cash (15).

| Policy | Margin weak → strong | Buffer weak → strong | Interest weak → strong | Debt ratio strong → weak |
| --- | --- | --- | --- | --- |
| Lenient | .02 → .15 | .5 → 3 | 1 → 2 | 2 → 8 |
| Standard | .05 → .20 | 1 → 4 | 1.25 → 3 | 1.5 → 6 |
| Strict | .08 → .25 | 2 → 6 | 1.5 → 4 | 1 → 4 |

For the first three components, multiply weight by
max(0, min(1, (value − weak)/(strong − weak))). For debt ratio, use
max(0, min(1, (weak − value)/(weak − strong))). Round the sum using
floor(sum + 0.5), as specified in [model policy](docs/underwriting-model.md), then check 0–49 strained,
50–74 guarded, 75–100 favorable. Test each boundary through fixtures; do not
engineer a real farm solely to hit a floating-point threshold.

Zero-cost, zero-interest, zero-debt, negative-cash and nonpositive-operating-cash
special cases must follow the explicit policy and emit no infinity/NaN. No
operating activity withholds a score; a complete zero-activity scenario can still
be a limited seasonal repeat. Unobserved interest on outstanding debt withholds
a score. External liabilities, principal schedules and accrual profitability
remain limitations; interest coverage is never described as DSCR.

## 6. Diagnostic negative tests and log review

### D01 — All commands, in a separate labeled run

Keep intentional failures in a dedicated negative-test log. Correcting a value
does not erase its earlier FAIL. Do not weaken the analyzer to obtain a clean run.

- [ ] lbOpen opens through the same entry point as the binding; denial cases
  use the same screen and preserve other menus.
- [ ] lbSnapshot writes a fresh plain itemized DTO and capability snapshot.
  It also works with structured diagnostics off. Its legacy plain output is
  outside the structured logger’s byte/event budget and analyzer check counts;
  use it sparingly, not in a spam loop.
- [ ] lbDebug summary produces cumulative checks/coverage while enabled.
  lbDebug off stops structured diagnostics but not normal bank/history behavior.
  lbDebug on resumes checks without individual read tracing; lbDebug trace
  restores read tracing. No budget resets; the off interval stays unobserved.
- [ ] lbMark namedState and lbValidate namedState create labeled fresh captures.
  If diagnostics were off, these commands intentionally enable normal logging.
- [ ] lbExpect with a native correct value records the correct comparison.
  Deliberately enter one incorrect cash value, then the correct one: the earlier
  failure remains. Record that failure as intentional.
- [ ] Test missing/invalid command arguments; malformed/nonfinite numbers and
  negative/fractional counts receive usage/validation messages, without game
  mutation. Incomplete count data remains UNAVAILABLE, never a proved zero.
- [ ] Normal native updates continue; no extra economic changes arise from
  diagnostics/probes. Trace and quiet modes produce equivalent financial DTOs
  for identical fixture inputs.
- [ ] After unload, mod commands are removed. Multiplayer/dedicated guards and
  command calls before readiness are local fixtures unless naturally reachable.

Use fixtures for log sink exceptions, cycles/metatables, byte/event/line/node
limits, intentionally missing log lines, XML faults and nested native exceptions.
Do not fill a disk, crash the game or inject hidden financial state for coverage.

### D02 — Analyze each preserved log

~~~sh
python3 tools/analyze_log.py /path/to/run-main-log.txt --output /path/to/run-main-report.md --json /path/to/run-main-report.json
~~~

Use different paths for input and outputs. Preserve the original unchanged.
**Exit code 0 means analysis completed, even when checks failed or coverage is
incomplete.** Read the report, not just the command’s exit status.

Review in this order:

1. Artifact/session metadata and the actual actions performed.
2. Native warnings/errors and their attribution; unrelated-mod errors are not
   automatically Lizard Bank failures.
3. Malformed JSON, sequence gaps, incomplete capture/dump/summary, missing
   mission end, logger errors, truncation and exhausted budgets.
4. Sticky runtime FAIL evidence, transaction/native-call lifecycle mismatches,
   save/release/readback failures and model-preparation errors.
5. WARN/UNAVAILABLE decisions and all material history/model blockers.
6. Runtime versus SYNTHETIC_ origin, plus user-entered expectations.
7. Each asset/source/result against its independent observation and each
   arithmetic formula against captured operands.
8. Every row/subcase below, including those the short route did not reach.

The source trace shows what was read and why it was included, rejected or
unvalued. Complete snapshot dumps retain empty containers and item detail.
All prepared report pages can be inspected in the refreshed report-page dump
without manually visiting each page; selected-page traces additionally establish
navigation. Neither establishes how the renderer looked on screen.

The analyzer reports scenario inventory as NOT_EXERCISED until human assessment;
it does not synthesize a completed manual test from a low-level PASS. Retain
separate fixture and Windows outcomes for the same scenario. A fallback that
was never selected remains unexercised even if the preferred source worked.

## 7. Code and resource ownership

The following map accounts for every implementation/resource family. Section 9
lists each test function separately. Static absence of a call is not measured
branch coverage; use a coverage tool if that stronger claim is required.

| Source | Responsibility | Required routes / independent evidence |
| --- | --- | --- |
| scripts/LizardBank.lua | Mission readiness, hooks, commands, shared opener, captures, policy and cleanup | R01–R03/R07–R08, D01; LIFE, GUI, DEBUG; bootstrap fixtures |
| scripts/BankDataSource.lua | Active farm, dates, cash/debt, owned land/equipment, section isolation | R01/R03/R05, A01–A04; SNAP/LAND/VEH |
| scripts/BankPropertyDataSource.lua | Owned buildings, identity, native value and sale restriction | A05; PROP |
| scripts/BankInventoryDataSource.lua | Owned storage, production, fill units and proxy exclusions | R06, A06–A09/A12; INV |
| scripts/BankStoredObjectDataSource.lua | Physical/virtual stored goods, bales and fermentation | A10–A12; BALE |
| scripts/BankAnimalDataSource.lua | Husbandry/group counts, health and separate reference quotes | R06, A13–A14; ANI |
| scripts/BankFinanceDataSource.lua | Native retained candidates, raw rows, bounds and exact category mapping | R04, S02; FIN and each category subcase |
| scripts/BankHistoryRuntime.lua | Native transaction/save wrappers, active farm, actual deltas and sampling | R03–R04/R08, S01–S02; HIST/SAVE |
| scripts/BankHistory.lua | Pure ledger, gross flows, gaps, boundaries, resume and retention | S01–S03; HIST/SAVE fixtures and genuine seasonal run |
| scripts/BankHistoryStore.lua | Save-local XML schema, strict reads/writes, handle release/readback | R08/S01; SAVE |
| scripts/BankUnderwriting.lua | Evidence gate, seasonal source mapping, score/policy and collateral | R07/S02–S03; FORE/SCORE |
| scripts/BankReport.lua | Native formatting, wrapping, pagination, asset/issue text | R01–R02, A01–A15; GUI/SNAP |
| scripts/BankFinancialReport.lua | Finance/history/forecast/score wording and disclosures | R04/R07/S02–S03; GUI/FIN/FORE/SCORE |
| scripts/BankScreen.lua | Native lifecycle/focus, buttons, rendered pages and stale-error replacement | R02/R07–R08; GUI, direct screen fixtures |
| scripts/BankDebugConfig.lua | Startup defaults and bounded timing/log settings | D01–D02; DEBUG bounds and invalid-config fixtures |
| scripts/BankDiagnostics.lua | Structured transport, synthetic isolation, sticky checks, snapshots and scheduling | D01–D02; DEBUG |
| scripts/BankValidation.lua | Independent snapshot/page invariants and cross-capture comparisons | All captures; deliberate malformed DTO fixtures; DEBUG/SNAP/FORE/SCORE |
| scripts/BankValidationCatalog.lua | Declared 190 scenarios; no automatic result promotion | Section 8 parity and report coverage; DEBUG |
| scripts/BankValidationProbes.lua | Safe detached ledger/model probes in host Lua | R01/D02; synthetic-only DEBUG-017 |
| modDesc.xml | Version, load order, action/binding, localization and single-player declaration | Section 2/R01; PKG/LIFE |
| gui/BankScreen.xml; gui/guiProfiles.xml | Resource callbacks, layout and inherited native profiles | Section 2/R02 at actual resolution/scale; GUI/PKG |
| l10n/l10n_en.xml | English keys, formatting placeholders and translation fallback | Section 2/R02; GUI |
| assets/icon.svg; assets/icon.dds | Supported artwork source and generated native icon/mips | Section 2 and native selection; PKG |
| tools/validate.py | Manifest/XML/resources/callbacks/localizations/DDS structural checks | Section 2, temporary-directory negative tooling fixtures |
| tools/make_icon.py | Restricted SVG rasterization and deterministic DXT5 mip chain | Section 2, icon fixtures and native screenshot |
| tools/build.py | Validated exact payload, reproducible ZIP and hash | Section 2, build-failure/allowlist fixtures |
| tools/analyze_log.py | Strict parsing, evidence correlation, report rendering and CLI I/O | D02 and Python parser/CLI fixtures |
| tests/run.lua; tests/test_*.lua; tests/test_*.py | Fixture runner, assertions and isolated test contracts | Section 2 and every named test in section 9; never native certification |
| README.md; docs/*.md; test.md | Installation, supported sources/policy, audit status and procedures | Check links/commands/versions against artifact and code; evidence is not an API contract |
| .gitignore | Excludes build output/caches from source tracking | Inspect source/ZIP inventory; exclusion does not delete or certify user evidence |

Supplemental requirements made explicit here: menu/dialog/open denial; every
console command including legacy output; render-size/scale geometry; process-wide
budget lifecycle; separate intentional-failure logs; native retained-window
longitudinal evidence; tooling negative branches; analyzer CLI/output semantics.
They expand the catalog procedures, without inventing runtime catalog PASS IDs.

## 8. Every catalog scenario

The following rows reproduce all 190 current stable scenarios as individual
checklist entries. The procedure, expected oracle and supporting logs are kept
together so no case requires guessing from a title. Complete the result ledger
for each row and its applicable variants; a checked box alone is not evidence.

<!-- CATALOG_CHECKLIST_START -->

### PKG: Packaging and native loading

Related local checks: [tools/build.py](tools/build.py), [tools/validate.py](tools/validate.py). Their latest execution status is recorded in [VALIDATION.md](docs/VALIDATION.md).

| ID | Scenario | Required evidence / setup | Expected oracle | Log / supporting evidence |
| --- | --- | --- | --- | --- |
| PKG-001 | ☐ Release identity and root archive layout | **structural**. Run build/validator and inspect ZIP names and version fields. | ZIP root contains modDesc.xml; manifest, bootstrap and diagnostics agree on 0.0.8. | Build output, ZIP list, startup version. |
| PKG-002 | ☐ Every declared source and GUI resource exists with exact case | **structural**. Validate sourceFiles, GUI/profile/icon/localization references. | Manifest load order resolves every global dependency; no absent resource or callback. | Validator output, native load errors. |
| PKG-003 | ☐ XML, localization and icon integrity | **structural**. Run local validation; inspect native mod selection icon/title. | XML parses; every lb_* string resolves; icon is valid 512px DXT5 with mipmaps. | Validator output and selection screenshot. |
| PKG-004 | ☐ Deterministic packaging and isolated runtime payload | **structural**. Build twice and compare hashes/list; install only ZIP. | Repeated unchanged builds have identical SHA256; archive includes needed runtime files and no tests, caches or dev tools. | Build hashes and ZIP inventory. |
| PKG-005 | ☐ Clean install without dependencies or stale duplicate copies | **manual**. Install into active mods folder, enable on disposable save, record other mods. | Single enabled Lizard Bank entry loads using only packaged resources. | Full startup log and selected version. |
| PKG-006 | ☐ Native parser and GIANTS TestRunner | **structural**. Run documented local commands and TestRunner if available. | Lua 5.1 parse, resource checks and available TestRunner pass; unavailable TestRunner stays pending. | Exact commands, versions and outputs. |

### LIFE: Mission lifecycle, inputs and integration

Related local checks: [tests/test_bootstrap.lua](tests/test_bootstrap.lua), [tests/test_history_runtime.lua](tests/test_history_runtime.lua). Their latest execution status is recorded in [VALIDATION.md](docs/VALIDATION.md).

| ID | Scenario | Required evidence / setup | Expected oracle | Log / supporting evidence |
| --- | --- | --- | --- | --- |
| LIFE-001 | ☐ Initialization while mission and mode are unavailable | **fixture**. Exercise bootstrap readiness stubs; watch first-ready trace in game. | No farm scan, GUI or observer attaches before ready single-player mission. | Startup readiness and initialization events. |
| LIFE-002 | ☐ Initialize exactly once and capture early load anchor | **manual**. Load a saved ledger; compare startup/resume trace and first checkpoint. | One observer/screen per mission; clean saved anchor resumes before game time advances. | Readiness, hook installation and resume records. |
| LIFE-003 | ☐ Mission with active farm other than ID 1 | **manual**. Use a naturally available non-1 farm/save; otherwise fixture only. | All sections and history use the resolved active farm, never a fixed ID. | Farm ID/source in every checkpoint. |
| LIFE-004 | ☐ Normal unload cleans owned resources | **manual**. Exit to menu with bank open and closed, then load another save. | Inputs, GUI/focus, commands, hooks and cached mission references release; native controls remain usable. | Teardown and next initialization trace. |
| LIFE-005 | ☐ Second save in same process | **manual**. Load new and established saves sequentially without restarting FS25. | Only second save assets/ledger appear; no duplicate actions, transaction events or callbacks. | Checkpoint mission/session IDs, event counts. |
| LIFE-006 | ☐ Remappable action rebuilds without duplicates | **manual**. Rebind Open Lizard Bank, apply twice, test old/new binding. | One press opens once after binding changes; other native bindings still work. | Input registration/removal and open events. |
| LIFE-007 | ☐ Single-player restriction and dedicated-server guard | **fixture**. Inspect manifest and run forced-mode stubs; real MP only if naturally reproducible. | MP/dedicated execution stays inactive and graceful; manifest declares single-player. | Mode/disabled reason, fixture output. |
| LIFE-008 | ☐ GUI initialization failure and focus restoration | **fixture**. Fixture missing/load-failing GUI paths. | Prior GUI focus is restored; no repeated frame retries, leaked controllers or stale report. | Initialization error and cleanup records. |
| LIFE-009 | ☐ Coexistence with later input/load wrappers | **fixture**. Exercise cooperative wrapper fixtures; repeat with actual installed mods when present. | Native behavior and later mod wrappers survive unload; detached observer cannot resurrect. | Wrapper ownership/removal and fixture output. |
| LIFE-010 | ☐ Replacement or unavailable farm object | **fixture**. Fixture same-ID replacement, different ID and missing farm transitions. | Old farm hooks release; replacement resolves dynamically; unavailable farm clears stale report. | Farm-change, hook and gap events. |
| LIFE-011 | ☐ Public openReport and console opener | **manual**. Use binding and lbOpen; exercise direct entry in local stub. | Open action, lbOpen and openReport share one screen and capture contract. | Open origin/capture sequence. |
| LIFE-012 | ☐ Observer and diagnostics preserve game behavior | **manual**. Compare quiescent before/after repeated open/Refresh/Policy with time paused where possible. | Bank actions do not change cash, debt, ownership, calendar or native transaction count. | Before/after snapshots and native Finance readings. |

### GUI: Native window, controls and report presentation

Related local checks: [tests/test_report.lua](tests/test_report.lua). Their latest execution status is recorded in [VALIDATION.md](docs/VALIDATION.md).

| ID | Scenario | Required evidence / setup | Expected oracle | Log / supporting evidence |
| --- | --- | --- | --- | --- |
| GUI-001 | ☐ Mouse navigation and Back/Close | **manual**. Use every button, close and resume movement/driving. | Open, Refresh, Policy, pages and Close respond; cursor and player controls restore. | Open/close/click trace and visual observation. |
| GUI-002 | ☐ Keyboard navigation and remapped open key | **manual**. Navigate without mouse; test Right Ctrl+B and chosen remap. | Focus order reaches all controls; native Back closes; no stuck controls. | Input trace plus manual focus result. |
| GUI-003 | ☐ Controller navigation and action glyphs | **manual**. Use controller through first/last page and close. | Native focus, glyphs, page/Refresh/Policy and Back work on an actual controller. | Manual controller/device evidence. |
| GUI-004 | ☐ Page boundaries and large report completeness | **manual**. Inspect largest available save and local long-report fixture. | Every asset/issue remains reachable; first/last page controls stay focusable; no clipped lines. | Page counts, full checkpoint and screenshots. |
| GUI-005 | ☐ Capture triggers and stale-failure replacement | **runtime**. Compare capture sequence across actions; fixture a capture failure. | Open/Refresh/Policy capture once; page navigation does not scan; failed capture replaces old data. | Capture reasons/counts and report status. |
| GUI-006 | ☐ Native currency, area, volume and custom units | **manual**. Change normal unit/currency settings if available and compare same values. | Displayed formatting matches game settings; custom units are not relabeled liters. | Raw snapshot values/unit labels and screenshots. |
| GUI-007 | ☐ English localization and fallback safety | **fixture**. Run localization fixtures; inspect GUI under installed game language. | Mod-scoped text resolves; missing/malformed translations fall back legibly without crashes. | Localization fixture output, GUI text. |
| GUI-008 | ☐ Long names, mixed IDs and Unicode | **fixture**. Run long/Unicode/mixed-ID report fixtures; inspect naturally long names. | Names wrap within page budget; sorting is deterministic; no source objects leak. | Rendered page strings and screenshots where available. |
| GUI-009 | ☐ Zero, unavailable, partial and excluded wording | **manual**. Compare empty new save, populated save and any unsupported source. | Verified empty/zero differs visibly from unknown; omitted items and limits are stated. | Status fields, issues and displayed labels. |
| GUI-010 | ☐ Policy button cycles using native controls | **manual**. Cycle with mouse, keyboard and controller; compare source figures. | Standard to Strict to Lenient to Standard; only model policy changes; absent evidence never creates score. | Mode changes, assessment reasons and unchanged source data. |
| GUI-011 | ☐ Report release on close and reload | **fixture**. Run screen lifecycle fixture; reopen after save switch. | Screen drops pages/snapshot on close; new mission does not show old report. | Screen lifecycle/capture events. |

### SNAP: Snapshot integrity, finance and coverage

Related local checks: [tests/test_data.lua](tests/test_data.lua), [tests/test_report.lua](tests/test_report.lua). Their latest execution status is recorded in [VALIDATION.md](docs/VALIDATION.md).

| ID | Scenario | Required evidence / setup | Expected oracle | Log / supporting evidence |
| --- | --- | --- | --- | --- |
| SNAP-001 | ☐ Cash getter, fallback and native UI reconciliation | **manual**. Read native Finance and compare lbValidate; optionally lbExpect cash value. | Accepted finite cash equals Finance within native display precision; chosen source is named. | Cash read/decision trace, expectation provenance. |
| SNAP-002 | ☐ Debt getter, fallback and native UI reconciliation | **manual**. Compare Finance before/after borrow and repay; lbExpect debt value. | Accepted finite nonnegative native loan equals Finance; external borrowing is not inferred. | Debt read/decision trace and native loan deltas. |
| SNAP-003 | ☐ Zero and negative cash versus unavailable debt | **fixture**. Run finite/zero/fallback fixtures; natural zero cases if available. | Zero cash/debt and negative cash stay valid; missing, negative debt and nonfinite data stay unknown. | Value/status/source fields. |
| SNAP-004 | ☐ Getter and raw-field disagreement | **fixture**. Inject conflicting getter/field values in local fixtures. | Source precedence stays explicit and diagnostics flag mismatch; no silent averaging. | Getter-field checks and selected source. |
| SNAP-005 | ☐ Dynamic identity and invalid/spectator identities | **fixture**. Fixture missing manager, invalid/spectator IDs and fallback route. | Unresolved farm cannot attribute assets/history; name is optional; no fake farm 1. | Farm source, capabilities and FARM_UNAVAILABLE. |
| SNAP-006 | ☐ Dated detached snapshot and version metadata | **runtime**. Capture then mutate test source objects; inspect live checkpoint metadata. | Farm, raw game date, game/mod/model/schema versions and source metadata accompany plain copied values. | Checkpoint headers, schema and source fields. |
| SNAP-007 | ☐ Calendar source fallback and absent date | **fixture**. Run calendar precedence/absence fixtures. | Monotonic day wins; fallback remains labeled; missing date stays unknown rather than invented Gregorian date. | capturedAt and calendar capability fields. |
| SNAP-008 | ☐ Failure isolation at accessor, record and section | **fixture**. Run throwing/malformed records and whole-section fixtures. | One failed source leaves healthy neighbors and explicit issue; stale successful values are not reused. | Collector failure boundaries, partial statuses. |
| SNAP-009 | ☐ Aggregate arithmetic and overflow | **runtime**. Compare logged item sums and subtotal checks; run overflow fixtures. | Partial sums equal known eligible values; no NaN/infinity or unknown-to-zero conversion. | Arithmetic invariant results and values. |
| SNAP-010 | ☐ Coverage and valuation scope | **manual**. Compare report subtotal to supported item values and disclosures. | Land/equipment/buildings subtotal remains partial; cash, inventory and animal quotes are not double-counted. | Subtotal ingredients and coverage issues. |
| SNAP-011 | ☐ Capture repeatability and no economic writes | **fixture**. Run immutable-source fixtures and side-effect sentinels. | Identical inputs give equivalent detached data; collector calls no mutation APIs. | Fixture output and repeated checkpoint differences. |

### LAND: Owned farmland

Related local checks: [tests/test_data.lua](tests/test_data.lua). Their latest execution status is recorded in [VALIDATION.md](docs/VALIDATION.md).

| ID | Scenario | Required evidence / setup | Expected oracle | Log / supporting evidence |
| --- | --- | --- | --- | --- |
| LAND-001 | ☐ Strict parcel ownership versus access permission | **manual**. Compare map ownership, accessed contract parcel and report. | Only actual active-farm owners count; contractor/access-only land is excluded. | Parcel owner decisions, IDs and native map evidence. |
| LAND-002 | ☐ Parcel identifiers, whole area and configured prices | **manual**. Inspect known parcels in map/native data and bank; do not equate field area with parcel area. | IDs match parcels; area is whole parcel hectares; value is configured current price with source label. | Land item values, source fields and screenshots. |
| LAND-003 | ☐ Buy/sell land refresh and capital movement | **manual**. Buy then sell affordable parcel on disposable save, refresh after each. | Owned list/count updates after transaction; actual cash delta is capital; no stale parcel. | Ownership decisions, transaction and snapshots. |
| LAND-004 | ☐ Duplicate aliases and mixed IDs | **fixture**. Run duplicate/mixed-key registry fixtures. | Same parcel ID counts once; distinct parcels remain separate and deterministically ordered. | Dedup checks and item counts. |
| LAND-005 | ☐ No land versus unavailable enumeration | **fixture**. Run empty/missing registry fixtures. | Verified empty list yields zero; missing manager/list/owner API yields unavailable. | Capabilities, status and total fields. |
| LAND-006 | ☐ Unvalued/unknown-owner/malformed parcel | **fixture**. Run bad ownership, price, area and record fixtures. | Unknown owner omitted explicitly; owned unpriced/unmeasured parcel listed without invented values; healthy parcels survive. | Issues, unknown counters and item statuses. |
| LAND-007 | ☐ Land subtotal numeric limits | **fixture**. Run extreme/negative/nonfinite area-price fixtures. | Finite known item sums are retained; overflowing totals are unavailable. | LAND_TOTAL_OVERFLOW and absent invalid total. |

### VEH: Equipment and implements

Related local checks: [tests/test_data.lua](tests/test_data.lua). Their latest execution status is recorded in [VALIDATION.md](docs/VALIDATION.md).

| ID | Scenario | Required evidence / setup | Expected oracle | Log / supporting evidence |
| --- | --- | --- | --- | --- |
| VEH-001 | ☐ Owned fleet and attached implements count once | **manual**. Compare garage list and attach/detach one implement before Refresh. | Every owned registered machine/implement appears once, attached or detached. | Equipment identities, dedup decisions and counts. |
| VEH-002 | ☐ Leased machines and return | **manual**. Lease inexpensive implement, refresh, return, refresh. | Leased rows are labeled and excluded from owned value; returning removes them. | State decisions, leased count and value subtotal. |
| VEH-003 | ☐ Mission borrowed equipment | **manual**. Accept suitable equipment-borrowing contract on disposable save; inspect/report then return. | Contract/borrowed equipment stays separate and never inflates owned collateral. | Borrowed state, contract screen and subtotal. |
| VEH-004 | ☐ Other farm and unknown ownership | **fixture**. Run ownership fixtures; compare naturally shared/modded assets if present. | Other known owners excluded; unknown owner omitted with issue; access is irrelevant. | Owner checks and omission issues. |
| VEH-005 | ☐ Native sale quote and contents warning | **manual**. Compare garage/workshop sale quote for empty and loaded trailer without assuming sale-channel fees equal. | Quote uses native getSellPrice once; warn contents may be included; do not add stock money. | Read source, quote value, contents flag and quote screenshot. |
| VEH-006 | ☐ Buy/sell and transaction amount versus quote | **manual**. Buy affordable item, compare quote, sell and refresh. | Purchase/sale updates fleet; recorded capital movement equals actual cash delta even if quote/channel differs. | Transaction delta, quote and asset removal. |
| VEH-007 | ☐ Pallet, big bag, train and ridden-horse exclusions | **manual**. Inspect existing pallet/big bag/train and ridden horse when available. | These objects do not become ordinary equipment collateral; goods/riding exclusions remain visible. | Equipment exclusion decisions and inventory/animal coverage. |
| VEH-008 | ☐ Missing enumeration/state constants and unknown property | **fixture**. Run fallback/missing-enum fixtures. | Fallback registry disclosed; absent enum never assumes numeric values; unknown state listed unvalued. | Registry source, capabilities and unknown-state issue. |
| VEH-009 | ☐ Quote failure, zero, all unvalued and empty fleet | **fixture**. Run quote and empty-fleet fixtures. | Zero quote valid; failed/negative/nonfinite quote unknown; all unknown not zero; verified empty is zero. | Quote status, unknown counts and subtotal. |
| VEH-010 | ☐ Deletion, duplicate ID and missing ID | **fixture**. Run registry/deletion/ID fixtures. | Removing object omitted; duplicate identity once; no-ID objects get snapshot-local labels without dropping independent implements. | Dedup/omission events and item list. |
| VEH-011 | ☐ Overflow and custom accessor isolation | **fixture**. Run malformed/throwing/extreme quote fixtures. | Bad custom object does not suppress healthy fleet; overflowing subtotal unknown. | Record errors and subtotal checks. |

### PROP: Buildings and placeables

Related local checks: [tests/test_property.lua](tests/test_property.lua). Their latest execution status is recorded in [VALIDATION.md](docs/VALIDATION.md).

| ID | Scenario | Required evidence / setup | Expected oracle | Log / supporting evidence |
| --- | --- | --- | --- | --- |
| PROP-001 | ☐ Owned registered buildings and production placeables | **manual**. Compare construction/owned production screens and bank. | Only active-farm owned registered placeables appear once; land access is insufficient. | Placeable owner, ID and enumeration trace. |
| PROP-002 | ☐ Engine monetary value and temporary refund distinction | **manual**. Place affordable structure, inspect immediate refund/sale UI and bank value, then inspect later. | Display getMonetaryValue basis, not inferred purchase cost or temporary construction refund. | Value source, quote and native screen evidence. |
| PROP-003 | ☐ Sale veto and unknown eligibility | **manual**. Inspect a native restricted placeable or fixture if unavailable. | canBeSold false/unknown remains advisory; value is never promised net sale proceeds. | Sale eligibility read and caveat. |
| PROP-004 | ☐ Build/sell refresh and removed storage aliases | **manual**. Build/sell affordable empty storage on disposable save and refresh after completion. | Sold placeable disappears; its old stores/counterparts cannot reappear via other registries. | Deletion/alias decisions, property and inventory snapshots. |
| PROP-005 | ☐ Duplicate objects and registered lookup fallback | **fixture**. Run duplicate/fallback fixtures. | Object/unique-ID aliases count once; documented placableByUniqueId fallback is labeled. | Enumeration and duplicate counts. |
| PROP-006 | ☐ Empty versus unavailable buildings | **fixture**. Run empty/missing-system fixtures. | Verified no supported buildings gives zero; absent registry/farm gives unavailable. | Status/count/total fields. |
| PROP-007 | ☐ Zero and invalid/missing monetary values | **fixture**. Run quote validation and healthy-neighbor fixtures. | Zero valid; negative, nonfinite or throwing value leaves explicit unvalued row. | UnknownValueCount and accessor issues. |
| PROP-008 | ☐ Removing/malformed records and unsafe names | **fixture**. Run removal/invalid metadata fixtures. | Deleting and malformed records stay isolated; non-scalar identifiers/names never leak references. | Record issues and detached row output. |
| PROP-009 | ☐ Property total overflow and detached refresh | **fixture**. Run overflow/detachment fixtures. | Overflow unavailable; refresh does not retain old object/value references. | Subtotal checks and fixture output. |

### INV: Stored goods, fill units and attribution

Related local checks: [tests/test_inventory.lua](tests/test_inventory.lua). Their latest execution status is recorded in [VALIDATION.md](docs/VALIDATION.md).

| ID | Scenario | Required evidence / setup | Expected oracle | Log / supporting evidence |
| --- | --- | --- | --- | --- |
| INV-001 | ☐ Silo/extension storage attribution and transfers | **manual**. Compare silo screen; transfer a known amount to trailer and back, refreshing at each settled state. | Contents follow verified storage owner; registry aliases/extension do not duplicate quantity. | Location/fill/unit/owner trace and quantity deltas. |
| INV-002 | ☐ Owned finalized production inventory | **manual**. Compare an existing production inventory and supported purchase/transfer. | Dedicated storage follows owned finalized production; unfinished/nonowned sources excluded. | Production finalization/owner decisions and quantities. |
| INV-003 | ☐ Loaded owned and leased containers | **manual**. Load a known quantity in owned or leased trailer; compare native HUD. | Quantity remains at correct container; leased label shown; cargo title stays unverified even in owned container. | Fill-unit reads, container state and cargo warning. |
| INV-004 | ☐ Pallet/big bag multi-unit stock | **manual**. Compare existing pallet/big bag contents then move/store it. | Every supported unit appears once with its actual fill type/unit; goods are not equipment value. | Unit-level snapshot and exclusion decisions. |
| INV-005 | ☐ Native custom unit and missing fill metadata | **fixture**. Run custom-unit and absent-manager/type fixtures. | Custom unit text retained; known quantity survives absent metadata without inventing liters or crop identity. | unit/unitText/fillType status and issues. |
| INV-006 | ☐ Verified zero versus invalid quantity | **fixture**. Run zero/invalid/throwing fill-unit fixtures. | Empty supported compartments count as zero; missing/negative/nonfinite contents stay unknown. | zeroCount, unknownCount and quantityStatus. |
| INV-007 | ☐ Missing registry and narrow fallback coverage | **fixture**. Run missing storage/placeable/vehicle system fixtures. | Supported direct adapters survive missing generic registry; absent section never claims full inventory coverage. | Coverage by source and registry capability flags. |
| INV-008 | ☐ Cargo ownership and monetary nonduplication | **runtime**. Inspect current snapshot/report and compare owned-assets calculation. | Container ownership never proves cargo title; inventory quantities never add to monetary subtotal. | cargoOwnership, includedInAssetQuote and subtotal checks. |
| INV-009 | ☐ Tree-planter mounted pallet proxy | **manual**. Inspect mounted native planter/pallet if available; missing registry remains fixture-only. | Mounted sapling pallet counted once; planter proxy excluded; missing actual pallet is a gap. | Proxy decisions and missing-pallet issue. |
| INV-010 | ☐ Storage/vehicle deletion signals and stale aliases | **fixture**. Run sold/removing object alias fixtures. | All supported deletion flags/getter paths prevent stale stock; healthy storage remains. | Removal and alias decisions. |
| INV-011 | ☐ Unknown owner/property and borrowed container | **fixture**. Run owner/state/borrowed fixtures. | Unknown owner/state omitted with explicit gap; mission-container stock is excluded. | Ownership decisions and coverage issues. |
| INV-012 | ☐ Quantity source failure isolation and DTO order | **fixture**. Run malformed/accessor/detachment fixtures. | One failed compartment/source leaves neighbors intact; outputs are scalar detached tables in deterministic order. | Collector boundary events and fixture output. |
| INV-013 | ☐ Ground heaps and unsupported crop/timber scope | **manual**. Review report on save with such assets; no inferred financial value. | Ground heaps, standing crops/timber and unsupported stocks stay explicitly outside quantity/asset coverage. | Coverage disclaimer and item inventory. |

### BALE: Bales, stored objects and handling transitions

Related local checks: [tests/test_stored_objects.lua](tests/test_stored_objects.lua), [tests/test_inventory.lua](tests/test_inventory.lua). Their latest execution status is recorded in [VALIDATION.md](docs/VALIDATION.md).

| ID | Scenario | Required evidence / setup | Expected oracle | Log / supporting evidence |
| --- | --- | --- | --- | --- |
| BALE-001 | ☐ Native loose bales and raw/wrapped item registry | **manual**. Inspect existing bale count/contents; compare a loose bale before/after moving. | Real owned registered bales give current fill type/quantity once; unrelated items ignored. | Bale class, registry shape and quantity trace. |
| BALE-002 | ☐ Contract, other-owner and unknown-owner bales | **manual**. Inspect naturally available contract bale; fixture missing owner. | Contract/other-farm bales excluded; unknown title explicitly unavailable, never presumed owned. | Mission/owner exclusion decisions. |
| BALE-003 | ☐ Loaded or unsellable bale remains current quantity | **manual**. Load/unload an existing bale, refresh when settled. | Physical bale on loader is still counted once even if cannot currently be sold. | Bale registration, handler proxy exclusion and quantity. |
| BALE-004 | ☐ Fermentation progress and current crop identity | **manual**. Inspect fermenting and completed bale if available; invalid progress fixture. | Actual current fill type and valid progress shown; future silage quantity/value not invented. | Current fill, fermentation status and source. |
| BALE-005 | ☐ Object storage real counterpart and all aliases | **manual**. Store then retrieve existing supported object, refreshing after each. | Stored bale/pallet counts once at storage location across item/vehicle aliases. | Real-counterpart identity, location and dedup trace. |
| BALE-006 | ☐ Pure virtual and unknown object-storage records | **manual**. Inspect native storage with no readable real counterpart; use fixture if absent. | Known object count retained, unavailable quantity explicit; UI text never parsed into invented liters. | Stored-record shape, count and unknown quantity issue. |
| BALE-007 | ☐ Stored counterpart ownership differs from building | **fixture**. Run counterpart owner and stale-alias fixtures. | Foreign/unknown counterpart is not attributed solely because building is owned; loose aliases remain blocked. | Ownership/block decisions. |
| BALE-008 | ☐ Loader count and straw-blower mirrored fill unit | **manual**. Inspect available loader/blower, including partial consumption. | Handler count/proxy does not duplicate physical bale; independent fuel/buffer contents remain. | Skipped unit reasons and registered bale checks. |
| BALE-009 | ☐ Round baler chamber transition | **manual**. Create/discharge native round bale when feasible; otherwise unexercised. | Transient chamber bale quantity omitted with gap; discharge/settle restores supported quantity without duplication. | Chamber omission and before/after quantity trace. |
| BALE-010 | ☐ Square baler and independent material/buffer | **manual**. Inspect existing square baler/material; fixture if unavailable. | Independent material/buffer remains; round-baler exclusion does not erase square-baler contents. | Per-unit proxy decision and quantity source. |
| BALE-011 | ☐ Missing class/registry, removed storage and bad getters | **fixture**. Run missing registry/class and failure fixtures. | Missing native Bale support differs from verified empty; failures/deletions isolated, no invented stock. | Coverage capabilities, removal and getter errors. |
| BALE-012 | ☐ Shape sampling limits and detached diagnostics | **fixture**. Run capped-shape/detachment fixtures. | Diagnostic samples are capped; native objects/metatables do not escape or execute during serialization. | Explicit sampling/truncation and fixture output. |

### ANI: Husbandry livestock

Related local checks: [tests/test_animals.lua](tests/test_animals.lua). Their latest execution status is recorded in [VALIDATION.md](docs/VALIDATION.md).

| ID | Scenario | Required evidence / setup | Expected oracle | Log / supporting evidence |
| --- | --- | --- | --- | --- |
| ANI-001 | ☐ Owned husbandry groups and current counts | **manual**. Compare animal screen on established save; optionally lbExpect animalsCount value. | Owned registered husbandries/groups match animal screen; every distinct group counted once. | Husbandry owner/group count trace and expectation. |
| ANI-002 | ☐ Native per-animal quote multiplied once | **manual**. Compare group/count and native quote screen, recording UI fees separately. | Reference total equals native unit quote times verified group count; no extra fee/transport deduction. | Unit quote, count, valueSource and total. |
| ANI-003 | ☐ Zero health/count/quote and empty barn | **manual**. Inspect empty supported barn and naturally occurring zero values; fixture unavailable zeros. | Valid zero stays zero; supported empty barn differs from unavailable enumeration. | Health/count/quote statuses and coverage. |
| ANI-004 | ☐ Invalid or missing count and getter precedence | **fixture**. Run count/getter precedence fixtures. | Fractional/negative/nonfinite count unknown; raw numAnimals used only when getter absent, never to hide a failed getter. | Getter/field capability and count issue. |
| ANI-005 | ☐ Missing quote versus known quantity | **fixture**. Run quote failure and healthy-neighbor fixtures. | Known animal counts survive failed quote; no zero valuation is invented. | Unknown-value count and retained count. |
| ANI-006 | ☐ Age/reproduction unverified units | **manual**. Compare report and diagnostic raw fields with native animal screen. | Raw diagnostics stay labeled unverified; no claimed months/percent or fertility projection. | ageRaw/reproductionRaw and capability flags. |
| ANI-007 | ☐ Subtype labels and individual horse names | **manual**. Inspect multiple species/groups and named horse when available. | Native localized label/name preserved; missing metadata uses generic name, not guessed breed. | Subtype key/name source and fallback issue. |
| ANI-008 | ☐ Transport and riding exclusions | **manual**. Load/unload animal or ride/return horse when available. | Loaded/ridden animals explicitly outside husbandry coverage; ridden horse never equipment collateral. | Animal exclusion flags and equipment exclusion. |
| ANI-009 | ☐ Duplicate husbandries/clusters and lookup fallback | **fixture**. Run dedup and registered-lookup fixtures. | Repeated aliases once; separate groups with same attributes stay separate; fallback source named. | Duplicate counters and row identities. |
| ANI-010 | ☐ Unknown owner, failed cluster enumeration and deletion | **fixture**. Run ownership/cluster/deletion malformed fixtures. | Unknown title/removal yields gaps; unreadable husbandry adds unavailable group, not fabricated empty barn. | Group issues and status. |
| ANI-011 | ☐ Health/metadata validation and overflow | **fixture**. Run invalid-health/metadata/extreme count quote fixtures. | Health outside 0..100 unavailable; optional object values sanitized; overflowing values/subtotals unavailable. | Capabilities, overflow issues and scalar rows. |
| ANI-012 | ☐ Animal totals separate and observational behavior | **runtime**. Compare subtotal ingredients and use mutation sentinels in fixture. | Reference quotes never enter covered collateral or operating cash; capture performs no animal/finance updates. | Asset/financial invariant output and source traces. |

### FIN: Retained native finance and category identity

Related local checks: [tests/test_finance.lua](tests/test_finance.lua). Their latest execution status is recorded in [VALIDATION.md](docs/VALIDATION.md).

| ID | Scenario | Required evidence / setup | Expected oracle | Log / supporting evidence |
| --- | --- | --- | --- | --- |
| FIN-001 | ☐ Retained current Finance category reconciliation | **manual**. Compare Finance screen at paused time to named checkpoint. | Raw amounts/signs/zeros and native labels match observed Finance rows; exact source and slot recorded. | finance source, category key, raw value and screenshot. |
| FIN-002 | ☐ Retained history slot semantics stay unverified | **manual**. Record native slot keys alongside UI; inspect labels and model input provenance. | No inferred date/order/retention/padding/completeness from slot index or save age. | Raw slot metadata and verification flags. |
| FIN-003 | ☐ Stats candidate precedence and farm ownership | **fixture**. Run mission/farm stats fallback, mismatch and competing-source fixtures. | Select one narrow supported source; no merging conflicting candidates; wrong farm excluded. | Candidate selection, owner and fallback trace. |
| FIN-004 | ☐ Empty/missing/padded retained buckets | **fixture**. Run empty/missing/padding fixtures. | Empty or zero-padded rows never become complete zero-activity periods. | Bucket availability and unverified status. |
| FIN-005 | ☐ Alias bucket dedup without merging identical independent rows | **fixture**. Run alias and independent-bucket fixtures. | Same object alias once; separate equal-value buckets preserved as distinct raw evidence. | Bucket identity/dedup evidence. |
| FIN-006 | ☐ Missing declarations and invalid amounts/keys | **fixture**. Run malformed metadata/key/value fixtures. | Declared missing values unavailable; nonnumeric/nonfinite amounts and non-scalar keys isolated. | Row status and bounds/shape issues. |
| FIN-007 | ☐ Unknown categories, numeric keys and label failures | **fixture**. Run category/label/malformed label fixtures. | Unknown/case-varied keys remain unclassified; native labels optional; no substring guesses. | Raw key, native label and classification source. |
| FIN-008 | ☐ Retained scan bounds and plain-data export | **fixture**. Run >256 buckets, >512 keys or >8192 records and detached-output fixtures. | Oversized buckets/keys/rows produce explicit truncation; source objects and mutation methods are not used. | Scan-bound issues and included counts. |
| FIN-009 | ☐ Live MoneyType exact identity classification | **runtime**. Inspect each available native mapping in the matrix category subcases; perform known sale/purchase/interest, leaving unobserved categories unexercised. | Recognized native identities map to declared operating/capital/financing/interest policy; no guessed numeric constants. | MoneyType names/raw type, classification and actual delta. |
| FIN-010 | ☐ Unknown/conflicting alias identities | **fixture**. Run exact identity/alias fixtures. | Unknown or conflicting aliases remain unclassified; equality metamethod cannot spoof identity; same-policy aliases coalesce. | Classifier reasons and fixture output. |
| FIN-011 | ☐ Animal and custom finance purpose remains uncertain | **manual**. Buy/sell animal or use known custom transaction if already available. | Unverified-purpose/custom categories remain unknown rather than invented operating/capital certainty. | Raw MoneyType/category and eligibility blocker. |
| FIN-012 | ☐ Retained records never become observed events | **runtime**. Compare event/period counts over unchanged repeated captures. | Opening/reloading archived rows does not replay activity or authorize complete ledger history. | Finance provenance versus observed ledger provenance. |

### HIST: Observed gross financial history and calendar

Related local checks: [tests/test_history.lua](tests/test_history.lua), [tests/test_history_runtime.lua](tests/test_history_runtime.lua). Their latest execution status is recorded in [VALIDATION.md](docs/VALIDATION.md).

| ID | Scenario | Required evidence / setup | Expected oracle | Log / supporting evidence |
| --- | --- | --- | --- | --- |
| HIST-001 | ☐ New and established saves start with partial observation | **manual**. Capture both saves before/after first transactions. | First installed period is partial on both saves; old native rows do not manufacture earlier history. | Initial ledger, first-period completeness and model reasons. |
| HIST-002 | ☐ Gross operating inflow and outflow | **manual**. Sell produce and buy supported consumable; compare actual cash changes. | Actual receipts/payments remain separate even if net zero; no nominal-price substitution. | Before/after cash, category, gross totals and reconciliation. |
| HIST-003 | ☐ Capital movements and valuation independence | **manual**. Perform affordable buy/sell pair and compare ledger. | Equipment/land/building sales and purchases remain capital; quote changes are not revenue. | Capital inflow/outflow and asset quote snapshots. |
| HIST-004 | ☐ Borrow/repay nesting and principal classification | **manual**. Borrow and repay identical native increment; compare both gross legs and event count. | Actual matched cash/debt delta recorded exactly once as financing; repayment not operating expense. | Loan wrapper/native calls, cash/debt deltas and totals. |
| HIST-005 | ☐ Interest expense and refund distinction | **manual**. Observe ordinary native charge; refund edge fixture-only if no natural path. | Recognized negative native interest separate; positive/refunded unknown interest never invented negative expense. | Interest identity/direction and class totals. |
| HIST-006 | ☐ Requested amount versus actual transaction result | **fixture**. Run clamped/no-op/partial native transaction fixtures. | Ledger uses actual before/after delta, not requested amount; zero actual movement adds no event. | Requested and actual delta fields, event count. |
| HIST-007 | ☐ Unexplained cash or debt mutation | **fixture**. Use fixture or naturally reproduced mod conflict; do not inject hidden game state. | Unmatched changes create explicit material gap and withhold eligibility; no balancing fabricated revenue. | Reconciliation/debt-gap events and reason codes. |
| HIST-008 | ☐ Nested ambiguous and failed native transaction | **fixture**. Run nested/error/observer-failure fixtures. | Ambiguous nested money stays unknown; native error rethrown; observer recovers and does not double-execute. | Native-call counts, errors and unclassified totals. |
| HIST-009 | ☐ Exact argument/return preservation | **fixture**. Run wrapper contract fixtures. | Native methods run once with original arguments and nil-containing return tuple; observer failure cannot swallow result. | Contract fixture assertions and hook trace. |
| HIST-010 | ☐ Adjacent native period boundary observed promptly | **manual**. Cross natural midnight at 1x near boundary; inspect within first game minute. | Completed period closes once; next period qualifies only after timely adjacent boundary; installation partial stays partial. | Before/after monotonic day, period, dayTime and completeness. |
| HIST-011 | ☐ Native 12 to 1 local-cycle rollover | **manual**. Cross actual native 12-to-1 boundary during extended run. | Local cycle increments once; no Gregorian-year inference or duplicate seasonal slot. | Cycle/period anchors and closed history. |
| HIST-012 | ☐ Skipped/late/backward calendar transition | **fixture**. Use normal sleep for late case; skipped/backward synthetic paths remain fixtures. | Sleep that misses opening, skipped day/period or rollback cannot compress gaps into complete history. | Calendar discontinuity/gap and eligibility reasons. |
| HIST-013 | ☐ Days-per-period settings change | **manual**. On disposable branch change normal days-per-month setting and wait until effective. | Changed period length invalidates incomparable history and discloses gap. | Old/new daysPerPeriod, retained periods and gap. |
| HIST-014 | ☐ Per-farm continuity and observer capability loss | **fixture**. Run farm/capability-loss fixtures. | Switch/missing farm/calendar/cash/hooks does not reuse previous farm history or claim ongoing complete observation. | Capabilities, active farm and material gaps. |
| HIST-015 | ☐ Cash reconciliation and tolerance boundary | **runtime**. Check each captured current/closed record; fixture inside/outside tolerance. | Opening cash plus all gross signed flows matches closing cash within 0.01; unknown flows cannot net away evidence gap. | Period arithmetic and unknown-flow checks. |
| HIST-016 | ☐ Bounded history/categories/gaps and numeric limits | **fixture**. Run >36 periods, category limit and extreme numeric fixtures. | At most 36 closed periods; bounded categories/gaps; overflow/invalid delta disclosed without nonfinite state. | Counts, overflow/gap markers and fixture output. |
| HIST-017 | ☐ Current partial, zero activity and detached report | **fixture**. Run current/idle/detached state fixtures. | Current period never counted complete; idle period is not failed payment; copied report cannot mutate ledger. | Period statuses and fixture output. |

### SAVE: Sidecar persistence and continuity

Related local checks: [tests/test_history.lua](tests/test_history.lua), [tests/test_history_runtime.lua](tests/test_history_runtime.lua). Their latest execution status is recorded in [VALIDATION.md](docs/VALIDATION.md).

| ID | Scenario | Required evidence / setup | Expected oracle | Log / supporting evidence |
| --- | --- | --- | --- | --- |
| SAVE-001 | ☐ Native save callback writes current directory | **manual**. Save normally, wait for completion; inspect log and final sidecar without moving temporary files. | Sidecar path uses callback-time directory, including tempsavegame, and appears in final savegameN after native success. | Save callback path/write outcome and final-file evidence. |
| SAVE-002 | ☐ Clean save/reload preserves exact observed state | **manual**. Save, quit, reload without deliberate advancement, compare named checkpoints. | Same farm/cash/debt/calendar resumes once, including mode, gross categories, event counts and closed periods. | Saved/read anchors, resume decision and equal totals. |
| SAVE-003 | ☐ Second save cycle and no duplicate observations | **manual**. Transact, save twice, reload and compare counts. | Further transactions saved/reloaded once; repeated save does not duplicate events. | Save sequence, persisted totals and resume checks. |
| SAVE-004 | ☐ Exit without saving discards unsaved bank events | **manual**. On disposable save transact then quit without save and reload. | Native money and bank ledger return to last saved state; Refresh/exit alone writes no sidecar. | Last save/unsaved checkpoint versus reloaded anchor. |
| SAVE-005 | ☐ Cross-save/farm isolation in one game process | **manual**. Switch test saves without restarting; save/reload each. | Each save/farm reads its own sidecar; no stale policy or ledger leaks. | Save paths, farm IDs and mission/session IDs. |
| SAVE-006 | ☐ Missing sidecar | **manual**. With FS25 closed remove only sidecar on a disposable copy, reload and save. | Missing file starts new partial observation with reason; native save remains playable; normal save recreates file. | Missing-file load note and initial partial ledger. |
| SAVE-007 | ☐ Mod disabled during intervening play | **manual**. Disable mod on a copy, change cash/calendar normally, save, re-enable. | Changed anchors prevent silently joining discontinuous history; limitation for identical anchors disclosed. | Anchor mismatch and restart/gap evidence. |
| SAVE-008 | ☐ Restored backup or stale copied sidecar | **fixture**. Use fixture mismatches; whole-folder backups for real play. | Cash/debt/calendar/farm/period-length mismatch rejects continuity; same-anchor hidden edits are not claimed detectable. | Mismatch reason with saved/current anchors. |
| SAVE-009 | ☐ Exact precision and typed XML round trip | **fixture**. Run typed XML round-trip fixture with fractional large values. | 17-digit numeric strings preserve anchors; no float32 rounding or executable serialization. | Written/read fields and equality assertions. |
| SAVE-010 | ☐ Schema, identity, count and ordering validation | **fixture**. Run malformed XML/storage fixtures. | Unsupported schema, invalid identity/count/order/current period are rejected rather than trusted. | Load validation reason and discarded continuity. |
| SAVE-011 | ☐ Period amount/category integrity | **fixture**. Run corrupt period/category fixtures. | Negative/nonfinite amount, duplicate category or invalid class rejected; bad cash reconciliation/gaps cannot manufacture complete evidence. | Load status and completeness/reconciliation. |
| SAVE-012 | ☐ Missing hooks or native XML APIs | **fixture**. Run missing save/XML functions and absent directory fixtures. | Unavailable persistence stated; no successful-save claim or fabricated fallback file path. | Persistence capabilities and lastSave failure. |
| SAVE-013 | ☐ Native save failure and whole-save completion distinction | **fixture**. Run native save failure fixtures; actual fault only if safely reproducible. | Thrown/false native save does not write success; sidecar written never proves final native save completed. | Native result, sidecar result and completion caveat. |
| SAVE-014 | ☐ Create/load/write/delete failure and handle cleanup | **fixture**. Run XML failure fixtures without disk-filling or damaging live save. | Failed/zero handle, false/nil save acknowledgement, exceptions release handles and report failure. | Write/read errors and handle counts. |
| SAVE-015 | ☐ Policy save scope and read-only native data | **manual**. Change policy, save/reload; unsaved-policy branch optional. | Policy persists only with normal game save; bank changes only its own sidecar and never native economic fields. | Mode, save trace and native figures. |
| SAVE-016 | ☐ Save-load hook ordering on real FS25 version | **manual**. Review clean reload trace and final path for both saves. | Load hook resumes before clock movement; real callback directory promotion matches assumptions on recorded game build. | Game version, early-load timing, anchors and save paths. |

### FORE: Seasonal forecast evidence and arithmetic

Related local checks: [tests/test_underwriting.lua](tests/test_underwriting.lua), [tests/test_history_runtime.lua](tests/test_history_runtime.lua). Their latest execution status is recorded in [VALIDATION.md](docs/VALIDATION.md).

| ID | Scenario | Required evidence / setup | Expected oracle | Log / supporting evidence |
| --- | --- | --- | --- | --- |
| FORE-001 | ☐ Insufficient history produces no fabricated forecast | **manual**. Inspect initial checkpoints under all policies. | New/old save without 12 qualifying observed periods shows reasons and no invented seasonal rows. | Forecast status/window/reasons. |
| FORE-002 | ☐ Twelve consecutive complete periods and exact window | **fixture**. Run short/gap/date/duplicate fixtures. | Only 12 immediately preceding complete reconciled periods qualify; arbitrary latest rows/gaps/duplicates do not. | Accepted/rejected window evidence. |
| FORE-003 | ☐ Real engine full seasonal observation | **manual**. Run extended ordinary-time route across at least 13 boundaries. | After initial partial plus 12 complete observed periods, actual native ledger can qualify without injected complete flags. | Boundary/save traces and qualified window. |
| FORE-004 | ☐ Matching-season repeat and horizon | **manual**. On genuinely eligible save compare 12 forecast rows with observed source rows. | Each next full period repeats matching observed slot; current partial omitted; source slot attached. | Forecast rows, source cycle/period and annual sums. |
| FORE-005 | ☐ Gross scenario amounts and excluded flows | **fixture**. Run distinctive seasonal/category fixture. | Project only operating receipts/payments and interest; capital/financing and asset values do not enter seasonal cash. | Projected components and source mapping. |
| FORE-006 | ☐ Material gaps, malformed inputs and cross-farm data | **fixture**. Run financial evidence-gate fixtures. | Unverified coverage, wrong farm/date, unknown flows or overflow withholds scenario; no confident fallback average. | Reason codes and absent numeric scenario. |
| FORE-007 | ☐ Zero activity and limited confidence | **fixture**. Run complete-idle/shorter-window fixtures. | Verified idle cycle may yield zero repeat scenario but no score; shorter data never annualized. | Forecast confidence, observed subtotal and assessment. |
| FORE-008 | ☐ Forecast wording and omitted obligations | **manual**. Inspect forecast on eligible fixture and real eligible save when achieved. | Conditional single-cycle repeat is labeled; no predicted yield/price, ending balance, profit, safe installment or principal coverage. | Assumptions/caveats in report and snapshot. |

### SCORE: Creditworthiness policy and evidence gates

Related local checks: [tests/test_underwriting.lua](tests/test_underwriting.lua). Their latest execution status is recorded in [VALIDATION.md](docs/VALIDATION.md).

| ID | Scenario | Required evidence / setup | Expected oracle | Log / supporting evidence |
| --- | --- | --- | --- | --- |
| SCORE-001 | ☐ No score before evidence gates pass | **manual**. Inspect initial saves and policy cycle. | New, established-only, partial or unavailable data yields no numeric score/band under every policy. | Assessment status, absent score/band and reasons. |
| SCORE-002 | ☐ Complete classified reconciled matching-farm evidence | **fixture**. Run missing/category/date/farm/gap gate fixtures. | 12 consecutive complete periods, all gross categories, verified current cash/debt and clear material coverage required. | Eligibility reasons and accepted period count. |
| SCORE-003 | ☐ Unknown gross inflows/outflows do not cancel | **fixture**. Run offsetting-unclassified fixture. | Equal unknown inflow/outflow still blocks assessment. | Both gross unknown amounts and blocker. |
| SCORE-004 | ☐ Debt with no observed interest and idle year | **fixture**. Run debt-no-interest and idle fixtures. | Positive debt without interest evidence or inactive operating year withholds score; neither gets invented failed grade. | Evidence reasons and absent score. |
| SCORE-005 | ☐ Margin component arithmetic | **fixture**. Recalculate independent fixture cases at/inside/outside thresholds. | 35-point operating margin uses operating cash before interest divided by receipts, bounded by mode thresholds. | Component raw value, thresholds, weight and points. |
| SCORE-006 | ☐ Cash-buffer component arithmetic | **fixture**. Check negative cash, ordinary costs and verified no-cost special case. | 30-point buffer uses current cash divided by mean monthly operating expense plus interest. | Buffer formula/value/special-case/points. |
| SCORE-007 | ☐ Native-interest component arithmetic | **fixture**. Check losses, positive/zero interest and debt evidence boundary. | 20-point interest coverage uses operating cash before interest over native interest; zero-burden case explicit. | Interest formula/value/reasons/points. |
| SCORE-008 | ☐ Native-debt component arithmetic | **fixture**. Check zero/positive debt and nonpositive operating cash cases. | 15-point leverage uses debt over positive operating cash; no debt full points; nonpositive cash flow no infinity. | Debt ratio or special status, thresholds and points. |
| SCORE-009 | ☐ Score rounding, clamping and bands | **fixture**. Recalculate boundary cases including 49/50/74/75 and saturation. | Finite rounded total stays 0..100; >=75 favorable, >=50 guarded, otherwise strained. | Component sum, final score and band. |
| SCORE-010 | ☐ Mode monotonicity and immutable policy thresholds | **fixture**. Run mode ordering and copied-policy fixtures. | Same valid evidence yields Lenient >= Standard >= Strict; returned policy mutation cannot alter future result. | Mode thresholds and score comparisons. |
| SCORE-011 | ☐ Real eligible policy control and persistence | **manual**. After real seasonal qualification, cycle controls and save/reload. | Eligible real ledger displays transparent components; cycling mode changes thresholds only; saved mode resumes. | Mode/source snapshots and saved/read mode. |
| SCORE-012 | ☐ Capital, financing and collateral independence | **fixture**. Run model isolation fixture with controlled evidence. | Borrowing/capital sales/asset appreciation cannot create operating earnings or direct score points; cash/debt effects remain real. | Operating measures, collateral and component inputs. |
| SCORE-013 | ☐ External-liability scope and provisional label | **fixture**. Run options fixture and inspect live native-only default. | Unverified external liabilities make score provisional; suspected material unknown liability withholds score. | Scope flags, provisional status and reasons. |
| SCORE-014 | ☐ Negative cash/loss, invalid values and arithmetic overflow | **fixture**. Run loss/cash/overflow fixtures. | Adverse known figures get explicit reasons; missing/nonfinite/overflow cannot become arbitrary bounded score. | Reason codes and unavailable outputs. |
| SCORE-015 | ☐ No invented underwriting facts or approval | **manual**. Inspect full assessment and explanations. | Score is transparent internal simulation; no bureau/default probability, payment history, accounting profit, DSCR or lending approval claim. | Model version, scope and unavailable obligations. |
| SCORE-016 | ☐ Partial collateral calculation and no stale figures | **runtime**. Compare subtotal/debt ratio to supported values and run stale-value fixture. | Known land/equipment/building quotes separate; inventory/animal/cash duplication excluded; unavailable stale values ignored. | Collateral inputs/status and invariants. |

### DEBUG: Validation instrumentation and analysis

Related local checks: [diagnostic transport](tests/test_diagnostics.lua), [collector diagnostics](tests/test_collector_diagnostics.lua), [history diagnostics](tests/test_history_diagnostics.lua), [independent invariants](tests/test_validation.lua), and [log analyzer](tests/test_analyze_log.py). Their latest execution status is recorded in [VALIDATION.md](docs/VALIDATION.md).

| ID | Scenario | Required evidence / setup | Expected oracle | Log / supporting evidence |
| --- | --- | --- | --- | --- |
| DEBUG-001 | ☐ Validation-release startup configuration | **manual**. Launch defaults, disable/re-enable, reload with config false on disposable install if needed. | 0.0.8 begins enabled with read tracing; config false or lbDebug off stops diagnostic work without disabling bank. | Configuration/mode transitions and quiet period. |
| DEBUG-002 | ☐ Diagnostic commands and invalid input | **manual**. Run each command and invalid mode/empty label variants. | lbDebug on/trace/off/summary, lbValidate label and lbMark label respond without crashing; malformed args are rejected/useful. | Command responses and labeled checkpoints. |
| DEBUG-003 | ☐ Automatic capture reasons and bounded frequency | **runtime**. Follow short route and inspect capture reason/count over idle interval. | First-ready/open/Refresh/save/reload/settled transaction/boundary captures are attributable and coalesced, not per-frame full scans. | Capture sequence/reasons/timing and limits. |
| DEBUG-004 | ☐ Read provenance, classification and exclusion evidence | **runtime**. Inspect representative successful, missing and excluded source traces; use fixtures for faults. | Trace identifies attempted accessor/field, type/status, fallback and include/exclude reason without extra economic reads. | Read and decision events with source and reason. |
| DEBUG-005 | ☐ Full snapshot schema and explicit truncation | **runtime**. Inspect ordinary checkpoint and oversized local fixture. | Bounded checkpoint serialization includes available values/statuses; exceeding limits emits explicit truncation, never silently claims completeness. | Snapshot records, budgets, truncation markers. |
| DEBUG-006 | ☐ Manual expectation comparisons | **manual**. Enter one correct native value and one deliberately wrong expectation, then enter the correct value again; retain each checkpoint result. | lbExpect cash/debt/landCount/equipmentOwned/animalsCount records independently read UI value and compares it; user entry is not proof UI correct. | Metric, expected/actual, provenance and result. |
| DEBUG-007 | ☐ Scenario catalog completeness accounting | **runtime**. Generate summary for empty and populated saves and review missing groups. | Every catalog ID remains visible with NOT_EXERCISED until warranted evidence; absent asset/path is not automatic PASS. | Catalog IDs, statuses and coverage counts. |
| DEBUG-008 | ☐ Internal invariant PASS versus native accuracy | **manual**. Review analyzer output against manual matrix evidence. | Arithmetic/source agreement checks never certify unseen game UI, assets, long periods or arbitrary mod compatibility. | Result scope/provenance and unexercised list. |
| DEBUG-009 | ☐ Failure visibility and diagnostic self-protection | **fixture**. Run failing serializer/sink/check fixture where implemented. | Collector/serializer/check exception produces diagnostic failure or unavailable, never swallows native transaction or crashes bank. | Diagnostic errors, native-call preservation and fixture result. |
| DEBUG-010 | ☐ Bounded logs, scalar sanitization and stable IDs | **fixture**. Run oversized/cyclic/malformed diagnostic fixtures. | Oversized strings/tables/cycles/metatables stay bounded/sanitized; no retained live refs; order/IDs stable enough to compare. | Budget/cycle markers and deterministic records. |
| DEBUG-011 | ☐ Summary counts and non-exercised branches | **runtime**. Compare summary to emitted check results and intentional mismatch. | Summary separates PASS/FAIL/WARN/UNAVAILABLE/NOT_EXERCISED; missing/partial logs cannot collapse into all-pass. | Summary counts, coverage and detected failures. |
| DEBUG-012 | ☐ Offline analyzer parses real log and preserves evidence | **manual**. Run tools/analyze_log.py on saved complete Windows log. | Analyzer extracts bank events amid unrelated log lines and emits Markdown/optional JSON with precise findings and checkpoint links. | Analyzer command/output and original log. |
| DEBUG-013 | ☐ Analyzer malformed/truncated/repeated-session inputs | **fixture**. Run analyzer fixtures or documented synthetic logs; keep them distinct from Windows evidence. | Bad lines/truncation/duplicate events/session changes are reported or handled without invented evidence; unknown IDs retained. | Parser warnings and session/checkpoint attribution. |
| DEBUG-014 | ☐ Diagnostics off/on economy and result equivalence | **fixture**. Compare identical scripted sequence with diagnostics enabled and disabled. | Enabling trace does not call collectors/getters twice, change classification/score, or duplicate transactions/save hooks. | Call counts, snapshots and event deltas. |
| DEBUG-015 | ☐ Unload/reload diagnostics lifecycle and command cleanup | **manual**. Use second-save route and compare trace/command registration. | New mission/session identity starts clean; no callbacks or old expectations/checkpoints attach to wrong save. | Teardown, command lifecycle and session IDs. |
| DEBUG-016 | ☐ Log collection provenance and reproducibility | **manual**. Save log and analyzer output with route notes/screenshots. | Evidence records ZIP hash, game version, map/mods, settings, save identity and actions; original log retained before next launch. | Evidence bundle metadata and original timestamps. |
| DEBUG-017 | ☐ Automatic pure-Lua model and ledger probes | **fixture**. Inspect startup probe results and source isolation; confirm synthetic twelve-period success cannot pass real seasonal qualification. | Run once on detached synthetic input without changing native time, money or history; origin=synthetic and SYNTHETIC_* IDs stay separate from runtime coverage. | Synthetic origin/check IDs, probe result and separate runtime/scenario summaries. |

### Category subcases: FIN-001, FIN-007, FIN-009 and FIN-010

Record each native constant/key separately, even where one row lists equivalent
aliases. Presence of an enum name is a capability observation, not evidence that
its real transaction was exercised. Each live subcase needs the exact runtime
identity, requested amount, actual before/after cash and gross classification.
Each retained subcase needs the exact native bucket/key/sign/amount and, where
available, its Finance-screen correspondence. The following is the implemented
policy inventory, not a claim that every name exists in every FS25 build.

| Live MoneyType name(s), individually assessed | Retained category key | Live / retained policy treatment |
| --- | --- | --- |
| SOLD_PRODUCTS | soldProducts | operating / operating |
| SOLD_MILK | soldMilk | operating / operating |
| SOLD_BALES | soldBales | operating / operating |
| SOLD_WOOD | soldWood | operating / operating |
| PROPERTY_INCOME | propertyIncome | operating / operating; documented recurring placeable income |
| MISSIONS, MISSION_REWARD | missionIncome | operating / operating |
| No live mapping inferred | harvestIncome, fieldJobIncome | unknown live / operating retained policy |
| PURCHASE_SEEDS | purchaseSeeds | operating / operating |
| PURCHASE_FERTILIZER | purchaseFertilizer | operating / operating |
| PURCHASE_SAPLINGS | purchaseSaplings | operating / operating |
| PURCHASE_FUEL | purchaseFuel | operating / operating |
| PURCHASE_WATER | purchaseWater | operating / operating |
| VEHICLE_RUNNING_COSTS | vehicleRunningCost | operating / operating |
| VEHICLE_LEASING_COSTS | vehicleLeasingCost | operating / operating |
| PROPERTY_MAINTENANCE | propertyMaintenance | operating / operating |
| WAGE_PAYMENT | wagePayment | operating / operating |
| PURCHASE_VEHICLE, NEW_VEHICLES, VEHICLE_BUY | newVehicles | capital / capital |
| SOLD_VEHICLES, VEHICLE_SELL | soldVehicles | capital / capital |
| BUILDING_BUY, CONSTRUCTION_COST | constructionCost | capital / capital |
| BUILDING_SELL | soldBuildings | capital / capital |
| PURCHASE_LAND, LAND_BUY | boughtFields | capital / capital |
| SOLD_LAND, LAND_SELL | soldFields | capital / capital |
| LOAN_INTEREST | loanInterest | interest expense for a negative observed delta / financing label on raw retained row; retained row never imports as observed interest |
| LOAN_BORROWED | loanBorrowed | financing / financing |
| LOAN_REPAYMENT | loanRepaid | financing / financing |
| NEW_ANIMALS_COST | newAnimals | unclassified / no exact retained mapping |
| SOLD_ANIMALS | soldAnimals | unclassified / no exact retained mapping |
| UNKNOWN, absent registry, custom/unmatched identity | Any other exact key or numeric key | unclassified; no case folding, substring match or guessed numeric enum |

Matched native changeLoan cash/debt deltas use the separate nativeLoan financing
path (HIST-004), including nested addMoney suppression. Test positive and negative
actual movements and no-op where legitimate; a positive interest movement must
not become a negative expense. Same-policy aliases coalesce; conflicting exact
identities remain unknown even if one alias appears plausible. Unknown livestock
purpose and unverified custom categories remain evidence gaps, not mapping errors
to conceal for eligibility.

### Boundary subcases and source alternatives

These expand the named scenarios; do not interpret one successful ordinary value
as coverage of all variants. Local fixtures are the appropriate place for values
the game cannot safely produce. Missing fixtures stay a recorded test gap.

| Scenario family | Individually check these variants |
| --- | --- |
| SNAP, LAND, VEH, PROP, INV, ANI | Valid positive; verified zero; permitted negative cash; forbidden negative quantity/value/debt; nil; wrong scalar type; NaN; positive/negative infinity; finite aggregate overflow; throwing getter; missing getter; malformed record; unavailable entire source; healthy neighbor; duplicate reference; duplicate persistent ID; distinct equal-value objects. Apply only where meaningful for that source. |
| SNAP / HIST identity | Native active ID other than 1; invalid/spectator/missing ID; fractional ID rejection; missing/replacement manager or same-ID farm object; mismatch between source, snapshot and history. |
| Enumeration alternatives | Vehicle list versus vehicleByUniqueId; placeables versus the native spelling placableByUniqueId where implemented; direct silo/extension/production stores versus generic storage registry; item registry raw objects versus wrapped item records; cash/debt getter versus finite scalar fallback; animal count getter versus absent-getter field fallback; each retained-finance candidate with precedence and owner checks. Inventory's direct placeable adapter may remain unavailable when a fallback exists only for other sections. |
| Ownership/title | Active farm, other farm, unresolved owner, permission-only access, leased, borrowed/mission, unknown property enum, missing enum constants, cargo ownership unverified, stored counterpart owner differing from storage-building owner. |
| Deletion/transitions | Every supported markedForDeletion/isDeleting/isDeleted/getIsBeingDeleted path for its adapter; shared registry aliases after sale; object-storage move; round-bale chamber/discharge; loaded bale proxy; ridden/transported animal transitions. Unsupported deletion markers are a compatibility gap. |
| HIST / SAVE calendar | Native periods 1 and 12; adjacent 12→1; same period later monotonic day; repeated period after skipped cycle; invalid/fractional period/day; midnight; dayTime just inside/outside valid [0,86400000); boundary at and either side of 60000 ms; same/changed daysPerPeriod; backward/late/skipped observations. |
| HIST / SAVE amounts | Reconciliation at and either side of 0.01 tolerance; resumed time at and either side of 1 ms; tiny transaction at and either side of 0.000001; exact actual cash/debt loan agreement versus mismatch; finite limit near 1e15; zero actual movement; offsetting unknown gross flows. Record the exact comparator used by each path rather than assuming all boundary operators are identical. |
| Bounded state / input | 36 closed periods and one over; ordinary/category-overflow records; bounded gap messages and category names; retained finance 256 buckets, 512 keys, 8192 records and overflow; missing/extra/malformed XML periods, categories, flags, ordering and end dates. |
| SCORE | For each mode and each component: below weak, exactly weak, interior, exactly strong and beyond strong; negative/zero cash; zero receipts/costs/debt/interest; positive debt without observed interest; operating loss; score rounding and 49/50/74/75 band edges; duplicate dates inside and outside the 12-period window; latest 12 rows with an actual missing period. |
| DEBUG | Event, byte, line, nesting, string, node/key and duration budgets at/over configured bounds; idle interval, settled action burst, repeated manual capture, diagnostics toggles, mission reset, truncated/missing log tail; serializer cycles/wrong types; sink error; synthetic-versus-runtime origins. Read actual BankDebugConfig limits and emitted limit markers rather than assuming unlimited trace. |

<!-- CATALOG_CHECKLIST_END -->

## 9. Every existing named local test

Run the full commands in section 2. This inventory is generated from declared
test names, not measured branch coverage. A passing named test establishes only
its actual assertions. Missing boundary variants remain open until implemented
or independently exercised. Synthetic host probes are additionally required to
retain their SYNTHETIC_ provenance.

<!-- LOCAL_TEST_CHECKLIST_START -->

Inventory: **250 Lua tests and 58 Python test methods**, including parameterized subcases where declared. These are checklists, not prefilled passes.

### tests/test_analyze_log.py — 39 named tests

- [ ] [test_absent_first_use_history_is_visible_unavailable_not_a_read_failure](tests/test_analyze_log.py#L71)
- [ ] [test_corrupt_history_and_explicit_failures_are_not_hidden_by_missing_sidecar_handling](tests/test_analyze_log.py#L80)
- [ ] [test_clean_transport_never_claims_scenario_or_real_world_success](tests/test_analyze_log.py#L89)
- [ ] [test_sticky_fail_then_pass_and_repeated_summaries_not_added](tests/test_analyze_log.py#L99)
- [ ] [test_lost_check_recovered_from_summary_without_double_counting_later_event](tests/test_analyze_log.py#L110)
- [ ] [test_regressing_summary_cannot_erase_failure](tests/test_analyze_log.py#L120)
- [ ] [test_distinct_warning_unknown_and_not_exercised_counts](tests/test_analyze_log.py#L128)
- [ ] [test_timestamp_prefix_and_lua_numeric_object_keys_preserved](tests/test_analyze_log.py#L137)
- [ ] [test_malformed_truncated_json_and_native_warnings_preserved](tests/test_analyze_log.py#L144)
- [ ] [test_nonfinite_json_invalid_envelopes_and_unknown_schema_not_trusted](tests/test_analyze_log.py#L155)
- [ ] [test_budget_gaps_truncation_logger_error_never_all_clear](tests/test_analyze_log.py#L164)
- [ ] [test_missing_capture_dump_summary_and_mission_ends](tests/test_analyze_log.py#L173)
- [ ] [test_dump_incomplete_false_omitted_and_end_without_begin](tests/test_analyze_log.py#L180)
- [ ] [test_seq_reset_groups_processes_and_mission_change_groups_same_process](tests/test_analyze_log.py#L187)
- [ ] [test_duplicate_sequence_exact_copy_not_counted_but_conflicting_fail_retained](tests/test_analyze_log.py#L197)
- [ ] [test_no_activity_or_diagnostics_off_is_incomplete](tests/test_analyze_log.py#L207)
- [ ] [test_partial_start_and_late_check_without_final_summary](tests/test_analyze_log.py#L214)
- [ ] [test_user_values_stay_user_declared_and_do_not_pass_scenario](tests/test_analyze_log.py#L221)
- [ ] [test_synthetic_transactions_periods_and_gates_never_native_evidence](tests/test_analyze_log.py#L231)
- [ ] [test_missing_origin_not_promoted_to_runtime](tests/test_analyze_log.py#L247)
- [ ] [test_latest_capabilities_and_native_window_gates_keep_source_references](tests/test_analyze_log.py#L256)
- [ ] [test_save_stage_counts_do_not_claim_independent_saves](tests/test_analyze_log.py#L269)
- [ ] [test_missing_catalog_remains_explicit_and_runtime_coverage_is_retained](tests/test_analyze_log.py#L279)
- [ ] [test_catalog_parser_reads_real_catalog_and_refuses_unknown_layout](tests/test_analyze_log.py#L287)
- [ ] [test_bounded_summary_failure_reserve_retains_failures_after_log_budget](tests/test_analyze_log.py#L296)
- [ ] [test_bounded_failure_list_truncation_not_silently_lost](tests/test_analyze_log.py#L313)
- [ ] [test_pre_mission_mode_record_does_not_invent_missing_lifecycle](tests/test_analyze_log.py#L319)
- [ ] [test_successful_capture_requires_dump_failed_capture_is_not_usable](tests/test_analyze_log.py#L328)
- [ ] [test_post_summary_transaction_requires_new_summary](tests/test_analyze_log.py#L336)
- [ ] [test_history_nested_passthrough_and_origins_correlate_independently](tests/test_analyze_log.py#L340)
- [ ] [test_history_multiple_farm_sidecar_stages_are_one_save_lifecycle](tests/test_analyze_log.py#L357)
- [ ] [test_history_native_error_and_save_false_preserve_failure_without_broken_pairing](tests/test_analyze_log.py#L370)
- [ ] [test_history_duplicate_invocation_result_begin_and_end_are_detected](tests/test_analyze_log.py#L384)
- [ ] [test_history_missing_terminal_and_orphan_result_never_complete](tests/test_analyze_log.py#L395)
- [ ] [test_history_invalid_parent_origin_and_result_mismatches_are_not_trusted](tests/test_analyze_log.py#L404)
- [ ] [test_history_sidecar_missing_or_duplicate_stages_and_missing_identity](tests/test_analyze_log.py#L413)
- [ ] [test_history_correlation_bounded_and_unknown_stage_cannot_finish_save](tests/test_analyze_log.py#L423)
- [ ] [test_duplicate_json_key_cannot_overwrite_failure_claim](tests/test_analyze_log.py#L438)
- [ ] [test_cli_markdown_json_outputs_and_cannot_overwrite_original](tests/test_analyze_log.py#L445)

### tests/test_animals.lua — 21 named tests

- [ ] [animals read owned husbandries and multiply native per-animal quotes exactly once](tests/test_animals.lua#L50)
- [ ] [animals distinguish verified empty husbandry coverage from unavailable enumeration](tests/test_animals.lua#L66)
- [ ] [animals require a resolved farm and mission without assuming farm one](tests/test_animals.lua#L78)
- [ ] [animals use documented registered placeable lookup when list is absent](tests/test_animals.lua#L86)
- [ ] [animals deduplicate husbandry aliases and repeated cluster references without merging distinct groups](tests/test_animals.lua#L96)
- [ ] [animals never infer ownership from fields or access permissions](tests/test_animals.lua#L108)
- [ ] [animals preserve valid zero counts prices and health](tests/test_animals.lua#L120)
- [ ] [animals never convert unknown or fractional counts into zero or a quoted group value](tests/test_animals.lua#L131)
- [ ] [animals preserve known counts when all native quotes are unavailable](tests/test_animals.lua#L141)
- [ ] [animals use documented raw count only when getter is absent and never mask getter failure](tests/test_animals.lua#L150)
- [ ] [animals isolate failed quote and metadata getters while preserving healthy groups](tests/test_animals.lua#L162)
- [ ] [animals show an explicit unavailable group when a husbandry cannot enumerate clusters](tests/test_animals.lua#L174)
- [ ] [animals isolate malformed placeables and clusters without suppressing supported figures](tests/test_animals.lua#L186)
- [ ] [animals omit husbandries and groups being removed without inventing empty coverage](tests/test_animals.lua#L197)
- [ ] [animals reject overflowing group values and subtotals while retaining finite evidence](tests/test_animals.lua#L208)
- [ ] [animals keep age and reproduction raw diagnostics without inventing confirmed units](tests/test_animals.lua#L223)
- [ ] [animals reject invalid health and raw optional objects without leaking references](tests/test_animals.lua#L240)
- [ ] [animals use localized native labels and individual names without guessing breed metadata](tests/test_animals.lua#L253)
- [ ] [animals remain useful without optional animal or fill type metadata systems](tests/test_animals.lua#L265)
- [ ] [animals defer transported and ridden stock and do not perform economic or reproductive updates](tests/test_animals.lua#L276)
- [ ] [animals return detached scalar rows and refresh without retaining mission state](tests/test_animals.lua#L292)

### tests/test_bootstrap.lua — 13 named tests

- [ ] [bootstrap waits for mission mode before starting](tests/test_bootstrap.lua#L88)
- [ ] [bootstrap initializes once and only scans when requested](tests/test_bootstrap.lua#L101)
- [ ] [multiplayer and dedicated sessions remain inactive](tests/test_bootstrap.lua#L120)
- [ ] [unload releases inputs, focus, screen, commands and snapshot](tests/test_bootstrap.lua#L135)
- [ ] [loading another save creates a fresh screen and snapshot](tests/test_bootstrap.lua#L157)
- [ ] [input rebuild preserves base behavior without accumulating events](tests/test_bootstrap.lua#L173)
- [ ] [unload preserves another mod's later input wrapper](tests/test_bootstrap.lua#L186)
- [ ] [failed GUI setup restores previous focus and avoids frame retries](tests/test_bootstrap.lua#L204)
- [ ] [load completion initializes history before first clock update and preserves native returns](tests/test_bootstrap.lua#L218)
- [ ] [an undispatched load callback cannot block first-update history with diagnostics off](tests/test_bootstrap.lua#L244)
- [ ] [later loading wrappers survive unload and cannot resurrect the bank observer](tests/test_bootstrap.lua#L264)
- [ ] [model preparation failures remain explicit instead of looking like ordinary withheld results](tests/test_bootstrap.lua#L279)
- [ ] [manual expectations do not certify unavailable counts as verified zero](tests/test_bootstrap.lua#L301)

### tests/test_collector_diagnostics.lua — 6 named tests

- [ ] [collector diagnostics preserve every snapshot value and native call count when enabled](tests/test_collector_diagnostics.lua#L145)
- [ ] [collector diagnostics distinguish missing accessors thrown errors nil returns and verified zero](tests/test_collector_diagnostics.lua#L166)
- [ ] [collector diagnostics report getter-field disagreement without replacing the selected source](tests/test_collector_diagnostics.lua#L189)
- [ ] [collector diagnostic DTOs stay detached and native return tables are only shallow read inputs](tests/test_collector_diagnostics.lua#L202)
- [ ] [collector diagnostics preserve unfamiliar owners and explicitly record foreign exclusion decisions](tests/test_collector_diagnostics.lua#L217)
- [ ] [collector MoneyType instrumentation preserves exact identity results and does not traverse tokens](tests/test_collector_diagnostics.lua#L233)

### tests/test_data.lua — 19 named tests

- [ ] [active farm and strict land ownership](tests/test_data.lua#L62)
- [ ] [zero, negative cash, unavailable finance and accessor precedence](tests/test_data.lua#L75)
- [ ] [deduplicate attached equipment without excluding independent implements](tests/test_data.lua#L93)
- [ ] [leased, borrowed and another farm equipment never inflate owned total](tests/test_data.lua#L107)
- [ ] [pallets and big bags are excluded from equipment](tests/test_data.lua#L121)
- [ ] [ridden horses are disclosed and never valued as ordinary equipment](tests/test_data.lua#L133)
- [ ] [loaded trailer uses the engine quote exactly once without inventory additions](tests/test_data.lua#L146)
- [ ] [bad quote and unknown state preserve a useful partial list](tests/test_data.lua#L156)
- [ ] [unavailable is distinct from a verified empty collection](tests/test_data.lua#L170)
- [ ] [all unvalued assets never produce a zero valuation](tests/test_data.lua#L181)
- [ ] [unknown ownership does not become another farm's asset](tests/test_data.lua#L193)
- [ ] [refresh makes a detached snapshot and retains no live objects](tests/test_data.lua#L204)
- [ ] [verified vehicle lookup fallback and missing state constants](tests/test_data.lua#L216)
- [ ] [overflow never escapes as an infinite financial subtotal](tests/test_data.lua#L228)
- [ ] [monotonic game day wins over optional calendar day](tests/test_data.lua#L242)
- [ ] [mixed numeric and string asset IDs sort consistently](tests/test_data.lua#L248)
- [ ] [capture integrates buildings and quantities and isolates a failed added section](tests/test_data.lua#L260)
- [ ] [capture includes separate husbandry counts quotes and raw diagnostic age](tests/test_data.lua#L288)
- [ ] [fractional farm identifiers are unavailable rather than attributed as an active farm](tests/test_data.lua#L311)

### tests/test_diagnostics.lua — 12 named tests

- [ ] [diagnostics off performs no native serialization or writes](tests/test_diagnostics.lua#L11)
- [ ] [diagnostics JSON escapes strings and marks unsupported numeric values](tests/test_diagnostics.lua#L19)
- [ ] [diagnostics native table reads never execute metamethods or recurse into native graph](tests/test_diagnostics.lua#L28)
- [ ] [diagnostics cycles line limits and truncation are explicit rather than crashes](tests/test_diagnostics.lua#L40)
- [ ] [diagnostics budget exhaustion still writes an explicit incomplete summary](tests/test_diagnostics.lua#L51)
- [ ] [diagnostics outcomes are counted independently and never overwrite failures](tests/test_diagnostics.lua#L67)
- [ ] [diagnostic automatic captures coalesce and occur only after settling outside callbacks](tests/test_diagnostics.lua#L77)
- [ ] [synthetic checks are labeled and never schedule a native asset capture](tests/test_diagnostics.lua#L90)
- [ ] [logger sink failure and recursive logging cannot interrupt the game](tests/test_diagnostics.lua#L106)
- [ ] [snapshot dumps retain empty collections and distinct number/string identifiers](tests/test_diagnostics.lua#L116)
- [ ] [failed capture-end logging and abandoned missions never stall later automatic captures](tests/test_diagnostics.lua#L126)
- [ ] [pure validation probes run in host without touching game globals](tests/test_diagnostics.lua#L141)

### tests/test_finance.lua — 18 named tests

- [ ] [finance preserves raw signed categories and separates retained buckets without inferred periods](tests/test_finance.lua#L35)
- [ ] [finance does not treat empty missing or zero-padded maps as completed zero-activity months](tests/test_finance.lua#L54)
- [ ] [finance resolves the supplied farm dynamically and excludes mismatched stats ownership](tests/test_finance.lua#L66)
- [ ] [finance uses narrow farm candidates when a mission accessor is absent or fails](tests/test_finance.lua#L81)
- [ ] [finance never merges different candidate sources or follows arbitrary object graphs](tests/test_finance.lua#L92)
- [ ] [finance deduplicates aliased buckets but preserves identical independent retained maps](tests/test_finance.lua#L106)
- [ ] [finance preserves native period metadata as unverified scalars instead of manufacturing dates](tests/test_finance.lua#L116)
- [ ] [finance keeps declared missing categories unavailable and rejects nonfinite or nonnumeric values](tests/test_finance.lua#L129)
- [ ] [finance preserves unknown and numeric categories without substring or case classification](tests/test_finance.lua#L143)
- [ ] [finance uses runtime native labels and respects explicit declared metadata-name collisions](tests/test_finance.lua#L151)
- [ ] [finance isolates unavailable history buckets and failing labels while preserving raw rows](tests/test_finance.lua#L161)
- [ ] [finance ignores non-scalar keys explicitly and bounds oversized retained histories](tests/test_finance.lua#L172)
- [ ] [finance returns detached DTOs and never invokes economic history or mutation methods](tests/test_finance.lua#L186)
- [ ] [finance classifies live MoneyType only by exact runtime identity and isolates interest](tests/test_finance.lua#L208)
- [ ] [finance MoneyType classification rejects guessed fields unknown values and conflicting identities](tests/test_finance.lua#L227)
- [ ] [finance MoneyType same-policy aliases coalesce and custom equality cannot invent a match](tests/test_finance.lua#L246)
- [ ] [finance property income keeps observed signed amounts without verifying retained periods](tests/test_finance.lua#L257)
- [ ] [finance property income matches only an unambiguous exact native identity](tests/test_finance.lua#L273)

### tests/test_history.lua — 17 named tests

- [ ] [first partial month does not fabricate earlier activity](tests/test_history.lua#L46)
- [ ] [verified events keep operating capital financing and interest separate](tests/test_history.lua#L57)
- [ ] [current unknown cash movements gate current assessment](tests/test_history.lua#L72)
- [ ] [cash mutation outside observer breaks reconciliation](tests/test_history.lua#L81)
- [ ] [twelve full observed periods become model evidence across cycle rollover](tests/test_history.lua#L88)
- [ ] [same seasonal slot after an unobserved year never compresses history](tests/test_history.lua#L101)
- [ ] [rollback and skipped seasonal boundary restart calendar chain](tests/test_history.lua#L110)
- [ ] [late boundary observation cannot claim a full current period](tests/test_history.lua#L119)
- [ ] [bounded retention keeps at most thirty-six closed periods](tests/test_history.lua#L126)
- [ ] [resume requires exact farm cash calendar and day-length anchor](tests/test_history.lua#L132)
- [ ] [typed XML round trip preserves exact anchor and complete evidence](tests/test_history.lua#L145)
- [ ] [corrupted XML cannot manufacture reconciled cash evidence](tests/test_history.lua#L160)
- [ ] [failed XML save releases its handle and reports failure](tests/test_history.lua#L173)
- [ ] [invalid cash deltas stay partial without storing nonfinite amounts](tests/test_history.lua#L181)
- [ ] [bounded category overflow is unclassified in details and totals](tests/test_history.lua#L189)
- [ ] [invalid classifications and interest refunds remain explicit unknown flows](tests/test_history.lua#L201)
- [ ] [XML success has no error text and missing write acknowledgement fails closed](tests/test_history.lua#L210)

### tests/test_history_diagnostics.lua — 16 named tests

- [ ] [logging changes neither economic calls nor exact return slots](tests/test_history_diagnostics.lua#L137)
- [ ] [nested nonactive and unreadable calls have distinct honest trace paths](tests/test_history_diagnostics.lua#L160)
- [ ] [native errors retain exact errors and observers recover](tests/test_history_diagnostics.lua#L184)
- [ ] [throwing diagnostic methods cannot stop native transactions](tests/test_history_diagnostics.lua#L200)
- [ ] [sample trace excludes ticking time but captures material state changes](tests/test_history_diagnostics.lua#L215)
- [ ] [save traces expose stages and basenames without promising native completion](tests/test_history_diagnostics.lua#L228)
- [ ] [XML verification reads only in debug and checks full persisted contract](tests/test_history_diagnostics.lua#L242)
- [ ] [failed readback never changes acknowledged write result](tests/test_history_diagnostics.lua#L258)
- [ ] [unacknowledged XML write cannot emit passing readback](tests/test_history_diagnostics.lua#L274)
- [ ] [XML release tracing reports one successful native call per acquired handle](tests/test_history_diagnostics.lua#L286)
- [ ] [throwing XML release is bounded visible and preserves successful read write results](tests/test_history_diagnostics.lua#L305)
- [ ] [throwing XML release never replaces original write or decode failure](tests/test_history_diagnostics.lua#L335)
- [ ] [non-string XML release errors never invoke arbitrary error metamethods](tests/test_history_diagnostics.lua#L353)
- [ ] [period and resume checks distinguish complete partial and unexercised](tests/test_history_diagnostics.lua#L365)
- [ ] [withheld models never claim executed scoring or supported seasonality](tests/test_history_diagnostics.lua#L385)
- [ ] [teardown proves owned restoration while preserving newer wrappers](tests/test_history_diagnostics.lua#L409)

### tests/test_history_runtime.lua — 20 named tests

- [ ] [money wrapper preserves exact native execution and nil returns](tests/test_history_runtime.lua#L68)
- [ ] [nested native loan money call is recorded once as financing](tests/test_history_runtime.lua#L78)
- [ ] [loan repayment is financing outflow and never operating expense](tests/test_history_runtime.lua#L92)
- [ ] [unmatched native debt mutation creates an explicit current gap](tests/test_history_runtime.lua#L101)
- [ ] [old farm hooks are removed and cannot target the new active farm](tests/test_history_runtime.lua#L112)
- [ ] [replacement farm object updates observer references](tests/test_history_runtime.lua#L128)
- [ ] [unavailable farm clears stale active report](tests/test_history_runtime.lua#L140)
- [ ] [save callback uses current temporary directory and preserves native returns](tests/test_history_runtime.lua#L149)
- [ ] [saved exact cash debt and calendar anchor resumes without callback duplication](tests/test_history_runtime.lua#L160)
- [ ] [stale sidecar cash or debt never imports prior continuity](tests/test_history_runtime.lua#L175)
- [ ] [observer failure never swallows or duplicates native transactions](tests/test_history_runtime.lua#L188)
- [ ] [teardown preserves another mod's later wrapper and drops bank ownership](tests/test_history_runtime.lua#L198)
- [ ] [returned diagnostic metadata is detached from live observer tables](tests/test_history_runtime.lua#L213)
- [ ] [native transaction failure is rethrown and wrapper state recovers](tests/test_history_runtime.lua#L224)
- [ ] [native save failure never writes an apparently successful sidecar](tests/test_history_runtime.lua#L236)
- [ ] [day-length setting change invalidates earlier comparable history](tests/test_history_runtime.lua#L246)
- [ ] [late resume does not silently relax the exact calendar anchor](tests/test_history_runtime.lua#L260)
- [ ] [native transaction observations drive a complete model and survive save reload](tests/test_history_runtime.lua#L273)
- [ ] [documented property income reconciles a 652 receipt and preserves refund gross direction](tests/test_history_runtime.lua#L328)
- [ ] [property mapping does not relabel earlier unknown activity or accept conflicting aliases](tests/test_history_runtime.lua#L382)

### tests/test_inventory.lua — 20 named tests

- [ ] [silos and extensions use contents owner and deduplicate registry aliases](tests/test_inventory.lua#L51)
- [ ] [dedicated production storage belongs to owned finalized placeable](tests/test_inventory.lua#L71)
- [ ] [loaded units, pallets and leased containers disclose unverified cargo title](tests/test_inventory.lua#L88)
- [ ] [native custom unit text is preserved without inventing liters](tests/test_inventory.lua#L111)
- [ ] [tree planter proxy does not duplicate the mounted sapling pallet](tests/test_inventory.lua#L120)
- [ ] [missing registered mounted pallet is an explicit coverage gap](tests/test_inventory.lua#L134)
- [ ] [verified zero and unavailable quantities remain different](tests/test_inventory.lua#L146)
- [ ] [missing metadata preserves known quantity and discloses identification gap](tests/test_inventory.lua#L164)
- [ ] [bad accessor does not prevent neighboring sources or fill units](tests/test_inventory.lua#L176)
- [ ] [missing farm, systems, and an empty supported inventory are distinguishable](tests/test_inventory.lua#L192)
- [ ] [owned object storage counts the held pallet once at its storage location](tests/test_inventory.lua#L212)
- [ ] [unknown owners and property states never become attributed holdings](tests/test_inventory.lua#L228)
- [ ] [refresh snapshots are detached and have deterministic row order](tests/test_inventory.lua#L243)
- [ ] [removed placeable stores cannot reappear through registry or sibling aliases](tests/test_inventory.lua#L264)
- [ ] [all deletion signals exclude vehicle cargo while preserving healthy quantities](tests/test_inventory.lua#L296)
- [ ] [standalone registered storage respects deletion without a placeable](tests/test_inventory.lua#L317)
- [ ] [deleted virtual store display objects never become loose inventory](tests/test_inventory.lua#L330)
- [ ] [bale loader counts and straw blower mirrors never duplicate physical bale quantities](tests/test_inventory.lua#L350)
- [ ] [round baler transition is omitted while independent buffer and square-baler material remain](tests/test_inventory.lua#L373)
- [ ] [an owned bale in a borrowed baler retains a visible chamber omission](tests/test_inventory.lua#L401)

### tests/test_property.lua — 15 named tests

- [ ] [buildings include only the resolved farm and accept zero monetary value](tests/test_property.lua#L26)
- [ ] [buildings distinguish a complete empty registry from unavailable enumeration](tests/test_property.lua#L35)
- [ ] [buildings require a valid active farm and placeable system](tests/test_property.lua#L43)
- [ ] [buildings deduplicate both repeated objects and registered unique identifiers](tests/test_property.lua#L51)
- [ ] [buildings never use temporary construction refunds or inferred purchase costs](tests/test_property.lua#L59)
- [ ] [buildings preserve advisory sale veto separately from monetary value](tests/test_property.lua#L72)
- [ ] [buildings reject missing, invalid, negative and nonfinite values without claiming zero](tests/test_property.lua#L83)
- [ ] [buildings do not infer ownership from mutable fields or land access](tests/test_property.lua#L99)
- [ ] [buildings omit registered objects pending deletion](tests/test_property.lua#L110)
- [ ] [buildings retain healthy records when custom monetary accessors throw](tests/test_property.lua#L123)
- [ ] [buildings isolate malformed registry records](tests/test_property.lua#L133)
- [ ] [buildings use the documented lookup spelling when the primary list is absent](tests/test_property.lua#L141)
- [ ] [buildings reject an overflowing subtotal while preserving finite item values](tests/test_property.lua#L150)
- [ ] [buildings return detached scalar data and do not retain stale values](tests/test_property.lua#L158)
- [ ] [buildings contain invalid custom names and identifiers instead of leaking references](tests/test_property.lua#L178)

### tests/test_report.lua — 19 named tests

- [ ] [report uses active farm, game date and native currency/area formatting](tests/test_report.lua#L52)
- [ ] [report distinguishes verified zero, unavailable and known partial totals](tests/test_report.lua#L65)
- [ ] [report fully unavailable input does not invent zero balances](tests/test_report.lua#L82)
- [ ] [screen captures only on open/refresh, replaces failed data and releases references](tests/test_report.lua#L91)
- [ ] [financial report discloses raw native slots without importing them as complete history](tests/test_report.lua#L177)
- [ ] [financial report presents full model evidence and keeps cash scenario separate from asset value](tests/test_report.lua#L193)
- [ ] [large reports paginate every asset and issue without truncation](tests/test_report.lua#L226)
- [ ] [snapshot formatting is read-only and keeps contents qualification](tests/test_report.lua#L249)
- [ ] [localization is scoped to this mod and malformed translation falls back](tests/test_report.lua#L259)
- [ ] [building monetary values extend the subtotal without promising sale proceeds](tests/test_report.lua#L273)
- [ ] [goods show native quantities and container ownership without adding inventory money](tests/test_report.lua#L290)
- [ ] [missing buildings and goods remain unavailable while verified empty buildings show zero](tests/test_report.lua#L311)
- [ ] [large stored-goods reports preserve every location within page limits](tests/test_report.lua#L324)
- [ ] [report pagination never gives a trailing separator its own empty page](tests/test_report.lua#L339)
- [ ] [overflow across otherwise finite asset sections is unavailable](tests/test_report.lua#L368)
- [ ] [bale report preserves current contents, fermentation and unavailable virtual quantities](tests/test_report.lua#L375)
- [ ] [livestock reference values stay separate from covered assets and retain native condition](tests/test_report.lua#L396)
- [ ] [livestock empty supported data and absent coverage never look identical](tests/test_report.lua#L417)
- [ ] [large livestock reports retain every group without overflowing page lines](tests/test_report.lua#L429)

### tests/test_stored_objects.lua — 16 named tests

- [ ] [registered real bales support raw and wrapped item records and reject unrelated items](tests/test_stored_objects.lua#L71)
- [ ] [other farms and mission bales do not become farm stock](tests/test_stored_objects.lua#L83)
- [ ] [loaded unsellable bales remain quantities and use actual current fermentation fill type](tests/test_stored_objects.lua#L96)
- [ ] [stored bale counterpart and every registry identity alias count once](tests/test_stored_objects.lua#L112)
- [ ] [stored pallets preserve all units custom text and one object count](tests/test_stored_objects.lua#L124)
- [ ] [pure virtual records show object count and unavailable quantity without parsing UI text](tests/test_stored_objects.lua#L136)
- [ ] [unknown object class retains unavailable entry rather than inventing a bale](tests/test_stored_objects.lua#L152)
- [ ] [removed storage blocks its counterparts even when other adapters still register them](tests/test_stored_objects.lua#L161)
- [ ] [deleted and unknown-owner loose bales are omitted while healthy sources survive](tests/test_stored_objects.lua#L173)
- [ ] [preblocked transient bales remain registered for proxy reconciliation](tests/test_stored_objects.lua#L186)
- [ ] [missing registries and missing native Bale class differ from empty supported data](tests/test_stored_objects.lua#L196)
- [ ] [invalid and throwing quantity getters keep a useful partial report](tests/test_stored_objects.lua#L210)
- [ ] [stored counterparts with another owner are blocked and never attributed by building ownership](tests/test_stored_objects.lua#L223)
- [ ] [diagnostic shape samples are capped and never retain native objects](tests/test_stored_objects.lua#L232)
- [ ] [documented placableByUniqueId fallback reads stored entries](tests/test_stored_objects.lua#L255)
- [ ] [bad fermentation progress is unavailable without changing current crop quantity](tests/test_stored_objects.lua#L264)

### tests/test_tools.py — 19 named tests

- [ ] [test_current_resource_tree_validates_without_native_claim](tests/test_tools.py#L59)
- [ ] [test_missing_manifest_and_malformed_xml_are_rejected](tests/test_tools.py#L63)
- [ ] [test_manifest_root_version_description_and_required_fields](tests/test_tools.py#L74)
- [ ] [test_multiplayer_manifest_must_explicitly_disable_support](tests/test_tools.py#L88)
- [ ] [test_resource_paths_reject_traversal_absolute_backslash_and_missing](tests/test_tools.py#L94)
- [ ] [test_resource_case_mismatch_and_case_alias_inventory](tests/test_tools.py#L108)
- [ ] [test_runtime_symlinks_are_rejected](tests/test_tools.py#L125)
- [ ] [test_localization_duplicates_and_unresolved_gui_keys_are_rejected](tests/test_tools.py#L133)
- [ ] [test_localization_prefix_and_lua_resource_literals_are_validated](tests/test_tools.py#L144)
- [ ] [test_inherited_gui_callbacks_are_warnings_not_invented_resolution](tests/test_tools.py#L151)
- [ ] [test_missing_runtime_families_are_rejected](tests/test_tools.py#L158)
- [ ] [test_dds_magic_header_dimensions_mips_format_and_payload_are_checked](tests/test_tools.py#L164)
- [ ] [test_package_allowlist_excludes_development_evidence_and_source_art](tests/test_tools.py#L182)
- [ ] [test_build_is_byte_reproducible_with_exact_payload_and_fixed_zip_metadata](tests/test_tools.py#L196)
- [ ] [test_validation_failure_does_not_create_or_overwrite_existing_zip](tests/test_tools.py#L214)
- [ ] [test_icon_art_rasterization_rect_polygon_and_color_contracts](tests/test_tools.py#L224)
- [ ] [test_icon_unsupported_svg_and_wrong_dimensions_fail_before_output_write](tests/test_tools.py#L239)
- [ ] [test_dxt5_small_mipmap_edge_replication_and_opaque_alpha](tests/test_tools.py#L252)
- [ ] [test_generated_icon_full_mips_and_no_rewrite_when_unchanged](tests/test_tools.py#L260)

### tests/test_underwriting.lua — 27 named tests

- [ ] [complete native cycle produces transparent bounded score](tests/test_underwriting.lua#L35)
- [ ] [new save has insufficient evidence without invented grade](tests/test_underwriting.lua#L55)
- [ ] [shorter observations are summed without annualization](tests/test_underwriting.lua#L66)
- [ ] [partial first month cannot impersonate a complete year](tests/test_underwriting.lua#L76)
- [ ] [failed cash reconciliation blocks scoring and seasonality](tests/test_underwriting.lua#L85)
- [ ] [unclassified inflows and outflows cannot cancel their uncertainty](tests/test_underwriting.lua#L93)
- [ ] [missing cost is unavailable and never zero](tests/test_underwriting.lua#L102)
- [ ] [negative or nonfinite gross amounts invalidate a period](tests/test_underwriting.lua#L111)
- [ ] [duplicate dated months are never summed twice](tests/test_underwriting.lua#L121)
- [ ] [old duplicate records do not invalidate a clean current window](tests/test_underwriting.lua#L130)
- [ ] [calendar gaps remain gaps despite twelve records](tests/test_underwriting.lua#L137)
- [ ] [unverified or malformed date prevents invented chronology](tests/test_underwriting.lua#L145)
- [ ] [seasonal scenario matches seasonal slot and omits partial current month](tests/test_underwriting.lua#L157)
- [ ] [capital sales borrowing and asset prices never create operating income](tests/test_underwriting.lua#L175)
- [ ] [mode thresholds are monotonic and independently copied](tests/test_underwriting.lua#L192)
- [ ] [complete inactive year remains startup evidence not failed grade](tests/test_underwriting.lua#L204)
- [ ] [unknown cash and native debt cannot produce a score](tests/test_underwriting.lua#L216)
- [ ] [native debt without observed interest withholds cost-based assessment](tests/test_underwriting.lua#L226)
- [ ] [material gaps and suspected external debt gate a score](tests/test_underwriting.lua#L239)
- [ ] [missing or invalid farm identity cannot authorize a score or seasonal scenario](tests/test_underwriting.lua#L258)
- [ ] [unverified material coverage also withholds a seasonal scenario](tests/test_underwriting.lua#L277)
- [ ] [history from another farm cannot be rated](tests/test_underwriting.lua#L287)
- [ ] [negative cash and operating loss are explicit not infinities](tests/test_underwriting.lua#L297)
- [ ] [overflow is unavailable not a fabricated bounded score](tests/test_underwriting.lua#L311)
- [ ] [returned observations have no live references to supplied history](tests/test_underwriting.lua#L320)
- [ ] [unavailable collateral figures are not resurrected from stale numbers](tests/test_underwriting.lua#L331)
- [ ] [conflicting duplicate rows never choose a financial winner](tests/test_underwriting.lua#L340)

### tests/test_validation.lua — 11 named tests

- [ ] [snapshot invariants accept valid partial evidence without claiming complete underwriting](tests/test_validation.lua#L18)
- [ ] [independent asset sums catch duplicate identifiers incorrect subtotals and leased valuation](tests/test_validation.lua#L25)
- [ ] [unknown financial readings never silently pass as verified zero](tests/test_validation.lua#L36)
- [ ] [animal quote math and unknown units are checked separately](tests/test_validation.lua#L43)
- [ ] [ledger arithmetic distinguishes disclosed gaps from false reconciliation](tests/test_validation.lua#L54)
- [ ] [fabricated eligible result without dated history fails independent model gate](tests/test_validation.lua#L64)
- [ ] [snapshot delta logs added and removed assets without inventing a sale amount](tests/test_validation.lua#L72)
- [ ] [report pages verify physical line limits but cannot prove visual clipping](tests/test_validation.lua#L80)
- [ ] [independent page validation catches empty separator-only pages within the line limit](tests/test_validation.lua#L87)
- [ ] [unknown farm identity is unavailable while a malformed positive fraction is a failure](tests/test_validation.lua#L99)
- [ ] [native category delta comparison discloses sign uncertainty and catches magnitude mismatches](tests/test_validation.lua#L106)

<!-- LOCAL_TEST_CHECKLIST_END -->

## 10. Closeout and evidence to return

- [ ] All catalog IDs, supplemental procedures, category aliases and applicable
  boundary variants have a result and evidence reference; absent paths remain
  NOT_EXERCISED/UNAVAILABLE with a reason.
- [ ] No unresolved unexpected failure, unexplained balance change, owner error,
  duplicate valuation, hidden truncation or lifecycle leak is called a pass.
- [ ] Known limitations stay disclosed in the GUI/log and acceptance record.
  Do not represent excluded farm wealth or external financing as verified zero.
- [ ] Native-source and retained-window findings are recorded separately from
  observed-history/model tests. A formula-correct score is not proof of real-world
  predictive accuracy or a farm’s ability to repay a proposed loan.
- [ ] Fixture outcomes, synthetic in-game probes and real Windows outcomes are
  separate, with artifact hashes and save/run identities.
- [ ] Preserve each original log, analyzer Markdown/JSON, local test/build output,
  relevant sidecars and independent native screenshots/notes.
- [ ] Return the result ledger plus **complete logs**, with the exact actions for
  each discrepancy. For reload problems include the disposable sidecar and
  whether the native save completed. Do not send only selected warning lines.
- [ ] If any required path is still missing evidence, report a scoped partial
  result and the exact remaining work. Do not declare “everything accurate”
  solely because all collected internal checks passed.
