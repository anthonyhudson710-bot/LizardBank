# Lizard Bank 0.0.8 validation matrix

This is an audit reset. **Earlier overall success reports are not relied upon as
acceptance evidence. All Windows scenarios below begin NOT_EXERCISED.** This
release adds validation to the complete 0.0.5 feature set; it does not establish
that the previous implementation was correct. Local fixtures establish only the
contracts they exercise with explicit game stubs.

The inventory covers the current implemented contract, known source alternatives,
failures, boundaries and disclosures. It cannot enumerate every behavior of an
arbitrary map, patch, mod combination or corrupted save. Add a new stable scenario
when a new failure class or supported adapter is discovered. Do not replace an
unknown result with an all-clear because the game opened successfully.

## Evidence and result rules

- **runtime**: automatically observable internal property, such as arithmetic,
  captured source shape or duplicate suppression. PASS means that property held
  for the recorded inputs. It does not prove that a source enumerated every real
  asset or agreed with a native game screen.
- **manual**: native UI/gameplay or other independent evidence is required. Logs
  reduce transcription and identify decisions; they do not manufacture the
  independent oracle. A supplied lbExpect value is marked user-entered evidence,
  not verified proof that the entered value was read correctly.
- **fixture**: synthetic, isolated failure/boundary exercise. A passing test is
  useful logic evidence and must remain separate from an FS25 engine result.
  Related test files identify where to investigate; a filename is not a claim
  that every subcase already has a passing assertion. Record any missing fixture.
- **structural**: package/XML/resource/static checks, with native loading called
  out separately. Packaging success is not runtime acceptance.

Record outcome as PASS, FAIL, WARN, UNAVAILABLE or NOT_EXERCISED, with game/build,
checkpoint, oracle and actual result. UNAVAILABLE can be correct graceful behavior
for an unsupported capability, but does not pass the supported-value scenario.
Known limitations can have their *disclosure* verified while the missing quantity
or economic coverage remains unavailable. A scenario with several subcases is
PARTIAL in human review until all required subcases have evidence; retain the
individual outcomes rather than marking the whole row PASS. In the machine
catalog, unresolved scenario status stays NOT_EXERCISED unless explicitly assessed.

The catalog in [BankValidationCatalog.lua](../scripts/BankValidationCatalog.lua)
contains 190 stable scenario IDs and matching oracle/procedure/log fields.
It is an inventory, not executable proof. Emitted low-level check IDs (including
collector decisions and history/diagnostic invariants) are independent evidence;
their PASS results must not automatically promote a catalog scenario. A successful
owner-equality check establishes why one observed item was included, not whether
all assets exist in the registry. No evidence is implied for a row merely because
another row in its group passed.

Start with the [short Windows route](WINDOWS_TEST.md). It gathers broad baseline
coverage in one session. Long seasonal evidence and unusual assets remain explicit
follow-up cases. Preserve the original log as well as analyzer reports.

## Source inventory

The original runtime contract spans BankDataSource, BankPropertyDataSource,
BankInventoryDataSource, BankStoredObjectDataSource, BankAnimalDataSource,
BankFinanceDataSource, BankHistory, BankHistoryStore, BankHistoryRuntime,
BankUnderwriting, BankFinancialReport, BankReport, BankScreen and LizardBank.
The validation layer adds startup configuration, diagnostic collection, this
catalog and offline log analysis. Packaging must include all declared runtime
files in dependency order. The table groups below cover those responsibilities,
GUI/localization/manifest resources and their tests.

## PKG: Packaging and native loading

Related local checks: [tools/build.py](../tools/build.py), [tools/validate.py](../tools/validate.py). Their latest execution status is recorded in [VALIDATION.md](VALIDATION.md).

| ID | Scenario | Required evidence / setup | Expected oracle | Log / supporting evidence |
| --- | --- | --- | --- | --- |
| PKG-001 | Release identity and root archive layout | **structural**. Run build/validator and inspect ZIP names and version fields. | ZIP root contains modDesc.xml; manifest, bootstrap and diagnostics agree on 0.0.8. | Build output, ZIP list, startup version. |
| PKG-002 | Every declared source and GUI resource exists with exact case | **structural**. Validate sourceFiles, GUI/profile/icon/localization references. | Manifest load order resolves every global dependency; no absent resource or callback. | Validator output, native load errors. |
| PKG-003 | XML, localization and icon integrity | **structural**. Run local validation; inspect native mod selection icon/title. | XML parses; every lb_* string resolves; icon is valid 512px DXT5 with mipmaps. | Validator output and selection screenshot. |
| PKG-004 | Deterministic packaging and isolated runtime payload | **structural**. Build twice and compare hashes/list; install only ZIP. | Repeated unchanged builds have identical SHA256; archive includes needed runtime files and no tests, caches or dev tools. | Build hashes and ZIP inventory. |
| PKG-005 | Clean install without dependencies or stale duplicate copies | **manual**. Install into active mods folder, enable on disposable save, record other mods. | Single enabled Lizard Bank entry loads using only packaged resources. | Full startup log and selected version. |
| PKG-006 | Native parser and GIANTS TestRunner | **structural**. Run documented local commands and TestRunner if available. | Lua 5.1 parse, resource checks and available TestRunner pass; unavailable TestRunner stays pending. | Exact commands, versions and outputs. |

## LIFE: Mission lifecycle, inputs and integration

Related local checks: [tests/test_bootstrap.lua](../tests/test_bootstrap.lua), [tests/test_history_runtime.lua](../tests/test_history_runtime.lua). Their latest execution status is recorded in [VALIDATION.md](VALIDATION.md).

| ID | Scenario | Required evidence / setup | Expected oracle | Log / supporting evidence |
| --- | --- | --- | --- | --- |
| LIFE-001 | Initialization while mission and mode are unavailable | **fixture**. Exercise bootstrap readiness stubs; watch first-ready trace in game. | No farm scan, GUI or observer attaches before ready single-player mission. | Startup readiness and initialization events. |
| LIFE-002 | Initialize exactly once and capture early load anchor | **manual**. Load a saved ledger; compare startup/resume trace and first checkpoint. | One observer/screen per mission; clean saved anchor resumes before game time advances. | Readiness, hook installation and resume records. |
| LIFE-003 | Mission with active farm other than ID 1 | **manual**. Use a naturally available non-1 farm/save; otherwise fixture only. | All sections and history use the resolved active farm, never a fixed ID. | Farm ID/source in every checkpoint. |
| LIFE-004 | Normal unload cleans owned resources | **manual**. Exit to menu with bank open and closed, then load another save. | Inputs, GUI/focus, commands, hooks and cached mission references release; native controls remain usable. | Teardown and next initialization trace. |
| LIFE-005 | Second save in same process | **manual**. Load new and established saves sequentially without restarting FS25. | Only second save assets/ledger appear; no duplicate actions, transaction events or callbacks. | Checkpoint mission/session IDs, event counts. |
| LIFE-006 | Remappable action rebuilds without duplicates | **manual**. Rebind Open Lizard Bank, apply twice, test old/new binding. | One press opens once after binding changes; other native bindings still work. | Input registration/removal and open events. |
| LIFE-007 | Single-player restriction and dedicated-server guard | **fixture**. Inspect manifest and run forced-mode stubs; real MP only if naturally reproducible. | MP/dedicated execution stays inactive and graceful; manifest declares single-player. | Mode/disabled reason, fixture output. |
| LIFE-008 | GUI initialization failure and focus restoration | **fixture**. Fixture missing/load-failing GUI paths. | Prior GUI focus is restored; no repeated frame retries, leaked controllers or stale report. | Initialization error and cleanup records. |
| LIFE-009 | Coexistence with later input/load wrappers | **fixture**. Exercise cooperative wrapper fixtures; repeat with actual installed mods when present. | Native behavior and later mod wrappers survive unload; detached observer cannot resurrect. | Wrapper ownership/removal and fixture output. |
| LIFE-010 | Replacement or unavailable farm object | **fixture**. Fixture same-ID replacement, different ID and missing farm transitions. | Old farm hooks release; replacement resolves dynamically; unavailable farm clears stale report. | Farm-change, hook and gap events. |
| LIFE-011 | Public openReport and console opener | **manual**. Use binding and lbOpen; exercise direct entry in local stub. | Open action, lbOpen and openReport share one screen and capture contract. | Open origin/capture sequence. |
| LIFE-012 | Observer and diagnostics preserve game behavior | **manual**. Compare quiescent before/after repeated open/Refresh/Policy with time paused where possible. | Bank actions do not change cash, debt, ownership, calendar or native transaction count. | Before/after snapshots and native Finance readings. |

