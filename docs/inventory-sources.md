# Inventory quantities: 0.0.3

This adapter observes holdings; it does not price inventory or prove title to
cargo. A farmer-owned or leased trailer can carry contract crop. Every item
therefore has cargoOwnership=unverified, and no inventory amount enters the
covered asset subtotal. Whether contents are already included in a vehicle or
building sale quote is recorded as unknown.

## Documented FS25 interfaces

Sources below are GIANTS FS25 scripting documentation, currently labeled
v1.20.0.0. They establish implementation semantics, not a completed runtime test
against the user's FS25 version.

| Adapter | Source and implementation |
| --- | --- |
| Individual storage | [Storage](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=1&class=118&version=script): read getFillLevels(), which returns the fill-type-indexed levels for this storage only. Check getOwnerFarmId(); never use access permissions or loading-station aggregates. |
| Silos | [PlaceableSilo](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=78&class=761&version=script): spec_silo.storages contains the individual stores. Per-farm storage ownership may differ from the building's owner. Linked station aggregates would double-count neighboring stores and are not used. |
| Extensions | [PlaceableSiloExtension](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=78&class=762&version=script): spec_siloExtension.storage is independently owned and registered. |
| Production | [PlaceableProductionPoint](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=78&class=755&version=script) exposes the dedicated productionPoint through its specialization and assigns the owning placeable's farm; unfinished points use public ownership and are excluded. [ProductionPoint](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=1&class=102&version=script) persists its dedicated storage separately. Read only that storage, after checking the placeable owner. |
| Vehicles and pallets | [FillUnit](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=78&class=672&version=script): getFillUnits(), getFillUnitFillLevel(index), and getFillUnitFillType(index). Raw quantities are liters unless the fill unit specifies unitText. That field is a native text override with no quantity conversion. Shop display conversion is deliberately not applied to raw quantities. Equipment property state must be OWNED or LEASED; MISSION state is excluded. |
| Fill names | [FillTypeManager](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=36&class=409&version=script): getFillTypeByIndex() provides the internal name and localized title. Unknown types retain their known quantity with a metadata finding. No universal product/supply classification is inferred from a fill-type name. |
| Mounted saplings | [TreePlanter](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=78&class=813&version=script): its fill getter can proxy mountedSaplingPallet. Skip that specific planter unit so the separately enumerated pallet supplies the single holding. |
| Bale and object storage | [Stored-object sources](stored-object-sources.md) describe the new adapter. It reads physical bales and real stored counterparts once, and records unsupported virtual quantities as unavailable. Stored counterparts are excluded from subsequent vehicle and loose-bale scans. |

## Bale-handler overlap

- [StrawBlower](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=78&class=802&version=script) mirrors currentBale in its fillUnitIndex. Skip that unit; the registered physical bale supplies the quantity. A missing registry counterpart creates a finding.
- [BaleLoader](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=78&class=635&version=script) uses its active fillUnitIndex as a count of bales, not additional liters. That unit is excluded; unrelated units remain readable.
- [Baler](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=78&class=636&version=script) can retain a full round chamber beside its physical bale. Early partial ejection temporarily inflates it before lastBaleFillLevel is applied on dropping. A chamber with hasUnloadingAnimation and a physical bale or pending partial-ejection amount is omitted with a refresh finding, along with its corresponding main fill unit. Independent buffer material and square-baler material for the next bale remain. Suppression uses both object identity and unique ID.

## Compatibility boundary

The primary enumeration uses mission.placeableSystem.placeables and the concrete
specializations above. A guarded mission.storageSystem.storages scan additionally
checks registered storage objects, including custom storage implementations that
provide the documented ownership and quantity methods. The registry's precise
layout is a compatibility candidate, not a verified public FS25 contract; the
diagnostic capability field says so. Missing registry data leaves the documented
adapters usable and adds a coverage finding. Registries may contain values or
object-keyed entries; both are handled without following arbitrary object graphs.

Storage identity is deduplicated by object reference and a nonempty uniqueId
when provided, never by its root node or generic local id. Vehicle identity uses
object reference and uniqueId. Silo, extension, production, and registry aliases
cannot add the same holding twice. All references are capture-local; report
rows contain copied primitive values only.

Pending-deletion records are skipped on markedForDeletion, isDeleting,
isDeleted, or an available getIsBeingDeleted() returning true. These guarded
lifecycle signals avoid reading a source while a sale/removal is incomplete.
All known stores of a removed placeable are blocked before collection, so a
still-registered alias cannot restore their stock. Real display objects of a
removed virtual store are also suppressed. A removal finding requests another
refresh after the operation finishes; healthy neighboring records remain usable.

## Snapshot contract

BankInventoryDataSource.collect(snapshot, context) creates snapshot.inventory:

- items: positive or unavailable quantity rows; verified empty units are omitted.
- sourceCount: attributed individual storage objects and vehicles inspected,
  including empty sources and sources whose quantity accessor failed.
- zeroCount: explicitly zero fill-type levels/vehicle units.
- unknownCount: incomplete records or metadata findings; this is not a count of
  unowned assets or an estimate of missing stock.
- excludedCount: detected borrowed sources, unfinished production sources,
  removed objects, contract bales, and proxy units intentionally excluded.
- coverage: adapter statuses for storage, production, vehicle, bales and
  objectStorage; available means that adapter's supported reads completed.
- status: partial when any covered adapter is readable, unavailable when none
  can be inspected. It never claims complete inventory coverage.

Rows include id, location, kind, source, fillTypeIndex, fillTypeName,
fillTypeTitle when available, quantity, quantityStatus, unit, optional unitText,
container ownership, cargoOwnership, and includedInAssetQuote. unit=l uses the
native raw liter quantity; unit=units plus unitText preserves a native custom
unit override. Invalid, negative, NaN, or infinite quantities have no numeric
quantity and remain visible as unavailable. No cross-fill-type volume total,
monetary valuation, forecast, or product/supply classification is created.

## Known gaps and runtime checks

Virtual quantities without a verified real counterpart, bunker and ground heaps,
standing crop, animals, timber, construction stock, and custom stock systems
without a supported adapter remain outside coverage. Animal feed/products can
appear only when exposed through an enumerated, farm-owned Storage; this does
not establish full husbandry stock coverage. Linked loading-station totals and
production output forecasts are not holdings and are never added.

The Windows check must reconcile a silo, an extension, owned production input
and output, a loaded trailer, a pallet/big bag, and a leased trailer. Moving a
known quantity between a trailer and silo must move its observed location
without duplicating it. Verify empty storage versus missing data, mounted
saplings, object-storage quantities and omissions, and new snapshots after save/reload.
The user confirmed v0.0.2 successful; v0.0.3 bale/storage additions remain pending.
