## Test262 required builtins/harnesses
##

import std/[math, options, logging, terminal, hashes]
import bali/runtime/vm/runtime/prelude
import bali/runtime/[bridge]
import bali/runtime/abstract/[equating, to_string]
import bali/runtime/[arguments, types]
import bali/stdlib/errors_common
import bali/internal/sugar

proc test262Error*(runtime: Runtime, msg: string) =
  runtime.vm.throw(jsException(msg))
  logTracebackAndDie(runtime)

type JSAssert* = object

proc generateStdIr*(runtime: Runtime) =
  info "builtins.test262: generating IR interfaces"

  # $DONOTEVALUATE (stub)
  runtime.defineFn(
    "$DONOTEVALUATE",
    proc() =
      return ,
  )

  runtime.registerType(prototype = JSAssert, name = "assert")

  # assert.sameValue
  runtime.defineFn(
    JSAssert,
    "sameValue",
    proc() =
      template no() =
        stderr.styledWriteLine(
          bgRed,
          fgBlack,
          " FAIL ",
          resetStyle,
          " ",
          styleBright,
          runtime.ToString(a),
          resetStyle,
          " != ",
          styleBright,
          runtime.ToString(b),
          resetStyle,
        )
        runtime.test262Error(
          "Assert.sameValue(): " & runtime.ToString(a) & " != " & runtime.ToString(b) &
            ' ' & msg
        )

      template yes() =
        stdout.styledWriteLine(
          bgGreen,
          fgBlack,
          " PASS ",
          resetStyle,
          " ",
          styleBright,
          runtime.ToString(a),
          resetStyle,
          " == ",
          styleBright,
          runtime.ToString(b),
          resetStyle,
        )
        return

      let
        a = &runtime.argument(1)
        b = &runtime.argument(2)
        msg =
          if runtime.argumentCount() > 2:
            runtime.ToString(&runtime.argument(3))
          else:
            ""

      if runtime.isLooselyEqual(a, b): yes else: no,
  )

  runtime.defineFn(
    JSAssert,
    "fail",
    proc() =
      let msg = runtime.ToString(&runtime.argument(1))
      stderr.styledWriteLine(
        bgRed, fgBlack, " FAIL ", resetStyle, " ", styleBright, msg, resetStyle
      )
      runtime.test262Error("Assert.fail(): test case failed: " & msg),
  )

  runtime.defineFn(
    JSAssert,
    "success",
    proc() =
      let msg = runtime.ToString(&runtime.argument(1))
      stderr.styledWriteLine(
        bgRed, fgBlack, " SUCCESS ", resetStyle, " ", styleBright, msg, resetStyle
      ),
  )