## GUI: Native window, controls and report presentation

Related local checks: [tests/test_report.lua](../tests/test_report.lua). Their latest execution status is recorded in [VALIDATION.md](VALIDATION.md).

| ID | Scenario | Required evidence / setup | Expected oracle | Log / supporting evidence |
| --- | --- | --- | --- | --- |
| GUI-001 | Mouse navigation and Back/Close | **manual**. Use every button, close and resume movement/driving. | Open, Refresh, Policy, pages and Close respond; cursor and player controls restore. | Open/close/click trace and visual observation. |
| GUI-002 | Keyboard navigation and remapped open key | **manual**. Navigate without mouse; test Right Ctrl+B and chosen remap. | Focus order reaches all controls; native Back closes; no stuck controls. | Input trace plus manual focus result. |
| GUI-003 | Controller navigation and action glyphs | **manual**. Use controller through first/last page and close. | Native focus, glyphs, page/Refresh/Policy and Back work on an actual controller. | Manual controller/device evidence. |
| GUI-004 | Page boundaries and large report completeness | **manual**. Inspect largest available save and local long-report fixture. | Every asset/issue remains reachable; first/last page controls stay focusable; no clipped lines. | Page counts, full checkpoint and screenshots. |
| GUI-005 | Capture triggers and stale-failure replacement | **runtime**. Compare capture sequence across actions; fixture a capture failure. | Open/Refresh/Policy capture once; page navigation does not scan; failed capture replaces old data. | Capture reasons/counts and report status. |
| GUI-006 | Native currency, area, volume and custom units | **manual**. Change normal unit/currency settings if available and compare same values. | Displayed formatting matches game settings; custom units are not relabeled liters. | Raw snapshot values/unit labels and screenshots. |
| GUI-007 | English localization and fallback safety | **fixture**. Run localization fixtures; inspect GUI under installed game language. | Mod-scoped text resolves; missing/malformed translations fall back legibly without crashes. | Localization fixture output, GUI text. |
| GUI-008 | Long names, mixed IDs and Unicode | **fixture**. Run long/Unicode/mixed-ID report fixtures; inspect naturally long names. | Names wrap within page budget; sorting is deterministic; no source objects leak. | Rendered page strings and screenshots where available. |
| GUI-009 | Zero, unavailable, partial and excluded wording | **manual**. Compare empty new save, populated save and any unsupported source. | Verified empty/zero differs visibly from unknown; omitted items and limits are stated. | Status fields, issues and displayed labels. |
| GUI-010 | Policy button cycles using native controls | **manual**. Cycle with mouse, keyboard and controller; compare source figures. | Standard to Strict to Lenient to Standard; only model policy changes; absent evidence never creates score. | Mode changes, assessment reasons and unchanged source data. |
| GUI-011 | Report release on close and reload | **fixture**. Run screen lifecycle fixture; reopen after save switch. | Screen drops pages/snapshot on close; new mission does not show old report. | Screen lifecycle/capture events. |

## SNAP: Snapshot integrity, finance and coverage

Related local checks: [tests/test_data.lua](../tests/test_data.lua), [tests/test_report.lua](../tests/test_report.lua). Their latest execution status is recorded in [VALIDATION.md](VALIDATION.md).

| ID | Scenario | Required evidence / setup | Expected oracle | Log / supporting evidence |
| --- | --- | --- | --- | --- |
| SNAP-001 | Cash getter, fallback and native UI reconciliation | **manual**. Read native Finance and compare lbValidate; optionally lbExpect cash value. | Accepted finite cash equals Finance within native display precision; chosen source is named. | Cash read/decision trace, expectation provenance. |
| SNAP-002 | Debt getter, fallback and native UI reconciliation | **manual**. Compare Finance before/after borrow and repay; lbExpect debt value. | Accepted finite nonnegative native loan equals Finance; external borrowing is not inferred. | Debt read/decision trace and native loan deltas. |
| SNAP-003 | Zero and negative cash versus unavailable debt | **fixture**. Run finite/zero/fallback fixtures; natural zero cases if available. | Zero cash/debt and negative cash stay valid; missing, negative debt and nonfinite data stay unknown. | Value/status/source fields. |
| SNAP-004 | Getter and raw-field disagreement | **fixture**. Inject conflicting getter/field values in local fixtures. | Source precedence stays explicit and diagnostics flag mismatch; no silent averaging. | Getter-field checks and selected source. |
| SNAP-005 | Dynamic identity and invalid/spectator identities | **fixture**. Fixture missing manager, invalid/spectator IDs and fallback route. | Unresolved farm cannot attribute assets/history; name is optional; no fake farm 1. | Farm source, capabilities and FARM_UNAVAILABLE. |
| SNAP-006 | Dated detached snapshot and version metadata | **runtime**. Capture then mutate test source objects; inspect live checkpoint metadata. | Farm, raw game date, game/mod/model/schema versions and source metadata accompany plain copied values. | Checkpoint headers, schema and source fields. |
| SNAP-007 | Calendar source fallback and absent date | **fixture**. Run calendar precedence/absence fixtures. | Monotonic day wins; fallback remains labeled; missing date stays unknown rather than invented Gregorian date. | capturedAt and calendar capability fields. |
| SNAP-008 | Failure isolation at accessor, record and section | **fixture**. Run throwing/malformed records and whole-section fixtures. | One failed source leaves healthy neighbors and explicit issue; stale successful values are not reused. | Collector failure boundaries, partial statuses. |
| SNAP-009 | Aggregate arithmetic and overflow | **runtime**. Compare logged item sums and subtotal checks; run overflow fixtures. | Partial sums equal known eligible values; no NaN/infinity or unknown-to-zero conversion. | Arithmetic invariant results and values. |
| SNAP-010 | Coverage and valuation scope | **manual**. Compare report subtotal to supported item values and disclosures. | Land/equipment/buildings subtotal remains partial; cash, inventory and animal quotes are not double-counted. | Subtotal ingredients and coverage issues. |
| SNAP-011 | Capture repeatability and no economic writes | **fixture**. Run immutable-source fixtures and side-effect sentinels. | Identical inputs give equivalent detached data; collector calls no mutation APIs. | Fixture output and repeated checkpoint differences. |

## LAND: Owned farmland

Related local checks: [tests/test_data.lua](../tests/test_data.lua). Their latest execution status is recorded in [VALIDATION.md](VALIDATION.md).

