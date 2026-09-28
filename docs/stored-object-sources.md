# Bales and object storage: 0.0.3

This slice adds observed native bale quantities and stored-object counts. It
does not price stock, forecast fermentation, establish cargo title, or fabricate
quantities for undocumented virtual representations.

## Documented behavior

- [Bale](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=1&class=10&version=script)
  registers physical instances with mission.itemSystem when loaded and removes
  them on deletion. getFillLevel() returns current liters; getFillType() returns
  the current crop. getIsFermenting() and getFermentingPercentage() supply current
  state. Completed fermentation changes the bale's actual fill type, so the
  collector never substitutes a predicted silage type. getOwnerFarmId() is
  checked against the active farm. isMissionBale excludes contract bales.
- [BaleUnloadTrigger](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=1&class=12&version=script)
  identifies a physical bale with object:isa(Bale). The collector requires this
  native class check, rather than treating arbitrary fillable objects as bales.
- [BaleManager](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=58&class=548&version=script)
  holds bale **type definitions** in its bales list, not the save's bale holdings.
  That list is never enumerated for inventory.
- [PlaceableObjectStorage](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=78&class=751&version=script)
  stores individual abstract objects in spec_objectStorage.storedObjects.
  getRealObject() exposes a real counterpart where one exists. Its
  REFERENCE_CLASS_NAME and getDialogText() identify a record for display; dialog
  text is never parsed into quantities. The separate objectInfos collection is
  delayed grouped presentation data and is not an additional stock source.
- [FillUnit](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=78&class=672&version=script)
  supplies each real stored pallet's units, current type, and quantity. A native
  unitText override changes the label without converting the raw quantity.
  Pallets require verified owner and OWNED property state; mission pallets are
  excluded.

These references are public FS25 documentation labeled v1.20.0.0. Source review
is distinct from validation on the user's running game.

## Boundaries that remain candidates

mission.itemSystem.items is a guarded registry-layout candidate: both real
objects and records containing item are accepted, and every candidate must pass
the native Bale class check. The public Bale source proves ItemSystem
registration, but does not publish the registry's layout. Capability diagnostics
state this distinction. A missing registry/class means unavailable, not an empty
farm.

Public FS25 documentation does not expose the implementation of the abstract
bale/pallet classes or establish their virtual quantity fields. When a stored
entry has no readable real counterpart, the report retains one known object,
its display description/class when available, and an unavailable quantity.
Container ownership does not prove that object's cargo ownership. No guesses
are made from fillLevel fields, nested attribute tables, XML filenames,
nominal bale capacities, or numbers in display text.

Diagnostics provide at most three abstract-object shape samples, each listing
at most twelve raw field names and Lua value types. They contain no field values,
references, or mutation. These samples can guide a subsequent verified adapter.

## Integration contract

BankStoredObjectDataSource.collect(snapshot, context, helpers,
blockedRealObjects) runs after inventory initialization and before other
inventory adapters. Root supplies:

- addQuantity(snapshot, context, category, item), unknown, issue, call, and
  optional isRemoving helpers using the inventory collector's existing rules.
- Optional registeredBales and blockedUniqueIds capture-local sets.
- An existing blockedRealObjects set, which is mutated and returned. Preblocked
  transient bales remain excluded. The set survives an outer error boundary.
- Context contains the native Bale class, VehiclePropertyState, and mission
  item/placeable systems; g_baleManager is unnecessary.

The module writes coverage.bales and coverage.objectStorage. Rows use kind
bale, storedBale, storedPallet, or generic objectStorage for an unsupported class.
Optional scalar fields are objectCount, objectName, objectClass, isFermenting,
and fermentationProgress (finite 0..1). Stored pallet objects with multiple
quantity rows carry objectCount=1 on only the first emitted row.

Virtual stores are inspected before loose bales. Every real counterpart is
blocked by reference and unique ID before ownership/deletion filtering, so
foreign, unknown, or removing virtual stock cannot reappear as loose stock.
Sources are deduplicated; only copied scalar row data escapes capture. Missing,
negative, and nonfinite quantities flow through the shared unavailable logic.

## Lifecycle and duplicate controls

Deletion flags and the optional native deletion getter exclude sources while
preserving healthy neighbors. Loaded/unsellable bales remain stock:
[BaleLoader](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=78&class=635&version=script)
uses save flags for mounted bales, so getNeedsSaving() and getCanBeSold() are not
inventory ownership filters.

The root inventory collector handles vehicle proxies. In particular,
[StrawBlower](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=78&class=802&version=script)
mirrors currentBale into a fill unit; that unit cannot be added again alongside
the real bale. Transient physical round bales created by
[Baler](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=78&class=636&version=script)
may temporarily show capacity before discharge applies actual contents. Root
blocks those transient records and reports a refresh-after-discharge gap.

Windows checks remain pending for 0.0.3: loose and loaded bales, contract
exclusion, fermentation before/after completion, stored bale/pallet counts,
unloading a stored object without doubling it, partial round-bale discharge,
save/reload, and unsupported virtual entries with lbSnapshot shape diagnostics.
