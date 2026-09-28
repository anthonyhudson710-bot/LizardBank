# Build verification

Version: **0.0.5**. Checked on **2026-09-27** in the macOS development workspace.

| Check | Result | What this establishes |
| --- | --- | --- |
| Lua logic and lifecycle tests | 196 passed, 0 failed | Prior asset/report regression coverage plus retained finances, exact money-type classification, gross flow separation, evidence gates, model arithmetic, seasonal matching, XML round trips, invalid anchors, money/save/load hooks and a complete transaction-to-assessment fixture |
| Lua syntax | All fourteen runtime files parse in Lua 5.1.5 | Standard Lua syntax compatibility, not GIANTS runtime behavior |
| XML and resource validation | Passed | Well-formed XML, English localization references, exact-case resource paths and declared callbacks |
| Mod icon | Passed | 512 x 512 DXT5 DDS with all ten mipmap levels |
| Packaged ZIP | Passed | Archive integrity, root modDesc.xml and allowlisted runtime files |
| GIANTS TestRunner | Pending | Tool is not installed in this workspace |
| Windows FS25 0.0.5 | Pending | No Windows run of this version has been observed; native Finance records, lifecycle timing, sidecar promotion, period boundaries and the new Policy button require verification |
| Windows FS25 through 0.0.4 | User-reported success | Earlier overall confirmations; individual checklist results were not supplied |

Tests use an isolated Lua 5.1.5 executable built from the official source archive. Its SHA-256 was checked against the [Lua download page](https://www.lua.org/ftp/). The interpreter is not shipped inside the mod.

The documented FS25 APIs and compatibility candidates are distinguished in [data-sources.md](data-sources.md) and [gui-sources.md](gui-sources.md). Reading an API reference is not an in-game verification.

The v0.0.5 integration fixture starts with insufficient history, observes an
initial partial period and twelve complete seasonal periods, records operating
receipts, operating payments, interest, borrowing and repayment through the
runtime wrappers, and produces the expected seasonal scenario and score. It
resumes the identical result from its saved ledger, then verifies that an
unexplained money mutation withholds both forecast and assessment. Separate XML
fixtures exercise native-style typed storage, finite validation, malformed data,
handle cleanup and unconfirmed write results. These are explicit game stubs,
not recordings from the GIANTS engine.

The early load-completion hook is tested before a simulated first clock update,
including return preservation and cooperative removal. Its availability and
ordering in FS25 1.23.1.0 remain unverified. Save callback presence and a successful
XML write are distinguished from completion of the whole native save. Retained
Finance slot dates/signs/window/padding remain unverified and are excluded from
normalized model input. See [history sources](history-sources.md),
[finance sources](finance-sources.md) and [model policy](underwriting-model.md).

The user confirmed on 2026-09-27 that **v0.0.1 worked**; the supplied log identifies FS25 **1.23.1.0**. This is recorded as user confirmation of the overall first-build outcome, without inventing individual test results or which accessor fallback was used. The original local suite passed 30 tests.

The user also confirmed **v0.0.2 successful** on 2026-09-27. The supplied second log excerpt shows Arkansas 4X loading and a comparison with zero new problem categories. It does not contain an itemized bank diagnostic or prove individual cases. The v0.0.2 local suite passed 68 tests.

After the v0.0.3 package was announced, the user said "succes next". This was treated as overall confirmation of that build, with the interpretation stated to the user. No additional log or individual case results were provided. Its local suite passed 88 tests.

The user explicitly confirmed **v0.0.4 successful** with "success now what" on 2026-09-27. No new diagnostic log or individual checklist results accompanied this confirmation. [WINDOWS_TEST.md](WINDOWS_TEST.md) retains the scenarios for regression testing; unreported cases are not individually marked passed.
