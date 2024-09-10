## JavaScript console API standard interface
## This uses a delegate system similar to that of V8's.
## Copyright (C) 2024 Trayambak Rai and Ferus Authors
import std/[options, tables, logging]
import mirage/ir/generator
import mirage/runtime/prelude
import bali/runtime/normalize
import bali/runtime/abstract/coercion
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

proc console(vm: PulsarInterpreter, level: ConsoleLevel) {.inline.} =
  var accum: string

  for arg in vm.registers.callArgs:
    let value = vm.ToString(arg)
    accum &= value & ' '

  delegate(level, accum)

proc consoleLogIR*(vm: PulsarInterpreter, generator: IRGenerator) =
  # generate binding interface
  
  # console.log
  # Perform Logger("log", data).
  generator.newModule(normalizeIRName "console.log")

  vm.registerBuiltin("BALI_CONSOLELOG",
    proc(op: Operation) =
      console(vm, ConsoleLevel.Log)
  )

  generator.call("BALI_CONSOLELOG")
  
  # console.warn
  # Perform Logger("warn", data).
  generator.newModule(normalizeIRName "console.warn")
  vm.registerBuiltin("BALI_CONSOLEWARN",
    proc(op: Operation) =
      console(vm, ConsoleLevel.Warn)
  )

  generator.call("BALI_CONSOLEWARN")
  
  # console.info
  # Perform Logger("info", data).
  generator.newModule(normalizeIRName "console.info")
  vm.registerBuiltin("BALI_CONSOLEINFO",
    proc(op: Operation) =
      console(vm, ConsoleLevel.Info)
  )

  generator.call("BALI_CONSOLEINFO")
  
  # console.error
  # Perform Logger("error", data).
  generator.newModule(normalizeIRName "console.error")
  vm.registerBuiltin("BALI_CONSOLEERROR",
    proc(op: Operation) =
      console(vm, ConsoleLevel.Error)
  )

  generator.call("BALI_CONSOLEERROR")
  
  # console.debug
  # Perform Logger("debug", data).
  generator.newModule(normalizeIRName "console.debug")
  vm.registerBuiltin("BALI_CONSOLEDEBUG",
    proc(op: Operation) =
      console(vm, ConsoleLevel.Debug)
  )

  generator.call("BALI_CONSOLEDEBUG")

  # TODO: implement the rest of the spec, mostly related to call traces and profiling later.

proc generateStdIR*(vm: PulsarInterpreter, generator: IRGenerator) =
  info "console: generating IR interfaces"
  
  consoleLogIR(vm, generator)