| ID | Scenario | Required evidence / setup | Expected oracle | Log / supporting evidence |
| --- | --- | --- | --- | --- |
| LAND-001 | Strict parcel ownership versus access permission | **manual**. Compare map ownership, accessed contract parcel and report. | Only actual active-farm owners count; contractor/access-only land is excluded. | Parcel owner decisions, IDs and native map evidence. |
| LAND-002 | Parcel identifiers, whole area and configured prices | **manual**. Inspect known parcels in map/native data and bank; do not equate field area with parcel area. | IDs match parcels; area is whole parcel hectares; value is configured current price with source label. | Land item values, source fields and screenshots. |
| LAND-003 | Buy/sell land refresh and capital movement | **manual**. Buy then sell affordable parcel on disposable save, refresh after each. | Owned list/count updates after transaction; actual cash delta is capital; no stale parcel. | Ownership decisions, transaction and snapshots. |
| LAND-004 | Duplicate aliases and mixed IDs | **fixture**. Run duplicate/mixed-key registry fixtures. | Same parcel ID counts once; distinct parcels remain separate and deterministically ordered. | Dedup checks and item counts. |
| LAND-005 | No land versus unavailable enumeration | **fixture**. Run empty/missing registry fixtures. | Verified empty list yields zero; missing manager/list/owner API yields unavailable. | Capabilities, status and total fields. |
| LAND-006 | Unvalued/unknown-owner/malformed parcel | **fixture**. Run bad ownership, price, area and record fixtures. | Unknown owner omitted explicitly; owned unpriced/unmeasured parcel listed without invented values; healthy parcels survive. | Issues, unknown counters and item statuses. |
| LAND-007 | Land subtotal numeric limits | **fixture**. Run extreme/negative/nonfinite area-price fixtures. | Finite known item sums are retained; overflowing totals are unavailable. | LAND_TOTAL_OVERFLOW and absent invalid total. |

## VEH: Equipment and implements

Related local checks: [tests/test_data.lua](../tests/test_data.lua). Their latest execution status is recorded in [VALIDATION.md](VALIDATION.md).

| ID | Scenario | Required evidence / setup | Expected oracle | Log / supporting evidence |
| --- | --- | --- | --- | --- |
| VEH-001 | Owned fleet and attached implements count once | **manual**. Compare garage list and attach/detach one implement before Refresh. | Every owned registered machine/implement appears once, attached or detached. | Equipment identities, dedup decisions and counts. |
| VEH-002 | Leased machines and return | **manual**. Lease inexpensive implement, refresh, return, refresh. | Leased rows are labeled and excluded from owned value; returning removes them. | State decisions, leased count and value subtotal. |
| VEH-003 | Mission borrowed equipment | **manual**. Accept suitable equipment-borrowing contract on disposable save; inspect/report then return. | Contract/borrowed equipment stays separate and never inflates owned collateral. | Borrowed state, contract screen and subtotal. |
| VEH-004 | Other farm and unknown ownership | **fixture**. Run ownership fixtures; compare naturally shared/modded assets if present. | Other known owners excluded; unknown owner omitted with issue; access is irrelevant. | Owner checks and omission issues. |
| VEH-005 | Native sale quote and contents warning | **manual**. Compare garage/workshop sale quote for empty and loaded trailer without assuming sale-channel fees equal. | Quote uses native getSellPrice once; warn contents may be included; do not add stock money. | Read source, quote value, contents flag and quote screenshot. |
| VEH-006 | Buy/sell and transaction amount versus quote | **manual**. Buy affordable item, compare quote, sell and refresh. | Purchase/sale updates fleet; recorded capital movement equals actual cash delta even if quote/channel differs. | Transaction delta, quote and asset removal. |
| VEH-007 | Pallet, big bag, train and ridden-horse exclusions | **manual**. Inspect existing pallet/big bag/train and ridden horse when available. | These objects do not become ordinary equipment collateral; goods/riding exclusions remain visible. | Equipment exclusion decisions and inventory/animal coverage. |
| VEH-008 | Missing enumeration/state constants and unknown property | **fixture**. Run fallback/missing-enum fixtures. | Fallback registry disclosed; absent enum never assumes numeric values; unknown state listed unvalued. | Registry source, capabilities and unknown-state issue. |
| VEH-009 | Quote failure, zero, all unvalued and empty fleet | **fixture**. Run quote and empty-fleet fixtures. | Zero quote valid; failed/negative/nonfinite quote unknown; all unknown not zero; verified empty is zero. | Quote status, unknown counts and subtotal. |
| VEH-010 | Deletion, duplicate ID and missing ID | **fixture**. Run registry/deletion/ID fixtures. | Removing object omitted; duplicate identity once; no-ID objects get snapshot-local labels without dropping independent implements. | Dedup/omission events and item list. |
| VEH-011 | Overflow and custom accessor isolation | **fixture**. Run malformed/throwing/extreme quote fixtures. | Bad custom object does not suppress healthy fleet; overflowing subtotal unknown. | Record errors and subtotal checks. |

## PROP: Buildings and placeables

Related local checks: [tests/test_property.lua](../tests/test_property.lua). Their latest execution status is recorded in [VALIDATION.md](VALIDATION.md).

| ID | Scenario | Required evidence / setup | Expected oracle | Log / supporting evidence |
| --- | --- | --- | --- | --- |
| PROP-001 | Owned registered buildings and production placeables | **manual**. Compare construction/owned production screens and bank. | Only active-farm owned registered placeables appear once; land access is insufficient. | Placeable owner, ID and enumeration trace. |
| PROP-002 | Engine monetary value and temporary refund distinction | **manual**. Place affordable structure, inspect immediate refund/sale UI and bank value, then inspect later. | Display getMonetaryValue basis, not inferred purchase cost or temporary construction refund. | Value source, quote and native screen evidence. |
| PROP-003 | Sale veto and unknown eligibility | **manual**. Inspect a native restricted placeable or fixture if unavailable. | canBeSold false/unknown remains advisory; value is never promised net sale proceeds. | Sale eligibility read and caveat. |
| PROP-004 | Build/sell refresh and removed storage aliases | **manual**. Build/sell affordable empty storage on disposable save and refresh after completion. | Sold placeable disappears; its old stores/counterparts cannot reappear via other registries. | Deletion/alias decisions, property and inventory snapshots. |
| PROP-005 | Duplicate objects and registered lookup fallback | **fixture**. Run duplicate/fallback fixtures. | Object/unique-ID aliases count once; documented placableByUniqueId fallback is labeled. | Enumeration and duplicate counts. |
| PROP-006 | Empty versus unavailable buildings | **fixture**. Run empty/missing-system fixtures. | Verified no supported buildings gives zero; absent registry/farm gives unavailable. | Status/count/total fields. |
| PROP-007 | Zero and invalid/missing monetary values | **fixture**. Run quote validation and healthy-neighbor fixtures. | Zero valid; negative, nonfinite or throwing value leaves explicit unvalued row. | UnknownValueCount and accessor issues. |
| PROP-008 | Removing/malformed records and unsafe names | **fixture**. Run removal/invalid metadata fixtures. | Deleting and malformed records stay isolated; non-scalar identifiers/names never leak references. | Record issues and detached row output. |
| PROP-009 | Property total overflow and detached refresh | **fixture**. Run overflow/detachment fixtures. | Overflow unavailable; refresh does not retain old object/value references. | Subtotal checks and fixture output. |

## INV: Stored goods, fill units and attribution

Related local checks: [tests/test_inventory.lua](../tests/test_inventory.lua). Their latest execution status is recorded in [VALIDATION.md](VALIDATION.md).

