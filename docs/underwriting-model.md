# Forecast and internal eligibility model

`BankUnderwriting.prepare(snapshot, history, options)` is a pure Lua calculation,
model version **1.0.0**. It reads normalized observations, returns copied scalar
reports, and changes no game state, files, loan balances or inputs. The model is
an explicit simulation policy, not a real credit bureau score, calibrated default
probability, or approval to lend. The same input always produces the same result.

## Input contract

The snapshot supplies current `cash` and native `debt`, each with
`status="available"` and a finite `value`. Negative cash is valid; negative debt
is invalid. The existing land, equipment and building quote subtotals are used
only in the separate partial collateral display.

The ledger supplies:

```lua
history = {
    farmId = 7, -- required positive whole farm ID matching snapshot.farm.id
    currentYear = 3,
    currentMonth = 1,
    materialGaps = {}, -- unresolved current financial coverage issues
    periods = {
        {
            year = 2, month = 1,
            complete = true,
            reconciled = true,
            operatingRevenue = 0,
            operatingExpense = 0,
            interestExpense = 0,
            capitalInflow = 0, capitalOutflow = 0,
            financingInflow = 0, financingOutflow = 0,
            unclassifiedInflow = 0, unclassifiedOutflow = 0
        }
    }
}
```

Amounts are finite, nonnegative **gross flows**, not signed net category balances.
Missing values are unknown, including missing zeroes. `operatingExpense` excludes
interest, capital purchases and financing movements. Only verified native
interest expenses belong in `interestExpense`; unidentified borrowing costs are
unclassified. Capital sales and loan proceeds never become operating revenue.
Loan principal repayments are financing outflows, never operating expenses.

`month` means a verified consecutive seasonal slot from 1 through 12. It is not
assumed to mean January through December. The collector owns native-calendar
mapping. A complete month covers its entire duration; installing the mod halfway
through a month does not create a complete month. `reconciled=true` means the
tracker has checked the recorded movements against the observed cash change.
The model does not establish those facts by inspecting arbitrary save data.

The assessment window is the twelve months immediately before the current month.
It is not the latest twelve rows regardless of their dates. Current and future
rows are ignored, old dated duplicates outside the window do not taint a clean
window, and duplicate dates inside it are excluded rather than double-counted.
Malformed dates are an unresolved evidence error. Both the history and snapshot
must identify the same positive whole farm ID; missing, invalid or mismatching
identities block assessment and forecast.

Options:

```lua
options = {
    mode = "standard", -- also lenient or strict; unknown defaults to standard
    externalLiabilitiesKnown = false,
    materialExternalLiabilityUnknown = false
}
```

Unless external liabilities are verified, an otherwise eligible score is marked
`provisional=true`, explicitly limited to native game cash and debt. A suspected
material external liability with unknown amount or payments withholds the score.
This avoids claiming that absence of an external-loan API proves no external
debt, while still allowing a clearly scoped native-game assessment.

## Evidence gates and unavailable results

A score requires twelve consecutive complete, reconciled months with every
category present, no unclassified inflows or outflows, no unresolved material
financial coverage issue, and verified current cash and native debt. It is also
withheld when native debt exists but the window contains no observed native
interest expense: a newly borrowed balance is not evidence of a known financing
cost.

A new save, partial first month, gaps, missing data, nonfinite amounts, arithmetic
overflow or complete year without operating activity produces
`status="insufficient_evidence"`, reason codes and **no score or band**. No
missed-payment history is fabricated. An inactive farm does not receive a failed
grade. A smaller amount of valid monthly data is shown as an observed subtotal,
never silently annualized.

Both unclassified inflows and outflows must be zero independently. Equal unknown
inflows and outflows do not cancel the uncertainty. A complete inactive year can
support a zero-activity repeat scenario but cannot support an eligibility grade.

## Cash measures and score

The calculations are:

```text
Operating cash before interest = operating revenue - operating expense
Cash before principal = operating cash before interest - interest expense
Classified net cash = cash before principal + capital inflow - capital outflow
                      + financing inflow - financing outflow
```

These are cash measures. They do not establish accrual profit, depreciation,
inventory cost of sales, receivables or payables. The returned `profitability`
field therefore remains unavailable. In particular, increased asset values and
cash from liquidation do not establish profitable recurring farm operations.

Each eligible score is the rounded sum of four component points:

