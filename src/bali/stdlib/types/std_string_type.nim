## Basic types for `JSString`.
## Separated from the String prototype functions to prevent circular dependencies. 

import
  bali/runtime/vm/atom,
  bali/runtime/atom_helpers,
  bali/runtime/types,
  bali/internal/sugar

type JSString* = object
  `@ internal`*: string

func value*(str: JSString): string {.inline.} =
  str.`@ internal`

proc newJSString*(runtime: Runtime, native: string): JSValue =
  ## Given a native string, turn it into a `JSString` allocated on the heap.
  var str = runtime.createObjFromType(JSString)
  str.tag("internal", native.str())

  ensureMove(str)

proc toNativeString*(str: JSValue): string =
  ## Given a `JSValue`, assuming it is a proper `JSString`, convert it into its native string representation.
  &getStr(&str.tagged("internal"))
