## Slot logic
## Author: Trayambak Rai (xtrayambak at disroot dot org)
import std/hashes
import bali/internal/sugar
import bali/stdlib/errors
import bali/runtime/vm/atom, bali/runtime/[atom_helpers, types]

proc RequireInternalSlot*[T](
    runtime: Runtime, obj: JSValue, internalSlot: typedesc[T]
) =
  ## 10.1.15 RequireInternalSlot ( O, internalSlot )

  # 1. If O is not an Object, throw a TypeError exception.
  if not obj.isObject:
    runtime.typeError("Value is not an object.")

  # 2. If O does not have an internalSlot internal slot, throw a TypeError exception.
  let slot = obj.tagged("bali_object_type")

  if !slot:
    runtime.typeError("Object does not have an internal slot.")

  if (&slot).kind != Integer:
    runtime.typeError("Object does not have a valid internal slot.")

  var flag = false
  for etyp in runtime.types:
    if etyp.proto != hash($internalSlot):
      continue

    if etyp.proto.int == &getInt(&slot):
      flag = true

  if not flag:
    runtime.typeError("Object does not have a required slot.")

  # 3. Return UNUSED.
