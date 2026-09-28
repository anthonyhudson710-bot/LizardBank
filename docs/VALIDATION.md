# Build verification

Version: **0.0.2**. Checked on **2026-09-27** in the macOS development workspace.

| Check | Result | What this establishes |
| --- | --- | --- |
| Lua logic and lifecycle tests | 68 passed, 0 failed | Ownership, missing data, deduplication, totals, quantities, removal, report pagination and lifecycle behavior against explicit fixtures |
| Lua syntax | All six runtime files parse in Lua 5.1.5 | Standard Lua syntax compatibility, not GIANTS runtime behavior |
| XML and resource validation | Passed | Well-formed XML, English localization references, exact-case resource paths and declared callbacks |
| Mod icon | Passed | 512 x 512 DXT5 DDS with all ten mipmap levels |
| Packaged ZIP | Passed | Archive integrity, root modDesc.xml and allowlisted runtime files |
| GIANTS TestRunner | Pending | Tool is not installed in this workspace |
| Windows FS25 0.0.2 | Pending | New building and stored-goods coverage must be checked in game |

Tests use an isolated Lua 5.1.5 executable built from the official source archive. Its SHA-256 was checked against the [Lua download page](https://www.lua.org/ftp/). The interpreter is not shipped inside the mod.

The documented FS25 APIs and compatibility candidates are distinguished in [data-sources.md](data-sources.md) and [gui-sources.md](gui-sources.md). Reading an API reference is not an in-game verification.

The user confirmed on 2026-09-27 that **v0.0.1 worked**; the supplied log identifies FS25 **1.23.1.0**. This is recorded as user confirmation of the overall first-build outcome, without inventing individual test results or which accessor fallback was used. The original local suite passed 30 tests.

The v0.0.2 Windows checks remain pending. Follow [WINDOWS_TEST.md](WINDOWS_TEST.md), focusing on building ownership/value, stock locations and quantities, transfers, removal, and save switching. Record the game version and map/mod combination with each result.
