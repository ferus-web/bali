## Object type, not to be confused with the `JSValue` variant "Object" (6),
## albeit this type maps almost 1:1 to it
##
## Copyright (C) 2025 Trayambak Rai (xtrayambak at disroot dot org)

import pkg/bali/runtime/[bridge, types], pkg/bali/runtime/vm/atom

type JSObject* = object

proc generateStdIR*(runtime: Runtime) =
  runtime.registerType("Object", JSObject)
  runtime.defineConstructor(
    "Object",
    proc() =
      ret runtime.createObjFromType(JSObject)
    ,
  )

  runtime.definePrototypeFn(
    JSObject,
    "toString",
    proc(this: JSValue) {.gcsafe.} =
      ret "[object Object]"
    ,
  )