| ID | Scenario | Required evidence / setup | Expected oracle | Log / supporting evidence |
| --- | --- | --- | --- | --- |
| INV-001 | Silo/extension storage attribution and transfers | **manual**. Compare silo screen; transfer a known amount to trailer and back, refreshing at each settled state. | Contents follow verified storage owner; registry aliases/extension do not duplicate quantity. | Location/fill/unit/owner trace and quantity deltas. |
| INV-002 | Owned finalized production inventory | **manual**. Compare an existing production inventory and supported purchase/transfer. | Dedicated storage follows owned finalized production; unfinished/nonowned sources excluded. | Production finalization/owner decisions and quantities. |
| INV-003 | Loaded owned and leased containers | **manual**. Load a known quantity in owned or leased trailer; compare native HUD. | Quantity remains at correct container; leased label shown; cargo title stays unverified even in owned container. | Fill-unit reads, container state and cargo warning. |
| INV-004 | Pallet/big bag multi-unit stock | **manual**. Compare existing pallet/big bag contents then move/store it. | Every supported unit appears once with its actual fill type/unit; goods are not equipment value. | Unit-level snapshot and exclusion decisions. |
| INV-005 | Native custom unit and missing fill metadata | **fixture**. Run custom-unit and absent-manager/type fixtures. | Custom unit text retained; known quantity survives absent metadata without inventing liters or crop identity. | unit/unitText/fillType status and issues. |
| INV-006 | Verified zero versus invalid quantity | **fixture**. Run zero/invalid/throwing fill-unit fixtures. | Empty supported compartments count as zero; missing/negative/nonfinite contents stay unknown. | zeroCount, unknownCount and quantityStatus. |
| INV-007 | Missing registry and narrow fallback coverage | **fixture**. Run missing storage/placeable/vehicle system fixtures. | Supported direct adapters survive missing generic registry; absent section never claims full inventory coverage. | Coverage by source and registry capability flags. |
| INV-008 | Cargo ownership and monetary nonduplication | **runtime**. Inspect current snapshot/report and compare owned-assets calculation. | Container ownership never proves cargo title; inventory quantities never add to monetary subtotal. | cargoOwnership, includedInAssetQuote and subtotal checks. |
| INV-009 | Tree-planter mounted pallet proxy | **manual**. Inspect mounted native planter/pallet if available; missing registry remains fixture-only. | Mounted sapling pallet counted once; planter proxy excluded; missing actual pallet is a gap. | Proxy decisions and missing-pallet issue. |
| INV-010 | Storage/vehicle deletion signals and stale aliases | **fixture**. Run sold/removing object alias fixtures. | All supported deletion flags/getter paths prevent stale stock; healthy storage remains. | Removal and alias decisions. |
| INV-011 | Unknown owner/property and borrowed container | **fixture**. Run owner/state/borrowed fixtures. | Unknown owner/state omitted with explicit gap; mission-container stock is excluded. | Ownership decisions and coverage issues. |
| INV-012 | Quantity source failure isolation and DTO order | **fixture**. Run malformed/accessor/detachment fixtures. | One failed compartment/source leaves neighbors intact; outputs are scalar detached tables in deterministic order. | Collector boundary events and fixture output. |
| INV-013 | Ground heaps and unsupported crop/timber scope | **manual**. Review report on save with such assets; no inferred financial value. | Ground heaps, standing crops/timber and unsupported stocks stay explicitly outside quantity/asset coverage. | Coverage disclaimer and item inventory. |

## BALE: Bales, stored objects and handling transitions

Related local checks: [tests/test_stored_objects.lua](../tests/test_stored_objects.lua), [tests/test_inventory.lua](../tests/test_inventory.lua). Their latest execution status is recorded in [VALIDATION.md](VALIDATION.md).

| ID | Scenario | Required evidence / setup | Expected oracle | Log / supporting evidence |
| --- | --- | --- | --- | --- |
| BALE-001 | Native loose bales and raw/wrapped item registry | **manual**. Inspect existing bale count/contents; compare a loose bale before/after moving. | Real owned registered bales give current fill type/quantity once; unrelated items ignored. | Bale class, registry shape and quantity trace. |
| BALE-002 | Contract, other-owner and unknown-owner bales | **manual**. Inspect naturally available contract bale; fixture missing owner. | Contract/other-farm bales excluded; unknown title explicitly unavailable, never presumed owned. | Mission/owner exclusion decisions. |
| BALE-003 | Loaded or unsellable bale remains current quantity | **manual**. Load/unload an existing bale, refresh when settled. | Physical bale on loader is still counted once even if cannot currently be sold. | Bale registration, handler proxy exclusion and quantity. |
| BALE-004 | Fermentation progress and current crop identity | **manual**. Inspect fermenting and completed bale if available; invalid progress fixture. | Actual current fill type and valid progress shown; future silage quantity/value not invented. | Current fill, fermentation status and source. |
| BALE-005 | Object storage real counterpart and all aliases | **manual**. Store then retrieve existing supported object, refreshing after each. | Stored bale/pallet counts once at storage location across item/vehicle aliases. | Real-counterpart identity, location and dedup trace. |
| BALE-006 | Pure virtual and unknown object-storage records | **manual**. Inspect native storage with no readable real counterpart; use fixture if absent. | Known object count retained, unavailable quantity explicit; UI text never parsed into invented liters. | Stored-record shape, count and unknown quantity issue. |
| BALE-007 | Stored counterpart ownership differs from building | **fixture**. Run counterpart owner and stale-alias fixtures. | Foreign/unknown counterpart is not attributed solely because building is owned; loose aliases remain blocked. | Ownership/block decisions. |
| BALE-008 | Loader count and straw-blower mirrored fill unit | **manual**. Inspect available loader/blower, including partial consumption. | Handler count/proxy does not duplicate physical bale; independent fuel/buffer contents remain. | Skipped unit reasons and registered bale checks. |
| BALE-009 | Round baler chamber transition | **manual**. Create/discharge native round bale when feasible; otherwise unexercised. | Transient chamber bale quantity omitted with gap; discharge/settle restores supported quantity without duplication. | Chamber omission and before/after quantity trace. |
| BALE-010 | Square baler and independent material/buffer | **manual**. Inspect existing square baler/material; fixture if unavailable. | Independent material/buffer remains; round-baler exclusion does not erase square-baler contents. | Per-unit proxy decision and quantity source. |
| BALE-011 | Missing class/registry, removed storage and bad getters | **fixture**. Run missing registry/class and failure fixtures. | Missing native Bale support differs from verified empty; failures/deletions isolated, no invented stock. | Coverage capabilities, removal and getter errors. |
| BALE-012 | Shape sampling limits and detached diagnostics | **fixture**. Run capped-shape/detachment fixtures. | Diagnostic samples are capped; native objects/metatables do not escape or execute during serialization. | Explicit sampling/truncation and fixture output. |

## ANI: Husbandry livestock

Related local checks: [tests/test_animals.lua](../tests/test_animals.lua). Their latest execution status is recorded in [VALIDATION.md](VALIDATION.md).

