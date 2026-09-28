# Observation history and runtime assumptions

This implementation ships with v0.0.5; Windows validation is pending. The local
suite validates the adapter contracts with explicit stubs. It cannot establish
native hook timing, native save promotion or every mod's money path.

## Evidence

- Official FS25 [AbstractMission](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=59&class=560&version=script)
  shows `mission:addMoney(change, farmId, MoneyType.MISSIONS, true, true)` in a
  server branch. This establishes the first three arguments and a real callsite;
  it does not publish the mission function body, boolean meanings or return values.
  Lizard Bank forwards every argument and return, reads actual balance deltas,
  and never invokes an economic function merely to discover its behavior.
- The same source reads `environment.currentMonotonicDay`, `daysPerPeriod`,
  `getDayInPeriodFromDay(day)` and millisecond `dayTime`. `currentYear` rollover
  is not established by that source. Our history uses local observation cycles
  and native period numbers, never inferred Gregorian dates.
- FS25 mod author [NewCareerDefaults](https://github.com/rdrygas/FS25_NewCareerDefaults)
  reports period 6 as August and a March-first native year. Its
  [implementation](https://raw.githubusercontent.com/rdrygas/FS25_NewCareerDefaults/main/scripts/NewCareerDefaults.lua)
  appends to `FSBaseMission.saveSavegame`, then writes under the mission's current
  `missionInfo.savegameDirectory`. The author reports that this is the temporary
  save folder subsequently promoted to the final slot. This is another author's
  primary code/runtime evidence, not an official published native implementation.
  Our capability-checked mission-instance wrapper uses that callback timing and
  resolves the directory after the original call returns. **A successful sidecar
  write is not proof that the whole native save subsequently completed.**
- The same mod author's `Mission00.loadMission00Finished` callback provides a
  practical loading-stage candidate. Lizard Bank installs a cooperative hook
  during `loadMap`, starts history after that original callback returns, and
  reads its save anchor before the first ordinary clock update. If unavailable,
  first-update or first-report fallback is recorded in diagnostics. Timestamp
  mismatches are never silently waived. Native load ordering still needs Windows
  validation, including interaction with another mod that changes the calendar.
- Native [saveXMLFile](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=33&function=884&version=engine)
  documents a boolean write result; [loadXMLFile](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=33&function=881&version=engine)
  documents zero on failure. The sidecar uses explicit string attributes for
  round-trip numeric precision, bounded arrays, finite-number validation and a
  schema version. It never deserializes executable Lua.
- `farm:changeLoan(...)`, `farm:getBalance()`/`money` and `getLoan()`/`loan` remain
  narrow runtime compatibility candidates. Loan classification requires matching
  cash and loan deltas. Unknown or conflicting MoneyType identities remain
  unclassified; arbitrary statistic fields are not trusted as classifications.

## Observation contract

The runtime observes only the active single-player farm. It samples calendar,
cash and debt once per second of game update time, and around intercepted native
money/loan calls. It does not scan assets each frame. Opening, Refresh and saving
also sample. Hooks call the original once, retain nil/multiple returns, propagate
native errors, and contain observer errors. Teardown removes only owned wrappers;
later wrappers from another mod are preserved with our observer detached.

The first installed period is partial, even for an apparently new save. A next
period is eligible for complete observation only across an adjacent native
period/day boundary first seen within its first game minute. Calendar jumps,
rollbacks, changed days-per-period, unexplained balances, identity changes and
observer failures invalidate affected continuity. Native retained rows are never
silently imported. A current period is not input as a completed forecast period.

Gross flows are recorded from actual cash changes, separately for operating
receipts/payments, interest, capital, financing and unknown movements. Category
totals retain a reconciliation trail for comparison with native Finance rows.
No amount is inferred from an asset valuation or a loan request's nominal amount.
Nested transactions with ambiguous mixed categories remain unclassified; a
matched native loan cash/debt change may be identified as financing.

At most 36 closed periods, bounded category counts and bounded gap messages are
retained per farm. Periods and report objects are copied so presentation cannot
modify observation state. Custom data is `lizardBankHistory_<farmId>.xml` in the
native save directory. It is written only during normal save callbacks, never
merely on exit or Refresh. Policy selection is stored with that farm's history.

Reload continuity requires a valid sidecar and matching farm/calendar/cash/debt
anchors. A failed native save, a restored older save with a newer sidecar, edited
money, play with the mod disabled, corrupt data, or another farm cannot silently
provide a complete history. Whole-folder backups are the supported way to copy
or restore a save. Sidecars are local game records, not tamper-proof evidence;
identical anchors cannot detect every external edit or every net-zero mutation
made through unsupported paths between observations.

## Explicit limits

Public scripting pages currently identify v1.20.0.0 while the supplied Windows
log identifies FS25 1.23.1.0. Runtime capability checks and Finance reconciliation
remain necessary. Absence of a compatible money/save hook is an unavailable
capability, not permission to invent history. Unknown money types, including
livestock capital-versus-operating purpose, can prevent an assessment. Native
interest coverage does not establish principal repayment obligations, external
loan completeness, payable bills, or accrued profit. These gaps remain visible
in the model and its GUI, with no economic changes or loan issuance.
