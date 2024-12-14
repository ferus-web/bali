## String type
## Wraps around the Mirage atom
## Author(s):
## Trayambak Rai (xtrayambak at disroot dot org)
import std/[logging, tables, hashes]
import bali/runtime/[arguments, bridge, atom_helpers, types]
import bali/runtime/abstract/to_string
import bali/internal/sugar
import mirage/atom
when defined(baliUseStdFind):
  import std/strutils
else:
  import pkg/kaleidoscope/search
import pretty

type
  JSString* = object
    `@internal`*: string

func value*(str: JSString): string {.inline.} =
  str.`@internal`

proc toJsString*(runtime: Runtime, atom: MAtom): JSString =
  JSString(
    `@internal`: runtime.ToString(atom)
  )

proc generateStdIr*(runtime: Runtime) =
  runtime.registerType(prototype = JSString, name = "String")
  runtime.defineConstructor(
    "String",
    proc =
      let argument = runtime.argument(1)

      var atom = runtime.toJsString(&argument).wrap()
      atom.tag("bali_object_type", int hash $JSString)
      ret atom
  )
  runtime.definePrototypeFn(
    JSString,
    "toString",
    proc(value: MAtom) =
      let value = &value.tagged("internal")

      ret value
  )

  runtime.definePrototypeFn(
    JSString,
    "indexOf",
    proc(value: MAtom) =
      let value = &value.tagged("internal")
      let needle = runtime.argument(1)

      if !needle:
        ret 0

      ret find(runtime.ToString(value), runtime.ToString(&needle))
  )
