# Validation evidence: audit reset

Version under validation: **0.0.8**, fixing the scoped findings from the first
detailed diagnostic Windows log. See [the log review](log-review-2026-09-27.md)
for captured 0.0.6 evidence, corrected defects and unresolved native adapters.
Audit reset recorded **2026-09-27**.

**Earlier user reports of overall success through 0.0.5 are not relied upon as
acceptance evidence. Windows correctness is UNVERIFIED until the relevant
scenario has recorded evidence.** This changes how evidence is assessed; it does
not assert that previous feedback was inaccurate or that every feature failed.

| Evidence category | Current status | What can be established |
| --- | --- | --- |
| Local Lua tests | **250 passed, 0 failed — Lua 5.1.5** | Only contracts actually exercised with explicit game stubs; no automatic engine pass |
| Local analyzer/tooling tests | **58 Python tests passed: 39 analyzer + 19 tooling; Lua diagnostic fixtures included above** | Instrumentation/parser/package behavior for supplied inputs; not correctness of an unseen Windows log |
| Lua syntax for every shipped runtime file | **19 of 19 passed** | Standard Lua 5.1 syntax, not availability/order of GIANTS globals |
| XML, localization, callback and exact-case resource validation | **Passed tools/validate.py** | Structural integrity of the shipped package |
| DDS icon and deterministic ZIP/hash | **Passed; two byte-identical builds, all 25 entries match source** | Icon/archive format and reproducible artifact identity |
| GIANTS TestRunner | **NOT RUN — unavailable in this workspace** | Native/static package checks still outstanding; not economic correctness |
| Windows FS25 0.0.8 short route | **NOT EXERCISED** | Baseline behavior only for the recorded map/mods/actions |
| Submitted 0.0.6 Windows log | **PARTIAL evidence reviewed; defects found** | Eight snapshots, five native money-call lifecycles, GUI navigation/refresh/close; no native save/reload/loan/period boundary or independent UI figures |
| Windows extended seasonal qualification | **NOT EXERCISED** | Eligible history, seasonal repeat and scoring in the real engine, only after the actual run |
| Prior overall runtime reports, 0.0.1–0.0.5 | **UNVERIFIED for acceptance after audit reset** | Historical user feedback only; no missing scenario result is inferred |
| Every scenario in VALIDATION_MATRIX.md | **NOT EXERCISED unless individually recorded otherwise** | Evidence scoped to that scenario, input and test environment |

Local verification completed **2026-09-27**. Catalog/matrix/runbook parity is
**190 unique IDs**. The root [test.md](../test.md) contains every catalog row,
category/boundary expansions, a source/resource responsibility map and all
250 Lua / 58 Python declared test names with source links. Local runbook links
and source/tool/test path coverage were checked; this is inventory validation,
not measured branch coverage. Every runtime Lua file is listed in the manifest. An actual
`BankDiagnostics.lua` serializer → Python analyzer fixture round trip also
completed with transport marked CAPTURED and all 190 scenarios still
NOT_EXERCISED; this was local synthetic evidence, not a Windows session.

Artifact: `dist/FS25_LizardBank.zip`, **116,971 bytes**, version **0.0.8**.
SHA256: `fd02c784d426841b6fd9b66913b95ceeb4fb972c6c77b44c34b9d52916e0c06c`.
The ZIP has `modDesc.xml` at its root and excludes tests, tools, development
documents and user logs. `git diff --check` passed.

## Evidence boundaries

The [validation matrix](VALIDATION_MATRIX.md) inventories 190 scenarios with stable
IDs, expected oracles, required setup and log evidence. The corresponding
[BankValidationCatalog.lua](../scripts/BankValidationCatalog.lua) declares scenarios,
not successful outcomes. The [Windows route](WINDOWS_TEST.md) minimizes repetitive
manual recording while preserving independent native-screen comparisons.

An automatic check can establish that a reported subtotal equals its captured
items, that a known owner matches the farm, or that a ledger reconciles. It cannot
prove that the native registry contains every asset, that a supplied UI expectation
was entered correctly, or that an unobserved gameplay path works. A PASS for an
internal invariant is not a blanket feature or scenario PASS. No captured path
means NOT_EXERCISED; unavailable native data remains UNAVAILABLE, even where its
graceful handling passed a local fixture.

Local fixtures use explicit game substitutes. Their twelve-period integration
path, XML round trips, failed accessors, category identities, extreme values,
hook return preservation and malformed inputs verify deterministic logic only
where assertions exist. They are not recordings from the GIANTS engine and do
not establish native finance layout, callback timing, input focus, temporary-save
promotion or a real twelve-period observation. A related test filename in the
matrix identifies where to inspect coverage, not proof all variants passed.

The save callback's successful sidecar write does not establish whole-save
completion. Clean saved/read farm, cash, debt and calendar anchors plus the final
file and real reload are required. Retained native Finance dates/order/window/
padding remain unverified and excluded from the observed model input. Optional
fallbacks and raw animal units retain their explicit uncertainty.

Documentation sources remain recorded in [data-sources.md](data-sources.md),
[gui-sources.md](gui-sources.md), [finance-sources.md](finance-sources.md) and
[history-sources.md](history-sources.md). Published API references support
implementation decisions; they are not runtime validation.

## Historical feedback retained without acceptance inference

Earlier conversation feedback reported overall success for 0.0.1, 0.0.2, 0.0.3,
0.0.4 and 0.0.5. Earlier supplied log material identified FS25 1.23.1.0 and an
Arkansas 4X load. Those reports did not supply an itemized record for every
financial, ownership, persistence, seasonal or controller scenario.

For this audit, none of those broad confirmations is carried forward as a
scenario PASS or a complete-release acceptance. Historic local test counts and
earlier successful packaging are likewise not substituted for the current
0.0.8 run. New evidence should preserve artifact hash, game version, map/mod
context, settings, original log, named checkpoints, independent measurements and
the precise matrix IDs actually exercised.

## Result entry format

Record: scenario ID; artifact SHA256; game/map/mod context; checkpoint/session;
setup/actions; independent expected value or invariant; actual result; outcome;
evidence location; unresolved limitation. Several subcases in one row may be
PARTIAL in the human record; keep unresolved machine scenarios NOT_EXERCISED
until assessed rather than promoting a group from one successful example.

Diagnostic truncation, missing sessions, fixture-only evidence and absent native
capabilities belong in the acceptance record. A review may accept a clearly
scoped result, but it must identify unverified cases and must not describe a
10–15 minute baseline as universal financial or engine validation.