| ID | Scenario | Required evidence / setup | Expected oracle | Log / supporting evidence |
| --- | --- | --- | --- | --- |
| ANI-001 | Owned husbandry groups and current counts | **manual**. Compare animal screen on established save; optionally lbExpect animalsCount value. | Owned registered husbandries/groups match animal screen; every distinct group counted once. | Husbandry owner/group count trace and expectation. |
| ANI-002 | Native per-animal quote multiplied once | **manual**. Compare group/count and native quote screen, recording UI fees separately. | Reference total equals native unit quote times verified group count; no extra fee/transport deduction. | Unit quote, count, valueSource and total. |
| ANI-003 | Zero health/count/quote and empty barn | **manual**. Inspect empty supported barn and naturally occurring zero values; fixture unavailable zeros. | Valid zero stays zero; supported empty barn differs from unavailable enumeration. | Health/count/quote statuses and coverage. |
| ANI-004 | Invalid or missing count and getter precedence | **fixture**. Run count/getter precedence fixtures. | Fractional/negative/nonfinite count unknown; raw numAnimals used only when getter absent, never to hide a failed getter. | Getter/field capability and count issue. |
| ANI-005 | Missing quote versus known quantity | **fixture**. Run quote failure and healthy-neighbor fixtures. | Known animal counts survive failed quote; no zero valuation is invented. | Unknown-value count and retained count. |
| ANI-006 | Age/reproduction unverified units | **manual**. Compare report and diagnostic raw fields with native animal screen. | Raw diagnostics stay labeled unverified; no claimed months/percent or fertility projection. | ageRaw/reproductionRaw and capability flags. |
| ANI-007 | Subtype labels and individual horse names | **manual**. Inspect multiple species/groups and named horse when available. | Native localized label/name preserved; missing metadata uses generic name, not guessed breed. | Subtype key/name source and fallback issue. |
| ANI-008 | Transport and riding exclusions | **manual**. Load/unload animal or ride/return horse when available. | Loaded/ridden animals explicitly outside husbandry coverage; ridden horse never equipment collateral. | Animal exclusion flags and equipment exclusion. |
| ANI-009 | Duplicate husbandries/clusters and lookup fallback | **fixture**. Run dedup and registered-lookup fixtures. | Repeated aliases once; separate groups with same attributes stay separate; fallback source named. | Duplicate counters and row identities. |
| ANI-010 | Unknown owner, failed cluster enumeration and deletion | **fixture**. Run ownership/cluster/deletion malformed fixtures. | Unknown title/removal yields gaps; unreadable husbandry adds unavailable group, not fabricated empty barn. | Group issues and status. |
| ANI-011 | Health/metadata validation and overflow | **fixture**. Run invalid-health/metadata/extreme count quote fixtures. | Health outside 0..100 unavailable; optional object values sanitized; overflowing values/subtotals unavailable. | Capabilities, overflow issues and scalar rows. |
| ANI-012 | Animal totals separate and observational behavior | **runtime**. Compare subtotal ingredients and use mutation sentinels in fixture. | Reference quotes never enter covered collateral or operating cash; capture performs no animal/finance updates. | Asset/financial invariant output and source traces. |

## FIN: Retained native finance and category identity

Related local checks: [tests/test_finance.lua](../tests/test_finance.lua). Their latest execution status is recorded in [VALIDATION.md](VALIDATION.md).

| ID | Scenario | Required evidence / setup | Expected oracle | Log / supporting evidence |
| --- | --- | --- | --- | --- |
| FIN-001 | Retained current Finance category reconciliation | **manual**. Compare Finance screen at paused time to named checkpoint. | Raw amounts/signs/zeros and native labels match observed Finance rows; exact source and slot recorded. | finance source, category key, raw value and screenshot. |
| FIN-002 | Retained history slot semantics stay unverified | **manual**. Record native slot keys alongside UI; inspect labels and model input provenance. | No inferred date/order/retention/padding/completeness from slot index or save age. | Raw slot metadata and verification flags. |
| FIN-003 | Stats candidate precedence and farm ownership | **fixture**. Run mission/farm stats fallback, mismatch and competing-source fixtures. | Select one narrow supported source; no merging conflicting candidates; wrong farm excluded. | Candidate selection, owner and fallback trace. |
| FIN-004 | Empty/missing/padded retained buckets | **fixture**. Run empty/missing/padding fixtures. | Empty or zero-padded rows never become complete zero-activity periods. | Bucket availability and unverified status. |
| FIN-005 | Alias bucket dedup without merging identical independent rows | **fixture**. Run alias and independent-bucket fixtures. | Same object alias once; separate equal-value buckets preserved as distinct raw evidence. | Bucket identity/dedup evidence. |
| FIN-006 | Missing declarations and invalid amounts/keys | **fixture**. Run malformed metadata/key/value fixtures. | Declared missing values unavailable; nonnumeric/nonfinite amounts and non-scalar keys isolated. | Row status and bounds/shape issues. |
| FIN-007 | Unknown categories, numeric keys and label failures | **fixture**. Run category/label/malformed label fixtures. | Unknown/case-varied keys remain unclassified; native labels optional; no substring guesses. | Raw key, native label and classification source. |
| FIN-008 | Retained scan bounds and plain-data export | **fixture**. Run >256 buckets, >512 keys or >8192 records and detached-output fixtures. | Oversized buckets/keys/rows produce explicit truncation; source objects and mutation methods are not used. | Scan-bound issues and included counts. |
| FIN-009 | Live MoneyType exact identity classification | **runtime**. Inspect each available native mapping in the matrix category subcases; perform known sale/purchase/interest, leaving unobserved categories unexercised. | Recognized native identities map to declared operating/capital/financing/interest policy; no guessed numeric constants. | MoneyType names/raw type, classification and actual delta. |
| FIN-010 | Unknown/conflicting alias identities | **fixture**. Run exact identity/alias fixtures. | Unknown or conflicting aliases remain unclassified; equality metamethod cannot spoof identity; same-policy aliases coalesce. | Classifier reasons and fixture output. |
| FIN-011 | Animal and custom finance purpose remains uncertain | **manual**. Buy/sell animal or use known custom transaction if already available. | Unverified-purpose/custom categories remain unknown rather than invented operating/capital certainty. | Raw MoneyType/category and eligibility blocker. |
| FIN-012 | Retained records never become observed events | **runtime**. Compare event/period counts over unchanged repeated captures. | Opening/reloading archived rows does not replay activity or authorize complete ledger history. | Finance provenance versus observed ledger provenance. |

## HIST: Observed gross financial history and calendar

Related local checks: [tests/test_history.lua](../tests/test_history.lua), [tests/test_history_runtime.lua](../tests/test_history_runtime.lua). Their latest execution status is recorded in [VALIDATION.md](VALIDATION.md).

