## Implementation of `throw` in MIR bytecode

import std/[logging]
import mirage/ir/generator
import mirage/runtime/prelude
import bali/grammar/errors
import bali/runtime/normalize
import bali/internal/sugar
import bali/runtime/types

type
  DeathCallback* = proc(vm: PulsarInterpreter, exitCode: int = 1)
  JSException* = ref object of RuntimeException
    name: string = ""

proc DefaultDeathCallback(vm: PulsarInterpreter, exitCode: int = 1) =
  quit(exitCode)

var deathCallback*: DeathCallback = DefaultDeathCallback

proc setDeathCallback*(fn: DeathCallback) {.inline.} =
  deathCallback = fn

proc generateMessage*(exc: JSException, err: string): string =
  var msg = "Uncaught "

  if exc.name.len > 0:
    msg &= exc.name & ':'

  msg & err

proc jsException*(msg: string): JSException {.inline.} =
  var exc = JSException()
  exc.message = exc.generateMessage(msg)

  exc

proc logTracebackAndDie*(runtime: Runtime, exitCode: int = 1) =
  let traceback = runtime.vm.generateTraceback()
  assert *traceback, "Mirage failed to generate traceback!"

  stderr.write &traceback & '\n'
  deathCallback(runtime.vm, exitCode)

proc typeError*(runtime: Runtime, message: string, exitCode: int = 1) {.inline.} =
  ## Meant for other Bali stdlib methods to use.
  runtime.vm.throw(jsException("TypeError: " & message))
  runtime.logTracebackAndDie(exitCode)

proc referenceError*(runtime: Runtime, message: string, exitCode: int = 1) {.inline.} =
  runtime.vm.throw(jsException("ReferenceError: " & message))
  runtime.logTracebackAndDie(exitCode)

proc syntaxError*(
  runtime: Runtime, message: string, exitCode: int = 1
) {.inline.} =
  ## Meant for other Bali stdlib methods to use.
  runtime.vm.throw(jsException("SyntaxError: " & message))
  runtime.logTracebackAndDie(exitCode)

proc syntaxError*(
  runtime: Runtime, error: ParseError, exitCode: int = 1
) {.inline.} =
  runtime.syntaxError(error.message, exitCode)

proc generateErrorsStdIr*(runtime: Runtime) =
  info "errors: generate IR interface"

  runtime.vm.registerBuiltin(
    "BALI_THROWERROR",
    proc(op: Operation) =
      runtime.vm.throw(jsException(&runtime.vm.registers.callArgs[0].getStr()))
      runtime.logTracebackAndDie(),
  )
