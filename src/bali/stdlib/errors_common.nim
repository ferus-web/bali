import std/[importutils, strutils]
import bali/runtime/vm/runtime/prelude
import bali/runtime/types
import bali/internal/sugar

privateAccess(PulsarInterpreter)

type
  JSException* = ref object of RuntimeException
    name: string = ""

  DeathCallback* = proc(vm: PulsarInterpreter, exitCode: int = 1)

proc DefaultDeathCallback(vm: PulsarInterpreter, exitCode: int = 1) =
  when not defined(baliCrashAndBurnEverythingOnError):
    # Gracefully exit.
    quit(exitCode)
  else:
    # Crash and burn everything down, as the above define suggests.
    assert(false, ":(")

var deathCallback*: DeathCallback = DefaultDeathCallback

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

  if not runtime.vm.trace.exception.message.contains(runtime.test262.negative.`type`):
    stdout.write(&traceback & '\n')
    deathCallback(runtime.vm, exitCode)
  else:
    stderr.write &traceback & '\n'
    deathCallback(runtime.vm, exitCode)
