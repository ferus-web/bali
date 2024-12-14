## JavaScript console API standard interface
## This uses a delegate system similar to that of V8's.

import std/[options, tables, logging]
import mirage/ir/generator
import mirage/runtime/prelude
import bali/runtime/[normalize, arguments, types, bridge]
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
  JSConsole* = object

const DefaultConsoleDelegate* = proc(level: ConsoleLevel, msg: string) =
  echo $level & ": " & msg

var delegate: ConsoleDelegate = DefaultConsoleDelegate

proc attachConsoleDelegate*(del: ConsoleDelegate) {.inline.} =
  delegate = del

proc console(runtime: Runtime, level: ConsoleLevel) {.inline.} =
  var accum: string

  for i in 1 .. runtime.argumentCount():
    let value = runtime.ToString(&runtime.argument(i))
    accum &= value & ' '

  delegate(level, accum)

proc consoleLogIR*(runtime: Runtime) =
  # generate binding interface
  runtime.registerType(prototype = JSConsole, name = "console")

  # console.log
  # Perform Logger("log", data).

  runtime.definePrototypeFn(
    JSConsole,
    "log",
    proc(_: MAtom) =
      console(runtime, ConsoleLevel.Log),
  )

  # console.warn
  # Perform Logger("warn", data).
  runtime.definePrototypeFn(
    JSConsole,
    "warn",
    proc(_: MAtom) =
      console(runtime, ConsoleLevel.Warn),
  )

  # console.info
  # Perform Logger("info", data).
  runtime.definePrototypeFn(
    JSConsole,
    "info",
    proc(_: MAtom) =
      console(runtime, ConsoleLevel.Info),
  )

  # console.error
  # Perform Logger("error", data).
  runtime.definePrototypeFn(
    JSConsole,
    "error",
    proc(_: MAtom) =
      console(runtime, ConsoleLevel.Error),
  )

  # console.debug
  # Perform Logger("debug", data).
  runtime.definePrototypeFn(
    JSConsole,
    "debug",
    proc(_: MAtom) =
      console(runtime, ConsoleLevel.Debug),
  )

  # TODO: implement the rest of the spec, mostly related to call traces and profiling later.

proc generateStdIR*(runtime: Runtime) =
  info "console: generating IR interfaces"

  consoleLogIR(runtime)