| ID | Scenario | Required evidence / setup | Expected oracle | Log / supporting evidence |
| --- | --- | --- | --- | --- |
| HIST-001 | New and established saves start with partial observation | **manual**. Capture both saves before/after first transactions. | First installed period is partial on both saves; old native rows do not manufacture earlier history. | Initial ledger, first-period completeness and model reasons. |
| HIST-002 | Gross operating inflow and outflow | **manual**. Sell produce and buy supported consumable; compare actual cash changes. | Actual receipts/payments remain separate even if net zero; no nominal-price substitution. | Before/after cash, category, gross totals and reconciliation. |
| HIST-003 | Capital movements and valuation independence | **manual**. Perform affordable buy/sell pair and compare ledger. | Equipment/land/building sales and purchases remain capital; quote changes are not revenue. | Capital inflow/outflow and asset quote snapshots. |
| HIST-004 | Borrow/repay nesting and principal classification | **manual**. Borrow and repay identical native increment; compare both gross legs and event count. | Actual matched cash/debt delta recorded exactly once as financing; repayment not operating expense. | Loan wrapper/native calls, cash/debt deltas and totals. |
| HIST-005 | Interest expense and refund distinction | **manual**. Observe ordinary native charge; refund edge fixture-only if no natural path. | Recognized negative native interest separate; positive/refunded unknown interest never invented negative expense. | Interest identity/direction and class totals. |
| HIST-006 | Requested amount versus actual transaction result | **fixture**. Run clamped/no-op/partial native transaction fixtures. | Ledger uses actual before/after delta, not requested amount; zero actual movement adds no event. | Requested and actual delta fields, event count. |
| HIST-007 | Unexplained cash or debt mutation | **fixture**. Use fixture or naturally reproduced mod conflict; do not inject hidden game state. | Unmatched changes create explicit material gap and withhold eligibility; no balancing fabricated revenue. | Reconciliation/debt-gap events and reason codes. |
| HIST-008 | Nested ambiguous and failed native transaction | **fixture**. Run nested/error/observer-failure fixtures. | Ambiguous nested money stays unknown; native error rethrown; observer recovers and does not double-execute. | Native-call counts, errors and unclassified totals. |
| HIST-009 | Exact argument/return preservation | **fixture**. Run wrapper contract fixtures. | Native methods run once with original arguments and nil-containing return tuple; observer failure cannot swallow result. | Contract fixture assertions and hook trace. |
| HIST-010 | Adjacent native period boundary observed promptly | **manual**. Cross natural midnight at 1x near boundary; inspect within first game minute. | Completed period closes once; next period qualifies only after timely adjacent boundary; installation partial stays partial. | Before/after monotonic day, period, dayTime and completeness. |
| HIST-011 | Native 12 to 1 local-cycle rollover | **manual**. Cross actual native 12-to-1 boundary during extended run. | Local cycle increments once; no Gregorian-year inference or duplicate seasonal slot. | Cycle/period anchors and closed history. |
| HIST-012 | Skipped/late/backward calendar transition | **fixture**. Use normal sleep for late case; skipped/backward synthetic paths remain fixtures. | Sleep that misses opening, skipped day/period or rollback cannot compress gaps into complete history. | Calendar discontinuity/gap and eligibility reasons. |
| HIST-013 | Days-per-period settings change | **manual**. On disposable branch change normal days-per-month setting and wait until effective. | Changed period length invalidates incomparable history and discloses gap. | Old/new daysPerPeriod, retained periods and gap. |
| HIST-014 | Per-farm continuity and observer capability loss | **fixture**. Run farm/capability-loss fixtures. | Switch/missing farm/calendar/cash/hooks does not reuse previous farm history or claim ongoing complete observation. | Capabilities, active farm and material gaps. |
| HIST-015 | Cash reconciliation and tolerance boundary | **runtime**. Check each captured current/closed record; fixture inside/outside tolerance. | Opening cash plus all gross signed flows matches closing cash within 0.01; unknown flows cannot net away evidence gap. | Period arithmetic and unknown-flow checks. |
| HIST-016 | Bounded history/categories/gaps and numeric limits | **fixture**. Run >36 periods, category limit and extreme numeric fixtures. | At most 36 closed periods; bounded categories/gaps; overflow/invalid delta disclosed without nonfinite state. | Counts, overflow/gap markers and fixture output. |
| HIST-017 | Current partial, zero activity and detached report | **fixture**. Run current/idle/detached state fixtures. | Current period never counted complete; idle period is not failed payment; copied report cannot mutate ledger. | Period statuses and fixture output. |

## SAVE: Sidecar persistence and continuity

Related local checks: [tests/test_history.lua](../tests/test_history.lua), [tests/test_history_runtime.lua](../tests/test_history_runtime.lua). Their latest execution status is recorded in [VALIDATION.md](VALIDATION.md).

| ID | Scenario | Required evidence / setup | Expected oracle | Log / supporting evidence |
| --- | --- | --- | --- | --- |
| SAVE-001 | Native save callback writes current directory | **manual**. Save normally, wait for completion; inspect log and final sidecar without moving temporary files. | Sidecar path uses callback-time directory, including tempsavegame, and appears in final savegameN after native success. | Save callback path/write outcome and final-file evidence. |
| SAVE-002 | Clean save/reload preserves exact observed state | **manual**. Save, quit, reload without deliberate advancement, compare named checkpoints. | Same farm/cash/debt/calendar resumes once, including mode, gross categories, event counts and closed periods. | Saved/read anchors, resume decision and equal totals. |
| SAVE-003 | Second save cycle and no duplicate observations | **manual**. Transact, save twice, reload and compare counts. | Further transactions saved/reloaded once; repeated save does not duplicate events. | Save sequence, persisted totals and resume checks. |
| SAVE-004 | Exit without saving discards unsaved bank events | **manual**. On disposable save transact then quit without save and reload. | Native money and bank ledger return to last saved state; Refresh/exit alone writes no sidecar. | Last save/unsaved checkpoint versus reloaded anchor. |
| SAVE-005 | Cross-save/farm isolation in one game process | **manual**. Switch test saves without restarting; save/reload each. | Each save/farm reads its own sidecar; no stale policy or ledger leaks. | Save paths, farm IDs and mission/session IDs. |
| SAVE-006 | Missing sidecar | **manual**. With FS25 closed remove only sidecar on a disposable copy, reload and save. | Missing file starts new partial observation with reason; native save remains playable; normal save recreates file. | Missing-file load note and initial partial ledger. |
| SAVE-007 | Mod disabled during intervening play | **manual**. Disable mod on a copy, change cash/calendar normally, save, re-enable. | Changed anchors prevent silently joining discontinuous history; limitation for identical anchors disclosed. | Anchor mismatch and restart/gap evidence. |
| SAVE-008 | Restored backup or stale copied sidecar | **fixture**. Use fixture mismatches; whole-folder backups for real play. | Cash/debt/calendar/farm/period-length mismatch rejects continuity; same-anchor hidden edits are not claimed detectable. | Mismatch reason with saved/current anchors. |
| SAVE-009 | Exact precision and typed XML round trip | **fixture**. Run typed XML round-trip fixture with fractional large values. | 17-digit numeric strings preserve anchors; no float32 rounding or executable serialization. | Written/read fields and equality assertions. |
| SAVE-010 | Schema, identity, count and ordering validation | **fixture**. Run malformed XML/storage fixtures. | Unsupported schema, invalid identity/count/order/current period are rejected rather than trusted. | Load validation reason and discarded continuity. |
| SAVE-011 | Period amount/category integrity | **fixture**. Run corrupt period/category fixtures. | Negative/nonfinite amount, duplicate category or invalid class rejected; bad cash reconciliation/gaps cannot manufacture complete evidence. | Load status and completeness/reconciliation. |
| SAVE-012 | Missing hooks or native XML APIs | **fixture**. Run missing save/XML functions and absent directory fixtures. | Unavailable persistence stated; no successful-save claim or fabricated fallback file path. | Persistence capabilities and lastSave failure. |
| SAVE-013 | Native save failure and whole-save completion distinction | **fixture**. Run native save failure fixtures; actual fault only if safely reproducible. | Thrown/false native save does not write success; sidecar written never proves final native save completed. | Native result, sidecar result and completion caveat. |
| SAVE-014 | Create/load/write/delete failure and handle cleanup | **fixture**. Run XML failure fixtures without disk-filling or damaging live save. | Failed/zero handle, false/nil save acknowledgement, exceptions release handles and report failure. | Write/read errors and handle counts. |
| SAVE-015 | Policy save scope and read-only native data | **manual**. Change policy, save/reload; unsaved-policy branch optional. | Policy persists only with normal game save; bank changes only its own sidecar and never native economic fields. | Mode, save trace and native figures. |
| SAVE-016 | Save-load hook ordering on real FS25 version | **manual**. Review clean reload trace and final path for both saves. | Load hook resumes before clock movement; real callback directory promotion matches assumptions on recorded game build. | Game version, early-load timing, anchors and save paths. |

