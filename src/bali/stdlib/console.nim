## JavaScript console API standard interface

import std/[options, logging, tables]
import bali/runtime/[arguments, types, bridge]
import bali/runtime/abstract/coercion
import bali/internal/sugar

type JSConsole* = object

const DefaultConsoleDelegate* = proc(level: ConsoleLevel, msg: string) {.gcsafe.} =
  echo msg

proc attachConsoleDelegate*(runtime: Runtime, del: ConsoleDelegate) {.inline.} =
  runtime.consoleDelegate = del

proc console(runtime: Runtime, level: ConsoleLevel) {.inline, gcsafe.} =
  var accum: string

  for i in 1 .. runtime.argumentCount():
    let value = runtime.ToString(&runtime.argument(i))
    accum &= value & ' '

  runtime.consoleDelegate(level, accum)

proc consoleLogIR*(runtime: Runtime) =
  # generate binding interface
  attachConsoleDelegate(runtime, DefaultConsoleDelegate)
  runtime.registerType(prototype = JSConsole, name = "console")

  # console.log
  # Perform Logger("log", data).

  runtime.defineFn(
    JSConsole,
    "log",
    proc() =
      console(runtime, ConsoleLevel.Log),
  )

  # console.warn
  # Perform Logger("warn", data).
  runtime.defineFn(
    JSConsole,
    "warn",
    proc() =
      console(runtime, ConsoleLevel.Warn),
  )

  # console.info
  # Perform Logger("info", data).
  runtime.defineFn(
    JSConsole,
    "info",
    proc() =
      console(runtime, ConsoleLevel.Info),
  )

  # console.error
  # Perform Logger("error", data).
  runtime.defineFn(
    JSConsole,
    "error",
    proc() =
      console(runtime, ConsoleLevel.Error),
  )

  # console.debug
  # Perform Logger("debug", data).
  runtime.defineFn(
    JSConsole,
    "debug",
    proc() =
      console(runtime, ConsoleLevel.Debug),
  )

  # TODO: implement the rest of the spec, mostly related to call traces and profiling later.

proc generateStdIR*(runtime: Runtime) =
  info "console: generating IR interfaces"

  consoleLogIR(runtime)
