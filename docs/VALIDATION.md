# First-build verification

Version: **0.0.1**. Checked on **2026-09-27** in the macOS development workspace.

| Check | Result | What this establishes |
| --- | --- | --- |
| Lua logic and lifecycle tests | 30 passed, 0 failed | Ownership, missing data, deduplication, totals, report pagination and lifecycle behavior against explicit fixtures |
| Lua syntax | All four runtime files parse in Lua 5.1.5 | Standard Lua syntax compatibility, not GIANTS runtime behavior |
| XML and resource validation | Passed | Well-formed XML, English localization references, exact-case resource paths and declared callbacks |
| Mod icon | Passed | 512 x 512 DXT5 DDS with all ten mipmap levels |
| Packaged ZIP | Passed | Archive integrity, root modDesc.xml and allowlisted runtime files |
| GIANTS TestRunner | Pending | Tool is not installed in this workspace |
| Windows FS25 | Pending | No FS25 game process is available here |

Tests use an isolated Lua 5.1.5 executable built from the official source archive. Its SHA-256 was checked against the [Lua download page](https://www.lua.org/ftp/). The interpreter is not shipped inside the mod.

The documented FS25 APIs and compatibility candidates are distinguished in [data-sources.md](data-sources.md) and [gui-sources.md](gui-sources.md). Reading an API reference is not an in-game verification.

The first milestone remains pending Windows confirmation of native cash/debt access, actual GUI layout, keybind/controller behavior, sale-quote interpretation, and save lifecycle. Follow [WINDOWS_TEST.md](WINDOWS_TEST.md) on both a new save and an existing-save copy. Record the game version and map/mod combination with each result.
