## Test262 required builtins
##

import std/[strutils, math, options, logging, tables]
import mirage/ir/generator
import mirage/runtime/prelude
import bali/runtime/[normalize, bridge]
import bali/runtime/abstract/to_string
import bali/runtime/[arguments, types, atom_helpers]
import bali/stdlib/errors
import bali/internal/sugar
import pretty

proc test262Error*(runtime: Runtime, msg: string) =
  runtime.vm.throw(jsException(msg))
  logTracebackAndDie(runtime)

type
  JSAssert* = object

proc generateStdIr*(runtime: Runtime) =
  info "builtins.test262: generating IR interfaces"

  # $DONOTEVALUATE (stub)
  runtime.defineFn(
    "$DONOTEVALUATE",
    proc =
      return
  )

  runtime.registerType(prototype = JSAssert, name = "assert")

  # assert.sameValue
  runtime.defineFn(
    JSAssert,
    "sameValue",
    proc =
      template no() =
        runtime.test262Error(
          "Assert.sameValue(): " & b.crush() & " != " & a.crush() & ' ' & msg
        )

      template yes() =
        info "Assert.sameValue(): passed test! (" & b.crush() & " == " & a.crush() & ')'
        return

      let
        a = &runtime.argument(1)
        b = &runtime.argument(2)
        msg =
          if runtime.argumentCount() > 2:
            runtime.ToString(&runtime.argument(3))
          else:
            ""

      if a.isUndefined() and b.isUndefined():
        yes

      if a.kind == UnsignedInt:
        if b.kind == Integer:
          if int(&a.getUint()) == &b.getInt(): yes else: no
      elif b.kind == UnsignedInt:
        if a.kind == Integer:
          if &a.getInt() == int(&b.getUint()): yes else: no

      if a.kind != b.kind:
        no

      case a.kind
      of Integer:
        if a.getInt() == b.getInt(): yes else: no
      of UnsignedInt:
        if a.getUint() == b.getUint(): yes else: no
      of String:
        if a.getStr() == b.getStr(): yes else: no
      of Null:
        yes
      else:
        no,
  )
