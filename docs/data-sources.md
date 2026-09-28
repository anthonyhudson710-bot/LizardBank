# Snapshot sources and evidence

This file separates published FS25 evidence from compatibility candidates. On 2026-09-27 the user confirmed that v0.0.1 worked in FS25 1.23.1.0. This confirms the reported overall result, not which getter/fallback supplied each value; no complete diagnostic trace or per-case result was retained. Local injected tests validate collector behavior, not engine compatibility. The v0.0.2 additions await Windows verification.

| Input | Read path | Evidence and meaning |
| --- | --- | --- |
| Active farm | `mission:getFarmId()`, then `g_localPlayer.farmId` if absent | Both appear in published FS25 code. Resolved on every capture; no fixed single-player farm ID. |
| Farm object | `g_farmManager:getFarmById(id)` | Published FS25 events use this lookup. |
| Cash | `farm:getBalance()`, then `farm.money` | **Compatibility candidates awaiting Windows verification.** Only finite numbers accepted. Negative cash is valid; zero is distinct from unavailable. |
| Native debt | `farm:getLoan()`, then `farm.loan` | **Compatibility candidates awaiting Windows verification.** Only finite nonnegative values accepted. No external debt search. |
| Farm name | `farm:getName()`, then `farm.name` | Compatibility candidates; missing names stay missing. |
| Game date | `mission.environment.currentMonotonicDay`, optional `currentYear`, `currentPeriod`, `dayTime` | FS25 AbstractMission uses the monotonic day for contract timing. Other calendar fields and fallback `currentDay` remain compatibility candidates. Raw game-day count and milliseconds after midnight are preserved without converting to invented calendar dates. |
| Land ownership | `g_farmlandManager:getFarmlands()` and `getFarmlandOwner(id)` | Published FS25 FarmlandManager methods. Access permissions are never ownership evidence. |
| Land area and value | `farmland.areaInHa`, `farmland.price` | Published FS25 Farmland fields. Area is the whole parcel, not cultivated field area. Price is the current game-configured price, not historical cost or a guaranteed sale outcome. |
| Registered vehicles | `mission.vehicleSystem.vehicles` | Published FS25 VehicleSystem enumerates registered vehicles. The documented `vehicleByUniqueId` lookup is a fallback if the list is unavailable; its use is disclosed. No recursive implement walk. |
| Vehicle identity | `getUniqueId()`, then `uniqueId` | Published FS25 Vehicle methods/fields. Deduplicated by both object identity and ID. Snapshot-local labels are used for absent IDs. |
| Vehicle ownership | `getOwnerFarmId()`, then `getPropertyState()` / `propertyState` | Owner must match the active farm exactly. FS25 `VehiclePropertyState.OWNED`, `.LEASED`, `.MISSION` decide classification; numeric constants are never assumed. |
| Equipment value | `vehicle:getSellPrice()` | Published FS25 engine quote; called once per owned item. Specializations/mods may include cargo. The report retains the quote intact and never adds a separate cargo valuation. No depreciation formula is reimplemented. |

Known pallet markers (`isPallet`, `spec_pallet`), big bags (`spec_bigBag`), and train-system vehicles are excluded from equipment. The FS25 VehicleSystem source explicitly distinguishes pallets, big bags, and trains. Custom objects that hide their native classification need Windows compatibility investigation. Unknown owners are omitted with a coverage issue; unknown property states are listed without a valuation. Other farms' known assets are not listed.

Section status is `available`, `partial`, or `unavailable`. Cash/debt use `available` or `unavailable`. An available section means its supported reads completed, not that it covers all farm wealth. Partial sums include known values only. A sum with no verified values is unavailable, except when enumeration verifies that the supported collection is empty. No snapshot holds references to mission/farm/vehicle objects. Failures are isolated by accessor, record, and section.

`BankDataSource.capture(context)` accepts a table keyed by engine global names for local tests. Without a context, it reads the actual engine globals, including `g_fillTypeManager` and `FillType` for quantities. The result has `schemaVersion = 2` and plain serializable tables: `farm`, `capturedAt`, `cash`, `debt`, `land`, `equipment`, `buildings`, `inventory`, `issues`, `capabilities`, and `gameVersion`. Capability values are scalar and diagnostic; missing APIs do not become zero-valued financial facts.

The added modules are isolated collection sections. [Building sources](property-sources.md) document monetary value versus sale eligibility and temporary refunds. [Inventory sources](inventory-sources.md) document strict storage attribution, quantities, deduplication, and exclusions. Inventory quantities never contribute separate monetary value to the asset subtotal.

## Primary references inspected

- [FS25 FarmlandManager](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=25&class=214&version=engine): ownership and enumeration; access permission has a separate implementation.
- [FS25 Farmland](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=25&class=213&version=script): parcel name, area, and current price fields.
- [FS25 Vehicle](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=91&class=888&version=script): sale quote, property state, unique ID, and display name.
- [FS25 VehicleSystem](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=91&class=897&version=script): registered collections and object exclusions.
- [FS25 AbstractMission](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=59&class=560&version=script): borrowed contract vehicles use `VehiclePropertyState.MISSION` and the contract farm owner.
- [FS25 VehicleSellingPoint](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=63&class=580&version=engine): mission farm and vehicle owner lookups.
- [FS25 PlayerSwitchedFarmEvent](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=1&class=98&version=script): farm-manager lookup.

The general GIANTS printable documentation contains `getBalance` / `getLoan` descriptions but mixes reference generations; it is not used to claim those paths have been verified for FS25. The diagnostic output records the actual getter availability, scalar types, chosen sources, property constants, vehicle enumeration path, and quote success counts to settle these points on Windows.

## First runtime evidence to capture

Check cash and debt against the Finance screen, land parcels against the ownership map, and equipment against the garage. Compare ordinary remote sale quotes, not a workshop sale bonus. Include a contract vehicle, a lease, a loaded trailer, a pallet, and an attached implement. Record the exact FS25 version and map with the diagnostic log. Repeating capture after purchases, sales, loan changes, and save reload must reconcile before the build is described as runtime validated.
