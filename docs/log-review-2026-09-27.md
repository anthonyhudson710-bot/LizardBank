# Review of the September 27 Windows logs

The submitted gameplay evidence is **Lizard Bank 0.0.6**, FS25 **1.23.1.0**,
Arkansas 4X **1.0.0.1**, single player. It does not validate the later 0.0.7 or
0.0.8 packages. Raw user logs remain local and are not committed or packaged.
Line numbers below refer to the originals before any filtering or formatting.

| Input | Size / evidence | SHA256 |
| --- | --- | --- |
| log.txt | 22,278,922 bytes; 69,038 lines; 67,474 structured records | 363b4761b47842528728cd9ef51717a366ba3935eb39a0c701a2631f870a391c |
| log_2026-09-27_21-58-23.txt | 1,139 bytes; 25 engine-startup lines; no bank events | 97a215daf4c065328ef4ed34f4aa50028e86098e5bc1a724ca9c6e9f3ba62319 |

## Captured evidence

- Eight snapshot captures finish successfully; no JSON/sequence/dump truncation
  or budget exhaustion is detected. The session lacks a bank mission-end event,
  even though the file ends with the game's `#End.` marker. That limits lifecycle
  evidence; it is not proof of a crash.
- Five native money-call lifecycles pair correctly. Four target farm 15 and are
  excluded from farm 1's observed ledger; one farm-1 receipt changes cash by 652
  exactly once (lines 25310–25375). The captured ledger arithmetic reconciles.
- Asset records are unchanged between first and last captures. The observed
  registry decisions support repeatability and exclusion arithmetic, not a
  buy/sell/transfer test or proof that every native asset was enumerated.
- GUI evidence contains all 67 page selections, three successful refreshes and
  a close that clears pages (68558). One page is blank; see the fix below.
  Pixel layout, physical input devices and restored driving remain manual checks.
- The model withholds scores/forecasts; no complete period exists. Synthetic
  probes are separate and provide no native seasonal or save evidence.
- No bank save callback, reload, borrow/repay, period boundary, policy cycle or
  lbExpect native-screen comparison is captured. The smaller startup log cannot
  fill any of those gaps.

## Reproduced issues fixed in 0.0.8

| Finding | Original evidence | Change and local regression |
| --- | --- | --- |
| Recurring property income was unclassified | Actual PROPERTY_INCOME +652 at 25358; retained propertyIncome 4564 at 8423 and 5216 at 31944; material gap at 32341 | Map this exact documented native identity/key to operating under finance-map.v2. Test actual +652, negative gross direction, no-op, ambiguous identities and preservation of old unclassified entries. |
| Blank trailing report page | GUI page 63/67, Stored goods and supplies, has empty text at 50783 | Trim trailing separator-only lines before pagination. Test 1–35 inventory-row counts, each item exactly once, nonblank pages and the 14-line limit. An independent AUTO_GUI_PAGE_TEXT check now rejects empty/whitespace-only pages. |
| History fallback blocked by installed but undispatched callback | Load hook installs at 1024, no load-complete event; observer starts via first_report_fallback at 1856 | Allow first-update fallback even while the candidate hook is installed. Test diagnostics-off/no-open startup and a later callback without duplicate observers. Exact native reload continuity remains unverified. |
| Missing history file mislabeled as failure evidence | history.xml.read succeeded=false, reason Sidecar absent at 1849 | Analyzer keeps expected missing file/API states visible as UNAVAILABLE. Corrupt/read-failed files and explicit FAIL checks still count as failures. |

The new property-income mapping has both captured native evidence and a published
FS25 callsite in [GIANTS' PlaceableIncomePerHour documentation](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=78&class=741&version=engine).
This is an analytical classification; it does not assert all property income is
stable, prove native UI labels/dates, or qualify the farm for underwriting.
Existing saved unknown flows are deliberately not reclassified retroactively.

## Unresolved adapter coverage

- **Loan observation:** `changeLoan` is unavailable at 1853/8765. Cash and debt
  getters do work. No loan transaction occurred, so neither an alternative
  native path nor correct borrow/repay classification is established.
- **Loose bales:** the native Bale class exists (7941), but the chosen
  mission.itemSystem.items registry is unavailable (7942–7943). Inventory is
  explicitly partial (9371–9372). This is not evidence of zero loose bales.
- **Other Finance names:** 14 rows were unclassified in the captured v1 policy,
  including propertyIncome and other actual native keys. Only the property-income
  path above is resolved by this patch. Other keys need source/purpose evidence;
  zero-valued rows alone do not validate transaction behavior or window semantics.
- **Load/save order:** no accepted saved anchor is exercised. The fallback fix
  prevents a stalled observer; it does not prove temporary-save promotion,
  callback timing, exact saved-time resumption or cleanup on another save.

After correcting the analyzer's missing-file classification, this log has zero
explicit failed-check/error records and one unavailable-history-source record.
That does **not** erase the blank-page/mapping defects found by reviewing data
and page text. Transport integrity remains INCOMPLETE due to missing mission-end
evidence. Internal PASS counts are not release acceptance.

Other game warnings include Courseplay XML, map foliage/material and rice-field
messages. They are retained in the analyzer output, not automatically attributed
to Lizard Bank. No Lizard Bank Lua stack trace was found in these inputs.

## Focused follow-up

Install the 0.0.8 ZIP on a disposable copy. Capture another natural property-income
payment; verify operating receipt and retained category change, then open/Refresh
and visit the previous inventory boundary. Borrow and repay one native increment
and preserve the log even if the observer reports a gap; the unsupported native
loan path still needs evidence, not an assumed pass. Save normally, wait for native
completion, return to menu and reload; finally return to menu before exiting and
preserve the full log. Use the complete [test.md](../test.md) for remaining cases.
