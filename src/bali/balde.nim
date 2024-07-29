## Balde - the Bali Debugger
##
## Copyright (C) 2024 Trayambak Rai and Ferus Authors

when not isMainModule:
  {.error: "This file is not meant to be separately imported!".}

import std/[times, tables, os, monotimes, logging]
import bali/grammar/prelude
import bali/runtime/prelude
import climate, colored_logger, jsony, pretty

var 
  enableProfiler = false
  profile = initTable[string, int64]()

proc enableLogging {.inline.} =
  addHandler newColoredLogger()

template profileThis(task: string, body: untyped) =
  var start: MonoTime
  if enableProfiler:
    start = getMonoTime()

  body
  
  if enableProfiler:
    let ant = getMonoTime()
    profile[task] = inMilliseconds(ant - start)

proc die(msg: varargs[string]) {.inline, noReturn.} =
  var str = "balde: "

  for m in msg:
    str &= m & ' '

  error(str)
  quit(1)

proc execFile(ctx: Context, file: string) {.inline.} =
  profileThis "execFile() sanity checks":
    if not fileExists(file):
      die "file not found:", file
  
    let perms = getFilePermissions(file)
    if fpGroupRead notin perms and fpUserRead notin perms:
      die "access denied:", file

  profileThis "read source file":
    let source = try:
      readFile(file)
    except IOError as exc:
      die "failed to open file:", exc.msg
      ""

  profileThis "allocate parser": 
    let parser = newParser(
      source
    )
  
  profileThis "parse source code":
    let ast = parser.parse()

  if ctx.cmdOptions.contains("dump-ast"):
    print ast
  
  profileThis "allocate runtime":
    let runtime = newRuntime(file, ast)

  profileThis "execution time":
    runtime.run()

  if ctx.cmdOptions.contains("dump-runtime-after-exec"):
    print runtime

proc baldeRun(ctx: Context): int =
  if not ctx.cmdOptions.contains("verbose") or ctx.cmdOptions.contains("v"):
    setLogFilter(lvlWarn)

  enableProfiler = ctx.cmdOptions.contains("enable-profiler") or ctx.cmdOptions.contains("P")

  ctx.arg:
    execFile(ctx, arg)
  do:
    die "`run` requires a file to evaluate."

proc main {.inline.} =
  enableLogging()

  const commands = {
    "run": baldeRun
  }

  let value = parseCommands(commands)
  
  if enableProfiler:
    writeFile(
      "balde_profiler.txt",
      toJson profile
    )
  
  quit(value)

when isMainModule:
  main()
