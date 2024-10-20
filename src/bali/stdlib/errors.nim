## Implementation of `throw` in MIR bytecode


import std/[logging]
import mirage/ir/generator
import mirage/runtime/prelude
import bali/grammar/errors
import bali/runtime/normalize
import bali/internal/sugar

type JSException* = ref object of RuntimeException
  name: string = ""

proc generateMessage*(exc: JSException, err: string): string =
  var msg = "Uncaught "

  if exc.name.len > 0:
    msg &= exc.name & ':'

  msg & err

proc jsException*(msg: string): JSException {.inline.} =
  var exc = JSException()
  exc.message = exc.generateMessage(msg)

  exc

proc logTracebackAndDie*(vm: PulsarInterpreter, exitCode: int = 1) =
  let traceback = vm.generateTraceback()
  assert *traceback, "Mirage failed to generate traceback!"

  stderr.write &traceback & '\n'
  quit(exitCode)

proc typeError*(vm: PulsarInterpreter, message: string, exitCode: int = 1) {.inline.} =
  ## Meant for other Bali stdlib methods to use.
  vm.throw(jsException("TypeError: " & message))
  vm.logTracebackAndDie(exitCode)

proc syntaxError*(
    vm: PulsarInterpreter, message: string, exitCode: int = 1
) {.inline.} =
  ## Meant for other Bali stdlib methods to use.
  vm.throw(jsException("SyntaxError: " & message))
  vm.logTracebackAndDie(exitCode)

proc syntaxError*(
    vm: PulsarInterpreter, error: ParseError, exitCode: int = 1
) {.inline.} =
  vm.syntaxError(error.message, exitCode)

proc generateStdIr*(vm: PulsarInterpreter, ir: IRGenerator) =
  info "errors: generate IR interface"

  vm.registerBuiltin(
    "BALI_THROWERROR",
    proc(op: Operation) =
      vm.throw(jsException(&vm.registers.callArgs[0].getStr()))
      vm.logTracebackAndDie(),
  )