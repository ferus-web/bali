## Test262 required builtins
##
## Copyright (C) 2024 Trayambak Rai

import std/[strutils, math, options, logging, tables]
import mirage/ir/generator
import mirage/runtime/prelude
import bali/runtime/normalize
import bali/stdlib/errors
import bali/internal/sugar
import pretty

proc test262Error*(vm: PulsarInterpreter, msg: string) =
  vm.throw(jsException(msg))
  logTracebackAndDie(vm)

proc generateStdIr*(vm: PulsarInterpreter, generator: IRGenerator) =
  info "builtins.test262: generating IR interfaces"

  # $DONOTEVALUATE (stub)
  generator.newModule(normalizeIRName "$DONOTEVALUATE")
  vm.registerBuiltin(
    "TESTS_DONOTEVALUATE",
    proc(op: Operation) =
      return ,
  )
  generator.call("TESTS_DONOTEVALUATE")

  # assert.sameValue
  generator.newModule(normalizeIRName "assert.sameValue")
  vm.registerBuiltin(
    "TESTS_ASSERTSAMEVALUE",
    proc(op: Operation) =
      template no() =
        vm.test262Error("Assert.sameValue(): " & a.crush() & " != " & b.crush())

      template yes() =
        info "Assert.sameValue(): passed test! (" & a.crush() & " == " & b.crush() & ')'
        return

      let
        a = vm.registers.callArgs.pop()
        b = vm.registers.callArgs.pop()

      if a.kind == UnsignedInt:
        if b.kind == Integer:
          if int(&a.getUint()) == &b.getInt(): yes
          else: no
      elif b.kind == UnsignedInt:
        if a.kind == Integer:
          if &a.getInt() == int(&b.getUint()): yes
          else: no

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
  generator.call("TESTS_ASSERTSAMEVALUE")
