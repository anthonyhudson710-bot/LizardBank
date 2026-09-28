# Buildings and placeable values

The 0.0.2 collector adds registered farm-owned placeables to the report. It reads
live objects only during collection and returns detached scalar records. It does
not inspect arbitrary map scene nodes or assume that land access grants ownership.

## Official API evidence

The following evidence was checked in GIANTS' FS25 scripting reference, currently
labelled **Script v1.20.0.0**. Windows runtime verification of this new slice is
still pending; successful 0.0.1 testing does not verify these additions.

| Input | Source and accounting use |
| --- | --- |
| Enumeration | `g_currentMission.placeableSystem.placeables`; `PlaceableSystem:addPlaceable` registers objects here and in `placableByUniqueId` (GIANTS' spelling). The lookup is a disclosed fallback, not a second scan. [PlaceableSystem](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=66&class=594&version=script) |
| Ownership | Exact `placeable:getOwnerFarmId()` match against the resolved active farm. `PlaceableSystem:getFarmhouse` demonstrates this ownership check. Other farms and public assets are excluded. [PlaceableSystem](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=66&class=594&version=script) |
| Identity and name | `getUniqueId()` and `getName()`. Repeat objects and identifiers are counted once. Missing identifiers receive snapshot-local labels. [Placeable](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=66&class=591&version=script) |
| Monetary value | `getMonetaryValue()` only. `getSellPrice()` documentation directs valuation callers to this method because sale prices can temporarily refund recent construction. Its monetary implementation is not reproduced in this reference page; the runtime result is checked for a finite nonnegative number. [Placeable](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=66&class=591&version=script) |
| Sale veto | Optional boolean from `canBeSold()`. Its base implementation permits sale; specializations may veto it. This check does not guarantee access to a sale action or realized proceeds. [Placeable](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=66&class=591&version=script) |
| Removal | `markedForDeletion`, `isDeleting`, and `isDeleted` exclude objects during removal. [Placeable](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=66&class=591&version=script) |

## Accounting boundary

- The subtotal is **engine monetary value**, not a liquid collateral valuation,
  purchase cost, construction refund, or appraisal. An unsellable owned building
  can still have a monetary value; its optional sale veto remains separate.
- No fallback multiplier or store price is invented. A verified zero is valid;
  absent, negative, infinite, or NaN values remain unavailable. Known values may
  form a partial subtotal. If all owned values are unknown, no zero is reported.
- The collector neither adds nor subtracts contents. Custom specializations may
  include stock, animals, or other assets in their returned monetary value.
  Separate inventory quantities must not be converted into an added monetary
  subtotal until that overlap has been verified. No generic contents exclusion
  is asserted for every modded placeable.
- Owned preplaced buildings are eligible when ownership is verified. Their value
  is not inferred from, or allocated out of, the farmland price. The monetary
  subtotal does not establish that land and a building can be sold independently.
- Objects without a standard monetary accessor are still listed as unvalued.
  Malformed records and failing accessors produce explicit coverage issues;
  readable records continue to contribute. Diagnostic capabilities contain only
  scalar values and counters.

## Windows acceptance checks

On a copied save, compare listed building names and ownership with the farm's
construction and production screens. Include a preplaced purchased production
building, a silo, a shed, an unsellable building if available, and an unowned map
business. Buy a building, refresh, save/reload, then sell it and refresh. Temporary
full construction refunds must not inflate its bank monetary value. Check that
stored goods appear separately as quantities and are not also added as money.
