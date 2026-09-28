# Retained native finances and classification

The retained-finance collector preserves native signed category values for inspection. It does not turn undocumented array positions into months, reconstruct transactions, identify padding by its zero values, or claim that the retained window covers the farm's life. It remains separate from Lizard Bank's observations recorded after installation.

## Evidence and compatibility boundary

The reviewed public FS25 documentation does not expose enough of FarmStats, FinanceStats, MoneyType initialization, or the Finance screen to verify the retained layout, category sign convention, calendar labels, retention limit, or padding behavior. Successful reads therefore remain compatibility candidates until compared with the installed game's Finance screen.

| Source | What it establishes |
| --- | --- |
| [FS25 PlayerSwitchedFarmEvent](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=1&class=98&version=script) | The current engine resolves a specific farm through `g_farmManager:getFarmById(id)`. The collector uses the snapshot's resolved farm ID and never assumes farm 1. |
| [FS19 FarmStats](https://gdn.giants-software.com/documentation_scripting_fs19.php?category=12&class=131&version=script) | **Legacy evidence, not an FS25 contract:** `finances` holds category values and `financesHistory` holds retained FinanceStats objects. Archive and save routines explain why an array key need not be a calendar day. These narrow field names motivate the guarded candidates. |
| [FS19 FinanceStats](https://gdn.giants-software.com/documentation_scripting_fs19.php?category=12&class=132&version=script) | **Legacy evidence:** category names and labels use `statNames` / `statNamesI18n`; construction initializes category zeros. A zero row alone therefore cannot establish that a period was observed or completed. |
| [FS25 FillUnit](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=78&class=672&version=script), `addFillUnitFillLevel` | An actual FS25 transaction passes `MoneyType.SOLD_PRODUCTS` to `mission:addMoney`. This supports matching the runtime category token, without guessing its numeric value or internal field layout. |

The general printable GIANTS reference mixes reference generations and is not used to promote an accessor to verified FS25 status. No forum code is treated as an engine contract.

## Narrow read paths

`BankFinanceDataSource.collect(snapshot, context)` tries `mission:farmStats(activeFarmId)`, then the resolved farm's `stats` and `farmStats` fields. These stats paths are marked as FS25 compatibility candidates. It selects the first candidate exposing a table at `finances` or `financesHistory`; it never merges competing sources. An explicit conflicting `farmId` rejects a candidate.

Only the selected stats object's `finances` and `financesHistory` maps are scanned. There is no recursive object-graph inspection, saved-file scraping, history archiving, queue flushing or economic mutation. Required context globals are `g_currentMission` and/or `g_farmManager`; optional `FinanceStats` and `g_i18n` provide runtime category lists and labels.

Within a retained bucket, declared category names are combined with observed scalar keys. Missing declared values become unavailable rows. Unknown keys are preserved, including numeric keys; they are not assigned an invented meaning. Tables, functions and nonfinite values are never numeric financial evidence. Direct method members are ignored unless a runtime category list explicitly declares that key.

## Returned data

`snapshot.finance` contains:

- `records`: flat category rows with the original `categoryKey`, key type, label and label source, `rawSignedValue` when finite, value status/type, classification and provenance, source, bucket ID/kind, and native `periodKey` / type.
- `buckets`: detached descriptors containing source, raw key, observed row counts, status, and raw scalar metadata.
- `metadata`: only named date-like fields and finance version counters copied from the selected stats object. Their presence does not verify their meaning.
- Known/unknown value counts, unknown/duplicate bucket counts, unclassified counts, ignored-key counts, and an explicit truncation flag.

`verification`, `windowStatus`, and every row's `periodStatus` are `unverified`. Section status is `partial` after a candidate is found, even when individual numeric values are readable. Bucket kinds `currentCandidate` and `historyCandidate` identify the source fields; they do not assert completed fiscal periods. Bucket status `available` means its scanned category numbers were readable, not that its time coverage was verified.

The raw metadata whitelist is `day`, `period`, `year`, `month`, `date`, `currentDay`, `currentPeriod`, `currentYear`, `currentMonotonicDay`, `startDay`, `endDay`, `isCurrent`, `isComplete`, and `isPadding`. They remain diagnostics. An explicitly declared category with one of these names is also retained as an unclassified category row.

All finite signs are preserved exactly. No absolute-value conversion, income/expense sign inversion, total net flow, annualization, missing-slot fill, forecast or debt-service measure is calculated here. An empty observed map is explicitly distinct from a verified zero-valued category. Two independent equal-valued maps remain distinct; aliases of the same bucket object are represented once with a duplicate descriptor. DTOs retain no engine object references.

Scans are bounded to 256 bucket descriptors, 512 keys per scanned map, and 8,192 category rows. Crossing a limit produces an issue and `truncated = true`; it never implies the omitted portion is empty.

## Classification policy and live MoneyType helper

Classification is Lizard Bank policy, identified as `lizardbank.finance-map.v1`, rather than a native accounting guarantee. Only exact names match. Categories are not inferred by substring, capitalization, amount sign, position or translated text.

| Class | Exact retained-category policy keys |
| --- | --- |
| Operating | `soldProducts`, `soldMilk`, `soldBales`, `soldWood`, `harvestIncome`, `missionIncome`, `fieldJobIncome`, `vehicleRunningCost`, `vehicleLeasingCost`, `propertyMaintenance`, `wagePayment`, `purchaseSeeds`, `purchaseFertilizer`, `purchaseSaplings`, `purchaseFuel`, `purchaseWater` |
| Capital | `newVehicles`, `soldVehicles`, `constructionCost`, `boughtFields`, `soldFields`, `soldBuildings` |
| Financing | `loanInterest`, `loanBorrowed`, `loanRepaid` |
| Unclassified | Everything else, including ambiguous animal purchases/sales, miscellaneous income, transfers, balance totals, and custom categories without a policy rule. |

These labels express intended analytical treatment of the named category, not proof that a category exists in the current installation. The FS25 matching and meaning of retained keys must still be reconciled. Finance-screen totals and generic `other` values are never redistributed into guessed classes.

`classifyCategory(rawKey)` returns the broad class and its provenance. `classifyMoneyType(moneyType, moneyTypes)` is a separate helper for the live tracker: it compares the event token to explicitly named constants present in the runtime `MoneyType` table, using raw identity. It returns the policy category key, tracker class, and exact matching constant source. There are no hardcoded numeric enums and no inferred `.statistic` or `.statName` fields.

The live helper separates `LOAN_INTEREST` into the exclusive tracker class `interest`, so the model cannot count the same expense as both operating cost and interest. Vehicle/building/land transaction constants map to capital; product/wood/milk sales and identified routine costs map to operating. Exact loan borrowing/repayment constants map to financing. Animal purchase/sale constants remain explicitly unclassified because breeding assets and trading livestock need a separate policy.

Same-policy aliases coalesce. Conflicting constant identities, `UNKNOWN`, unavailable registries, custom categories, and unmatched tokens return unclassified. Modded equality metamethods cannot manufacture a match. The helper classifies an observed category; it does not prove that the transaction completed or that its passed amount equals the actual balance change. Those are responsibilities of the tracking adapter and its reconciliation checks.

## Windows reconciliation

Capture diagnostics alongside the native Finance screen before and after one known purchase, crop sale, equipment transaction, loan action, and period change. Compare exact raw category keys, native labels, signed amounts, source fields, version counters, and retained bucket keys. Include a new save, an established save, reload, and a non-default days-per-period setting.

Verify separately: which field represents the ongoing period; historical ordering; retention before and after reload; whether rows are preallocated/padded; whether fields aggregate days or months; and which native categories omit transfers or financing. An all-zero row and an index matching a displayed month are insufficient proof by themselves. Until these observations settle the contract, retained records are diagnostic evidence and do not become completed periods in underwriting.

Local tests cover scoped ownership, candidate precedence, signs/zero/unavailable data, raw metadata, aliases versus distinct equal buckets, malformed records, scan bounds, detached DTOs, and exact MoneyType classification with exclusive interest. They do not replace these runtime comparisons.
