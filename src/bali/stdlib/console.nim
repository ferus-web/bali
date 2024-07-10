## JavaScript console API standard interface
import std/[tables, logging]
import mirage/ir/generator
import mirage/runtime/prelude
import bali/runtime/normalize
import bali/internal/sugar
import pretty

type
  ConsoleLevel* {.pure.} = enum
    Debug
    Error
    Info
    Log
    Trace
    Warn

  ConsoleDelegate* = proc(level: ConsoleLevel, msg: string)

const
  DefaultConsoleDelegate* = proc(level: ConsoleLevel, msg: string) =
    echo $level & ": " & msg

var delegate: ConsoleDelegate = DefaultConsoleDelegate

proc attachConsoleDelegate*(del: ConsoleDelegate) {.inline.} =
  delegate = del

proc consoleLogIR*(vm: PulsarInterpreter, generator: IRGenerator) =
  # generate binding interface
  generator.newModule(normalizeIRName "console.log")
  generator.call("BALI_CONSOLELOG")

  vm.registerBuiltin("BALI_CONSOLELOG",
    proc(op: Operation) =
      echo "\n\n\nI WAS CALLED MEOW :33333"
      for arg in vm.registers.callArgs:
        let value =
          case arg.kind
          of Integer:
            $(&arg.getInt())
          of String:
            $(&arg.getStr())
          else: ""

        delegate(ConsoleLevel.Log, value)
  )

proc generateStdIR*(vm: PulsarInterpreter, generator: IRGenerator) =
  info "console: generating IR interfaces"
  
  consoleLogIR(vm, generator)
