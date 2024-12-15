## String type
## Wraps around the Mirage atom
## Author(s):
## Trayambak Rai (xtrayambak at disroot dot org)
import std/[logging, tables, hashes]
import bali/runtime/[arguments, bridge, atom_helpers, types]
import bali/runtime/abstract/to_string
import bali/internal/[trim_string, sugar]
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
      debug "String.toString(): returning value: " & &getStr(value)

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

      debug "String.indexOf(): value = \"" & runtime.ToString(value) & "\"; needle = \"" & runtime.ToString(&needle) & '"'

      ret find(runtime.ToString(value), runtime.ToString(&needle))
  )

  runtime.definePrototypeFn(
    JSString,
    "trim",
    proc(value: MAtom) =
      ## 22.1.3.32 String.prototype.trim ( )

      # 1. Let S be the this value.
      let value = &value.tagged("internal")
      
      # 2. Return ? TrimString (S, start + end)
      ret runtime.trimString(value, TrimMode.Both)
  )

  proc trimStart(value: MAtom) =
    ## 22.1.3.34 String.prototype.trimStart ( )
    ## B.2.2.15 String.prototype.trimLeft ( )       [ LEGACY VERSION, USE 22.1.3.34 INSTEAD! ]

    # 1. Let S be the this value.
    let value = &value.tagged("internal")
      
    # 2. Return ? TrimString (S, start)
    ret runtime.trimString(value, TrimMode.Left)

  proc trimEnd(value: MAtom) =
    ## 22.1.3.33 String.prototype.trimEnd ( )
    ## B.2.2.16 String.prototype.trimRight ( )     [ LEGACY VERSION, USE 22.1.3.33 INSTEAD! ]

    # 1. Let S be the this value.
    let value = &value.tagged("internal")
      
    # 2. Return ? TrimString (S, start)
    ret runtime.trimString(value, TrimMode.Right)

  runtime.definePrototypeFn(
    JSString, "trimStart",
    trimStart
  )

  runtime.definePrototypeFn(
    JSString, "trimLeft",
    trimStart
  )

  runtime.definePrototypeFn(
    JSString, "trimEnd",
    trimEnd
  )
  
  runtime.definePrototypeFn(
    JSString, "trimRight",
    trimEnd
  )