## FORE: Seasonal forecast evidence and arithmetic

Related local checks: [tests/test_underwriting.lua](../tests/test_underwriting.lua), [tests/test_history_runtime.lua](../tests/test_history_runtime.lua). Their latest execution status is recorded in [VALIDATION.md](VALIDATION.md).

| ID | Scenario | Required evidence / setup | Expected oracle | Log / supporting evidence |
| --- | --- | --- | --- | --- |
| FORE-001 | Insufficient history produces no fabricated forecast | **manual**. Inspect initial checkpoints under all policies. | New/old save without 12 qualifying observed periods shows reasons and no invented seasonal rows. | Forecast status/window/reasons. |
| FORE-002 | Twelve consecutive complete periods and exact window | **fixture**. Run short/gap/date/duplicate fixtures. | Only 12 immediately preceding complete reconciled periods qualify; arbitrary latest rows/gaps/duplicates do not. | Accepted/rejected window evidence. |
| FORE-003 | Real engine full seasonal observation | **manual**. Run extended ordinary-time route across at least 13 boundaries. | After initial partial plus 12 complete observed periods, actual native ledger can qualify without injected complete flags. | Boundary/save traces and qualified window. |
| FORE-004 | Matching-season repeat and horizon | **manual**. On genuinely eligible save compare 12 forecast rows with observed source rows. | Each next full period repeats matching observed slot; current partial omitted; source slot attached. | Forecast rows, source cycle/period and annual sums. |
| FORE-005 | Gross scenario amounts and excluded flows | **fixture**. Run distinctive seasonal/category fixture. | Project only operating receipts/payments and interest; capital/financing and asset values do not enter seasonal cash. | Projected components and source mapping. |
| FORE-006 | Material gaps, malformed inputs and cross-farm data | **fixture**. Run financial evidence-gate fixtures. | Unverified coverage, wrong farm/date, unknown flows or overflow withholds scenario; no confident fallback average. | Reason codes and absent numeric scenario. |
| FORE-007 | Zero activity and limited confidence | **fixture**. Run complete-idle/shorter-window fixtures. | Verified idle cycle may yield zero repeat scenario but no score; shorter data never annualized. | Forecast confidence, observed subtotal and assessment. |
| FORE-008 | Forecast wording and omitted obligations | **manual**. Inspect forecast on eligible fixture and real eligible save when achieved. | Conditional single-cycle repeat is labeled; no predicted yield/price, ending balance, profit, safe installment or principal coverage. | Assumptions/caveats in report and snapshot. |

## SCORE: Creditworthiness policy and evidence gates

Related local checks: [tests/test_underwriting.lua](../tests/test_underwriting.lua). Their latest execution status is recorded in [VALIDATION.md](VALIDATION.md).

| ID | Scenario | Required evidence / setup | Expected oracle | Log / supporting evidence |
| --- | --- | --- | --- | --- |
| SCORE-001 | No score before evidence gates pass | **manual**. Inspect initial saves and policy cycle. | New, established-only, partial or unavailable data yields no numeric score/band under every policy. | Assessment status, absent score/band and reasons. |
| SCORE-002 | Complete classified reconciled matching-farm evidence | **fixture**. Run missing/category/date/farm/gap gate fixtures. | 12 consecutive complete periods, all gross categories, verified current cash/debt and clear material coverage required. | Eligibility reasons and accepted period count. |
| SCORE-003 | Unknown gross inflows/outflows do not cancel | **fixture**. Run offsetting-unclassified fixture. | Equal unknown inflow/outflow still blocks assessment. | Both gross unknown amounts and blocker. |
| SCORE-004 | Debt with no observed interest and idle year | **fixture**. Run debt-no-interest and idle fixtures. | Positive debt without interest evidence or inactive operating year withholds score; neither gets invented failed grade. | Evidence reasons and absent score. |
| SCORE-005 | Margin component arithmetic | **fixture**. Recalculate independent fixture cases at/inside/outside thresholds. | 35-point operating margin uses operating cash before interest divided by receipts, bounded by mode thresholds. | Component raw value, thresholds, weight and points. |
| SCORE-006 | Cash-buffer component arithmetic | **fixture**. Check negative cash, ordinary costs and verified no-cost special case. | 30-point buffer uses current cash divided by mean monthly operating expense plus interest. | Buffer formula/value/special-case/points. |
| SCORE-007 | Native-interest component arithmetic | **fixture**. Check losses, positive/zero interest and debt evidence boundary. | 20-point interest coverage uses operating cash before interest over native interest; zero-burden case explicit. | Interest formula/value/reasons/points. |
| SCORE-008 | Native-debt component arithmetic | **fixture**. Check zero/positive debt and nonpositive operating cash cases. | 15-point leverage uses debt over positive operating cash; no debt full points; nonpositive cash flow no infinity. | Debt ratio or special status, thresholds and points. |
| SCORE-009 | Score rounding, clamping and bands | **fixture**. Recalculate boundary cases including 49/50/74/75 and saturation. | Finite rounded total stays 0..100; >=75 favorable, >=50 guarded, otherwise strained. | Component sum, final score and band. |
| SCORE-010 | Mode monotonicity and immutable policy thresholds | **fixture**. Run mode ordering and copied-policy fixtures. | Same valid evidence yields Lenient >= Standard >= Strict; returned policy mutation cannot alter future result. | Mode thresholds and score comparisons. |
| SCORE-011 | Real eligible policy control and persistence | **manual**. After real seasonal qualification, cycle controls and save/reload. | Eligible real ledger displays transparent components; cycling mode changes thresholds only; saved mode resumes. | Mode/source snapshots and saved/read mode. |
| SCORE-012 | Capital, financing and collateral independence | **fixture**. Run model isolation fixture with controlled evidence. | Borrowing/capital sales/asset appreciation cannot create operating earnings or direct score points; cash/debt effects remain real. | Operating measures, collateral and component inputs. |
| SCORE-013 | External-liability scope and provisional label | **fixture**. Run options fixture and inspect live native-only default. | Unverified external liabilities make score provisional; suspected material unknown liability withholds score. | Scope flags, provisional status and reasons. |
| SCORE-014 | Negative cash/loss, invalid values and arithmetic overflow | **fixture**. Run loss/cash/overflow fixtures. | Adverse known figures get explicit reasons; missing/nonfinite/overflow cannot become arbitrary bounded score. | Reason codes and unavailable outputs. |
| SCORE-015 | No invented underwriting facts or approval | **manual**. Inspect full assessment and explanations. | Score is transparent internal simulation; no bureau/default probability, payment history, accounting profit, DSCR or lending approval claim. | Model version, scope and unavailable obligations. |
| SCORE-016 | Partial collateral calculation and no stale figures | **runtime**. Compare subtotal/debt ratio to supported values and run stale-value fixture. | Known land/equipment/building quotes separate; inventory/animal/cash duplication excluded; unavailable stale values ignored. | Collateral inputs/status and invariants. |

## DEBUG: Validation instrumentation and analysis

Related local checks: [diagnostic transport](../tests/test_diagnostics.lua), [collector diagnostics](../tests/test_collector_diagnostics.lua), [history diagnostics](../tests/test_history_diagnostics.lua), [independent invariants](../tests/test_validation.lua), and [log analyzer](../tests/test_analyze_log.py). Their latest execution status is recorded in [VALIDATION.md](VALIDATION.md).

