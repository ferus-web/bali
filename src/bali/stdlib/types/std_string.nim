## String type
## Wraps around the Mirage atom
## Author(s):
## Trayambak Rai (xtrayambak at disroot dot org)
import std/[logging, tables, strutils, hashes, unicode]
import bali/runtime/[arguments, bridge, wrapping, atom_helpers, types]
import bali/runtime/abstract/[coercible, to_number, to_string]
import bali/stdlib/errors, bali/stdlib/types/std_string_type
import bali/internal/[trim_string, sugar]
import bali/runtime/vm/atom
import pkg/[kaleidoscope/search, ferrite/utf16view]

const
  ## At what point should Bali start SIMD-accelerating string related operations?
  BaliStringAccelerationThreshold* {.intdefine.} = 128

proc generateStdIr*(runtime: Runtime) =
  runtime.registerType(prototype = JSString, name = "String")
  proc stringConstructor() =
    let argument =
      if runtime.argumentCount > 0:
        &runtime.argument(1)
      else:
        str("")

    if runtime.isA(argument, JSString):
      ret argument

    var atom = runtime.createObjFromType(JSString)
    let value = runtime.ToString(argument)
    runtime.tag(atom, "internal", value)
    atom["length"] = newUtf16View(value).codeunitLen().uinteger()
    ret atom

  runtime.defineConstructor("String", stringConstructor)
  runtime.defineFn("String", stringConstructor)

  runtime.definePrototypeFn(
    JSString,
    "toString",
    proc(str: JSValue) =
      let value = &str.tagged("internal")
      debug "String.toString(): returning value: " & &getStr(value)

      ret value
    ,
  )

  runtime.definePrototypeFn(
    JSString,
    "indexOf",
    proc(value: JSValue) =
      ## 22.1.3.9 String.prototype.indexOf ( searchString [ , position ] )
      ## If searchString appears as a substring of the result of converting this object to a String, at one or
      ## more indices that are greater than or equal to position, then the smallest such index is returned;
      ## otherwise, -1𝔽 is returned. If position is undefined, +0𝔽 is assumed, so as to search all of the
      ## String.

      let
        # 1. Let O be ? RequireObjectCoercible(this value)
        # 2. Let S be ? ToString(O).
        value =
          runtime.ToString(runtime.RequireObjectCoercible(&value.tagged("internal")))
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
      if value.len < BaliStringAccelerationThreshold:
        ret strutils.find(value[start ..< value.len], searchStr)
          # Optimization: Don't use SIMD acceleration if a string is smaller than 512 characters
      else:
        ret search.find(value[start ..< value.len], searchStr)
    ,
  )

  runtime.definePrototypeFn(
    JSString,
    "concat",
    proc(value: JSValue) =
      ## 22.1.3.5 String.prototype.concat ( ...args )

      # 1. Let O be ? RequireObjectCoercible(this value).
      # 2. Let S be ? ToString(O).
      let value =
        runtime.ToString(runtime.RequireObjectCoercible(&value.tagged("internal")))

      # 3. Let R be S.
      var res = value

      # 4. For each element next of args, do
      for i in 0 ..< runtime.argumentCount():
        # a. Let nextString be ? ToString(next).
        let nextString = runtime.ToString(&runtime.argument(i + 1))

        # b. Set R to the string-concatenation of R and nextString.
        res &= nextString

      # 5. Return R.
      ret res
    ,
  )

  runtime.definePrototypeFn(
    JSString,
    "trim",
    proc(value: JSValue) =
      ## 22.1.3.32 String.prototype.trim ( )

      # 1. Let S be the this value.
      let value = &value.tagged("internal")

      # 2. Return ? TrimString (S, start + end)
      ret runtime.trimString(value, TrimMode.Both)
    ,
  )

  proc trimStart(value: JSValue) =
    ## 22.1.3.34 String.prototype.trimStart ( )
    ## B.2.2.15 String.prototype.trimLeft ( )       [ LEGACY VERSION, USE 22.1.3.34 INSTEAD! ]

    # 1. Let S be the this value.
    let value = &value.tagged("internal")

    # 2. Return ? TrimString (S, start)
    ret runtime.trimString(value, TrimMode.Left)

  proc trimEnd(value: JSValue) =
    ## 22.1.3.33 String.prototype.trimEnd ( )
    ## B.2.2.16 String.prototype.trimRight ( )     [ LEGACY VERSION, USE 22.1.3.33 INSTEAD! ]

    # 1. Let S be the this value.
    let value = &value.tagged("internal")

    # 2. Return ? TrimString (S, start)
    ret runtime.trimString(value, TrimMode.Right)

  runtime.definePrototypeFn(JSString, "trimStart", trimStart)

  runtime.definePrototypeFn(JSString, "trimLeft", trimStart)

  runtime.definePrototypeFn(JSString, "trimEnd", trimEnd)

  runtime.definePrototypeFn(JSString, "trimRight", trimEnd)

  runtime.definePrototypeFn(
    JSString,
    "toLowerCase",
    proc(value: JSValue) =
      let value = &value.tagged("internal")

      ret strutils.toLowerAscii(runtime.ToString(value))
    ,
  )

  runtime.definePrototypeFn(
    JSString,
    "toUpperCase",
    proc(value: JSValue) =
      let value = &value.tagged("internal")

      ret strutils.toUpperAscii(runtime.ToString(value))
    ,
  )

  runtime.definePrototypeFn(
    JSString,
    "repeat",
    proc(value: JSValue) =
      let value = runtime.ToString(&value.tagged("internal"))
      var repeatCnt: int

      if runtime.argumentCount() > 0:
        repeatCnt = int(runtime.ToNumber(&runtime.argument(1)))

      if repeatCnt < 0:
        runtime.rangeError("repeat count must be non-negative")

      ret value.repeat(repeatCnt)
    ,
  )

  runtime.defineFn(
    JSString,
    "fromCharCode",
    proc() =
      ## 22.1.2.1 String.fromCharCode ( ...codeUnits ), https://tc39.es/ecma262/#sec-string.fromcharcode
      # 1. Let result be the empty String.
      var res: string

      # 2. For each element next of codeUnits, do
      for i in 1 .. runtime.argumentCount():
        # a. Let nextCU be the code unit whose numeric value is ℝ(? ToUint16(next)).
        let nextCodeUnit = uint16(runtime.ToNumber(&runtime.argument(i)))

        # b. Set result to the string-concatenation of result and nextCU.
        res &= Rune(nextCodeUnit)

      # 3. Return result.
      ret res
    ,
  )

  runtime.definePrototypeFn(
    JSString,
    "codePointAt",
    proc(value: JSValue) =
      # 22.1.3.4 String.prototype.codePointAt ( pos )
      let
        # 1. Let O be ? RequireObjectCoercible(this value).
        obj = runtime.RequireObjectCoercible(value)

        # 2. Let S be ? ToString(O).
        str = runtime.ToString(obj)

        # 3. Let position be ? ToIntegerOrInfinity(pos)
        position = int(runtime.ToNumber(&runtime.argument(1)))

        # 4. Let size be the length of S
        size = str.len

      # 5. If position < 0 or position ≥ size, return undefined.
      if position < 0 or position >= size:
        ret undefined()

      # 6. Let cp be CodePointAt(S, position).
      let codepoint = newUtf16View(str).codePointAt(position.uint())

      # Return 𝔽(cp.[[CodePoint]]).
      ret codepoint
    ,
  )

  #[ runtime.definePrototypeFn(
    JSString,
    "substring",
    proc(value: MAtom) =
      # 22.1.3.25 String.prototype.substring ( start, end )

      # If either argument is NaN or negative, it is replaced with zero; if either argument is strictly greater than the length
      # of the String, it is replaced with the length of the String.
      
      let
        # 1. Let O be ? RequireObjectCoercible(this value).
        obj = runtime.RequireObjectCoercible(&value.tagged("internal"))
        
        # 2. Let S be ? ToString(O).
        str = newUtf16View(runtime.ToString(obj))
        
        # 3. Let len be the length of S.
        stringLength = str.codeunitLen

      if start == NaN:
        start = 0f

      if last == NaN:
        last = 0f

      if start > 
  ) ]#