| Component | Weight | Calculation |
| --- | ---: | --- |
| Operating cash margin | 35 | Annual operating cash before interest / operating revenue |
| Cash buffer in months | 30 | Current cash / ((annual operating expense + interest) / 12) |
| Native interest coverage | 20 | Annual operating cash before interest / observed native interest |
| Native debt relative to operating cash | 15 | Current native debt / annual operating cash before interest |

For the first three components, points rise linearly from zero at the weak
threshold to the full weight at the strong threshold. Values outside that range
are capped at zero or the full weight. The debt ratio runs in the other direction:
full points at or below the strong threshold and zero at or above the weak
threshold. Returned components include the actual value, formula, thresholds,
weight, points and special-case status.

| Mode | Margin weak → strong | Buffer months weak → strong | Interest coverage weak → strong | Debt ratio strong → weak |
| --- | --- | --- | --- | --- |
| Lenient | 2% → 15% | 0.5 → 3 | 1 → 2 | 2 → 8 |
| Standard | 5% → 20% | 1 → 4 | 1.25 → 3 | 1.5 → 6 |
| Strict | 8% → 25% | 2 → 6 | 1.5 → 4 | 1 → 4 |

The internal bands are **75–100 favorable**, **50–74 guarded**, and **0–49
strained**. They are transparent game-policy thresholds, not empirically
calibrated credit grades. Lenient mode never tightens a threshold relative to
standard, and strict never loosens one.

No revenue gives zero margin points without dividing by zero. No observed cash
cost gives no numeric buffer ratio; its component receives full points only with
nonnegative cash, explicitly tagged `no_observed_cash_cost`. A verified zero debt
balance and zero observed interest give no numeric interest ratio and no native
interest burden. Positive debt with nonpositive operating cash receives zero
leverage points without emitting infinity. A zero native debt balance receives
full leverage points. These special cases do not bypass the evidence gates.

No repayment schedule is available to this model. `principalCoverage` is always
unavailable: interest coverage is **not DSCR**. Positive cash before principal is
not proof that any proposed installment is affordable. Negative operating cash,
negative current cash, and interest not covered receive explicit reason codes;
none is misrepresented as a historical late payment.

## Seasonal scenario

With a complete verified twelve-month window, the forecast repeats the latest
completed observation for each matching seasonal slot. It covers the next twelve
**full** months, excluding the partially elapsed current month. Every row carries
the source year and month. One observed cycle supplies a conditional seasonal
baseline, not established predictive accuracy; confidence is labeled
`limited_single_cycle`.

Only operating revenue, operating expenses, native interest and cash before
principal are projected. The scenario assumes that production scale, sale timing,
prices, costs and interest repeat. It does not predict crop yields, stock
liquidation, capital investment, new borrowing or principal repayment. It does
not use asset appreciation as cash flow. No closing cash balance is forecast,
because intervening activity in the current partial month and future principal
obligations are unknown. Shorter or incomplete history, unchecked financial
coverage, or unresolved material data gaps yield no seasonal scenario. A
suspected external liability separately blocks the score; a clearly limited
native operating scenario may still be shown. Current liabilities not
represented by the native history remain an explicit limitation of that scenario.

## Collateral and integration

Known land, owned-equipment and building quotes appear in a separate partial
collateral subtotal and native-debt ratio. They never add score points. Cash is
not duplicated into this subtotal. Inventory and separate animal reference quotes
are not added because valuation and embedded contents may overlap. These quotes
do not verify liens, external debt, sale eligibility or net liquidation proceeds.

The returned top-level tables are `history`, `forecast`, `assessment`,
`collateral` and `assumptions`, with `modelVersion` and `mode`. The caller may
attach the result to a snapshot for GUI and diagnostics. All returned objects are
detached from the source ledger and snapshot. This model does not read GIANTS
globals and does not provide a loan creation or repayment API.

Local verification: `lua tests/test_underwriting.lua`. Tests exercise policy
arithmetic, seasonal matching, incomplete history, malformed/duplicate dates,
unclassified flows, cross-farm history, unavailable inputs, zero activity,
external-liability gating, overflow, mode ordering and independence from asset
prices, capital proceeds and new borrowing. These tests validate the normalized
contract; they do not establish that a native FS25 history accessor, category
mapping or live tracking hook is correct. Those checks belong to the source
adapter and Windows reconciliation tests.