| ID | Scenario | Required evidence / setup | Expected oracle | Log / supporting evidence |
| --- | --- | --- | --- | --- |
| DEBUG-001 | Validation-release startup configuration | **manual**. Launch defaults, disable/re-enable, reload with config false on disposable install if needed. | 0.0.8 begins enabled with read tracing; config false or lbDebug off stops diagnostic work without disabling bank. | Configuration/mode transitions and quiet period. |
| DEBUG-002 | Diagnostic commands and invalid input | **manual**. Run each command and invalid mode/empty label variants. | lbDebug on/trace/off/summary, lbValidate label and lbMark label respond without crashing; malformed args are rejected/useful. | Command responses and labeled checkpoints. |
| DEBUG-003 | Automatic capture reasons and bounded frequency | **runtime**. Follow short route and inspect capture reason/count over idle interval. | First-ready/open/Refresh/save/reload/settled transaction/boundary captures are attributable and coalesced, not per-frame full scans. | Capture sequence/reasons/timing and limits. |
| DEBUG-004 | Read provenance, classification and exclusion evidence | **runtime**. Inspect representative successful, missing and excluded source traces; use fixtures for faults. | Trace identifies attempted accessor/field, type/status, fallback and include/exclude reason without extra economic reads. | Read and decision events with source and reason. |
| DEBUG-005 | Full snapshot schema and explicit truncation | **runtime**. Inspect ordinary checkpoint and oversized local fixture. | Bounded checkpoint serialization includes available values/statuses; exceeding limits emits explicit truncation, never silently claims completeness. | Snapshot records, budgets, truncation markers. |
| DEBUG-006 | Manual expectation comparisons | **manual**. Enter one correct native value and one deliberately wrong expectation, then enter the correct value again; retain each checkpoint result. | lbExpect cash/debt/landCount/equipmentOwned/animalsCount records independently read UI value and compares it; user entry is not proof UI correct. | Metric, expected/actual, provenance and result. |
| DEBUG-007 | Scenario catalog completeness accounting | **runtime**. Generate summary for empty and populated saves and review missing groups. | Every catalog ID remains visible with NOT_EXERCISED until warranted evidence; absent asset/path is not automatic PASS. | Catalog IDs, statuses and coverage counts. |
| DEBUG-008 | Internal invariant PASS versus native accuracy | **manual**. Review analyzer output against manual matrix evidence. | Arithmetic/source agreement checks never certify unseen game UI, assets, long periods or arbitrary mod compatibility. | Result scope/provenance and unexercised list. |
| DEBUG-009 | Failure visibility and diagnostic self-protection | **fixture**. Run failing serializer/sink/check fixture where implemented. | Collector/serializer/check exception produces diagnostic failure or unavailable, never swallows native transaction or crashes bank. | Diagnostic errors, native-call preservation and fixture result. |
| DEBUG-010 | Bounded logs, scalar sanitization and stable IDs | **fixture**. Run oversized/cyclic/malformed diagnostic fixtures. | Oversized strings/tables/cycles/metatables stay bounded/sanitized; no retained live refs; order/IDs stable enough to compare. | Budget/cycle markers and deterministic records. |
| DEBUG-011 | Summary counts and non-exercised branches | **runtime**. Compare summary to emitted check results and intentional mismatch. | Summary separates PASS/FAIL/WARN/UNAVAILABLE/NOT_EXERCISED; missing/partial logs cannot collapse into all-pass. | Summary counts, coverage and detected failures. |
| DEBUG-012 | Offline analyzer parses real log and preserves evidence | **manual**. Run tools/analyze_log.py on saved complete Windows log. | Analyzer extracts bank events amid unrelated log lines and emits Markdown/optional JSON with precise findings and checkpoint links. | Analyzer command/output and original log. |
| DEBUG-013 | Analyzer malformed/truncated/repeated-session inputs | **fixture**. Run analyzer fixtures or documented synthetic logs; keep them distinct from Windows evidence. | Bad lines/truncation/duplicate events/session changes are reported or handled without invented evidence; unknown IDs retained. | Parser warnings and session/checkpoint attribution. |
| DEBUG-014 | Diagnostics off/on economy and result equivalence | **fixture**. Compare identical scripted sequence with diagnostics enabled and disabled. | Enabling trace does not call collectors/getters twice, change classification/score, or duplicate transactions/save hooks. | Call counts, snapshots and event deltas. |
| DEBUG-015 | Unload/reload diagnostics lifecycle and command cleanup | **manual**. Use second-save route and compare trace/command registration. | New mission/session identity starts clean; no callbacks or old expectations/checkpoints attach to wrong save. | Teardown, command lifecycle and session IDs. |
| DEBUG-016 | Log collection provenance and reproducibility | **manual**. Save log and analyzer output with route notes/screenshots. | Evidence records ZIP hash, game version, map/mods, settings, save identity and actions; original log retained before next launch. | Evidence bundle metadata and original timestamps. |
| DEBUG-017 | Automatic pure-Lua model and ledger probes | **fixture**. Inspect startup probe results and source isolation; confirm synthetic twelve-period success cannot pass real seasonal qualification. | Run once on detached synthetic input without changing native time, money or history; origin=synthetic and SYNTHETIC_* IDs stay separate from runtime coverage. | Synthetic origin/check IDs, probe result and separate runtime/scenario summaries. |

## Category subcases: FIN-001, FIN-007, FIN-009 and FIN-010

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

## Boundary subcases and source alternatives

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

## Explicit limits and unexercised evidence

- No native UI comparison can prove unenumerated assets are absent. Unsupported
  registry shapes, custom ownership rules and unsupported external finance need
  their own adapter/evidence. Log their absence and preserve partial coverage.
- Inventory is quantity-only and cargo title may be unknown. Ground heaps,
  standing crops/timber and arbitrary external inventories are not claimed;
  virtual objects can expose counts without measurable contents.
- Animal coverage is owned husbandry groups. Transported/ridden animals and
  unverified age/reproduction units remain explicit exclusions or raw diagnostics.
  Reference quotes do not establish sale fees, title, liens or liquidation proceeds.
- Buildings use engine monetary values with advisory vetoes. Land prices and
  vehicle quotes are current game values, not purchase costs, appraisals or a
  guaranteed net sale outcome. Included contents are never valued twice.
- Retained native Finance slots have unverified dates/order/window/padding and
  are never silently imported as complete observed periods. Native calendar slots
  and local cycles are not Gregorian month/year claims.
- History cannot detect every unsupported net-zero mutation between samples,
  identical-anchor external edit or tampered sidecar. Sidecars are local records,
  not tamper-proof financial evidence. Writing one does not certify full native
  save completion; clean real save/reload must be observed.
- A 10–15 minute route does not establish twelve complete periods, all interest
  types, every bale handler, every animal subtype, controller support without a
  controller, or arbitrary mods. Missing cases stay NOT_EXERCISED. Synthetic
  fixtures never become engine evidence; do not inject hidden qualifying state
  or falsify complete-period flags into a real save.
- Forecast/score are transparent conditional simulation policy. External debt,
  accrued profit, bills/receivables/payables, principal schedules, DSCR, calibrated
  default risk and historical payment conduct are not proven. Verify their
  disclosed absence rather than claiming full real-life underwriting coverage.

## Acceptance record

The short route is an initial diagnostic sample, not a release-wide PASS. For
acceptance, every applicable supported scenario needs evidence at its stated
level, meaningful local checks must pass, and any failure must be resolved or
explicitly scoped. Record each unexercised scenario and reason. Eligibility and
seasonal forecast may only be called engine-validated after the real extended
observation path passes. User approval or an overall success message is recorded
as feedback, not substituted for the missing measurements.
