# Livestock snapshot sources — 0.0.4

This slice reads current animals in registered husbandries owned by the active farm. Native animal reference quotes form a separate subtotal, never an addition to the combined covered-assets subtotal. Transported animals and horses currently being ridden are explicitly deferred. These are documentation findings and local logic tests; the 0.0.4 Windows comparisons remain separate in [WINDOWS_TEST.md](WINDOWS_TEST.md).

## API evidence

The public FS25 scripting reference reviewed for this build identifies itself as Script v1.20.0.0. That is not proof of identical behavior in another installed game version or in custom specializations.

| Observation | Official source and implementation |
| --- | --- |
| Registered placeables | [PlaceableSystem](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=66&class=594&version=script), `addPlaceable`, maintains `placeables` and `placableByUniqueId` (GIANTS' spelling). The collector uses the list, with the lookup as a diagnostic fallback. |
| Placeable ownership and identity | [Placeable](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=66&class=591&version=script), `getOwnerFarmId`, `getUniqueId`, and `getName`. Unknown ownership is excluded; access permission and land ownership do not substitute for husbandry ownership. |
| Current husbandry groups and counts | [PlaceableHusbandryAnimals](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=78&class=731&version=script), `getClusters` reads its cluster system. `getNumOfAnimals` sums `cluster.numAnimals`. The documented per-cluster getter is preferred; that raw count is a fallback only when the getter is absent. |
| Current health | `PlaceableHusbandryAnimals:updateInfo` formats `cluster.health` directly as a percentage. The collector preserves a finite value between 0 and 100 without rescaling. It does not compute a herd average. |
| Per-animal reference quote | [LivestockTrailer](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=78&class=692&version=script), `getSellPrice`, multiplies `cluster:getSellPrice()` by `cluster:getNumAnimals()` before applying its own 0.75 multiplier. This establishes that the cluster getter is per animal. Lizard Bank multiplies once by the verified count and adds no fee or transport calculation. |
| Localized native label | `LivestockTrailer:getAdditionalComponentMass` resolves `getSubTypeByIndex(...).fillTypeIndex` through `g_fillTypeManager:getFillTypeByIndex`. The collector uses that fill type's native `title`, also used by [PlaceableHusbandryMilk](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=78&class=737&version=script), `getConditionInfos`. This may describe a general category; it is not guaranteed to name the breed. |
| Individual names and subtype identifier | [Rideable](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=78&class=785&version=script) uses cluster `getName` for a horse name and `subType.name` when saving. The snapshot keeps that internal name as `subtypeKey`, independently of its readable label. |
| Riding transfer | `PlaceableHusbandryAnimals:startRiding` removes the ridden animal from the husbandry and creates an owned vehicle carrying a cloned cluster; Rideable transfers the animal back when returning to its stable. Counting only husbandry clusters therefore omits a currently ridden horse. |

Neither the reviewed cluster callers nor the published GUI excerpt establish general livestock transaction fees or net sale proceeds. The trailer's 0.75 multiplier is specific to selling a loaded trailer; it is not interpreted as a universal transport fee. Native nonempty husbandries veto building sale, but this does not establish how every modded building quote treats animals. Keeping livestock separate avoids claiming that all custom valuations can safely be combined.

## Snapshot contract

`BankAnimalDataSource.collect(snapshot, context)` needs `context.g_currentMission`; optional names use its `animalSystem` and `context.g_fillTypeManager`. It replaces `snapshot.animals`, appends issues, and records scalar capability checks. No live mission, placeable, cluster, subtype, or fill-type object is retained.

`animals` contains `items`, `ownedHusbandryCount`, `clusterCount`, `unknownCountCount`, `unknownValueCount`, `excludedCount`, `status`, optional `totalCount` / `totalValue`, and `transportedStatus = "excluded"` / `riddenStatus = "excluded"`. Section `status` describes the supported husbandry scan; the permanent coverage issue describes excluded locations and the separate valuation basis.

Each item has a snapshot-local `id`, readable `location` and `name`, `status`, and `valueSource`. Optional confirmed figures are whole nonnegative `count`, `healthPercent`, per-animal `unitValue`, and count-multiplied `value`. Optional `nativeTypeName` is a localized fill-type label; `subtypeKey` is the engine's internal subtype name. No species or breed is guessed from numeric IDs.

`ageRaw` / `ageSource` preserve a finite `cluster:getAge()` result for diagnostics. `reproductionRaw` / `reproductionSource` preserve an observed finite `cluster.reproduction` only as an unverified diagnostic field. The published callers establish an age accessor, but not its unit; they do not establish the reproduction field's meaning or scale. **This build does not populate `ageMonths` or `reproductionPercent`.** The GUI must not normalize or present either raw field as a confirmed measurement. No reproduction update method is invoked.

An unavailable husbandry cluster list or malformed group produces a visible unknown row. `clusterCount` counts successfully read unique cluster records, including legitimate zero-count records. Unknown-row counters count rows, not an estimated number of missing animals. `excludedCount` counts omitted husbandries or invalid placeable records whose coverage cannot be established.

Known groups contribute to partial subtotals; all-unknown data stays `nil`. A completely enumerated empty supported set yields verified zero. Finite zero quotes and zero health remain valid. Invalid counts, negative/nonfinite prices, and overflowing products/subtotals are unavailable. A valid per-animal quote can remain visible even when a group count or multiplied value is unavailable.

## Read-only behavior and limits

Repeated placeables are deduplicated by object identity and verified placeable unique ID. Clusters are deduplicated by identity across the scan; no undocumented cluster-ID getter or subtype-based grouping is assumed. Distinct clusters of the same subtype are retained. IDs and row ordering are presentation aids, not persistent history keys.

Each placeable and cluster is isolated behind protected calls. Known deletion flags suppress records while they are being removed. No pending cluster queue is flushed, no updates or economic methods are called, and no visual animal meshes or trailer preview slots are counted. Refresh after a transfer completes to reconcile transient states.

The collector does not scan trailer clusters or Rideable vehicles, sell anything, infer disease/fertility, reconstruct transactions, or forecast offspring or production. Custom species without the documented husbandry specialization are outside this adapter. Custom methods can change valuation semantics; capability checks and partial reports support investigation without replacing unknown values with estimates.

Local Lua tests cover ownership, duplicate aliases, distinct groups, verified zero versus missing data, unavailable cluster lists, getter failures, invalid numeric data, overflow, raw optional diagnostics, detached rows, refreshing, and read-only exclusions. They cannot establish live FS25 behavior; use the Windows matrix to compare counts, health, animal reference quotes, purchases/sales, trailer transfers, riding, and save changes.
