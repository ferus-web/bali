## String type
## Wraps around the Mirage atom
## Author(s):
## Trayambak Rai (xtrayambak at disroot dot org)
import std/[logging, tables, strutils, hashes]
import bali/runtime/[arguments, bridge, atom_helpers, types]
import bali/runtime/abstract/[coercible, to_number, to_string]
import bali/internal/[trim_string, sugar]
import mirage/atom
import pkg/kaleidoscope/[search]
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
    proc(str: MAtom) =
      let value = &str.tagged("internal")
      debug "String.toString(): returning value: " & &getStr(value)

      ret value
  )

  runtime.definePrototypeFn(
    JSString,
    "indexOf",
    proc(value: MAtom) =
      ## 22.1.3.9 String.prototype.indexOf ( searchString [ , position ] )
      ## If searchString appears as a substring of the result of converting this object to a String, at one or
      ## more indices that are greater than or equal to position, then the smallest such index is returned;
      ## otherwise, -1𝔽 is returned. If position is undefined, +0𝔽 is assumed, so as to search all of the
      ## String.

      let
        # 1. Let O be ? RequireObjectCoercible(this value)
        # 2. Let S be ? ToString(O).
        value = runtime.ToString(
          runtime.RequireObjectCoercible(&value.tagged("internal"))
        )
        needle = runtime.argument(1)
        position = runtime.argument(2)
      
      var searchStr: string
      if *needle:
        # 3. Let searchStr be ? ToString(searchString).
        searchStr = runtime.ToString(&needle)
      
      # 4. Let pos be ? ToIntegerOrInfinity(position).
      var pos: uint
      if *position:
        pos = runtime.ToNumber(&position).uint()
      else:
        # 5. Assert: If position is undefined, then pos is 0.
        pos = 0'u
  
      let
        # 6. Let len be the length of S
        len = value.len.uint

        # 7. Let start be the result of clamping pos between 0 and len.
        start = clamp(pos, 0'u, len)

      # 8. Return 𝔽(StringIndexOf(S, searchStr, start)).
      ret search.find(value[start ..< value.len], searchStr)
  )

  runtime.definePrototypeFn(
    JSString, "concat",
    proc(value: MAtom) =
      ## 22.1.3.5 String.prototype.concat ( ...args )

      # 1. Let O be ? RequireObjectCoercible(this value).
      # 2. Let S be ? ToString(O).
      let value = runtime.ToString(
        runtime.RequireObjectCoercible(&value.tagged("internal"))
      )
      
      # 3. Let R be S.
      var res = value

      # 4. For each element next of args, do
      for i in 0 ..< runtime.argumentCount():
        # a. Let nextString be ? ToString(next).
        let nextString = runtime.ToString(
          &runtime.argument(i + 1)
        )

        # b. Set R to the string-concatenation of R and nextString.
        res &= nextString

      # 5. Return R.
      echo runtime.argumentcount
      echo res
      ret res
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

  runtime.definePrototypeFn(
    JSString, "toLowerCase",
    proc(value: MAtom) =
      let value = &value.tagged("internal")

      ret strutils.toLowerAscii(runtime.ToString(value))
  )

  runtime.definePrototypeFn(
    JSString, "toUpperCase",
    proc(value: MAtom) =
      let value = &value.tagged("internal")

      ret strutils.toUpperAscii(runtime.ToString(value))
  )
