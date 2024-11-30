## Balde - the Bali Debugger
##

when not isMainModule:
  {.error: "This file is not meant to be separately imported!".}

import std/[times, tables, os, monotimes, logging]
import bali/grammar/prelude
import bali/internal/sugar
import bali/runtime/prelude
import bali/private/argparser
import colored_logger, jsony, pretty

var
  enableProfiler = false
  profile = initTable[string, int64]()

proc enableLogging() {.inline.} =
  addHandler newColoredLogger()
  setLogFilter(lvlInfo)

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

proc execFile(ctx: Input, file: string) {.inline.} =
  profileThis "execFile() sanity checks":
    if not fileExists(file):
      die "file not found:", file

    let perms = getFilePermissions(file)
    if fpGroupRead notin perms and fpUserRead notin perms:
      die "access denied:", file

  profileThis "read source file":
    let source =
      try:
        readFile(file)
      except IOError as exc:
        die "failed to open file:", exc.msg
        ""

  if ctx.enabled("dump-tokens"):
    let excludeWs = ctx.enabled("no-whitespace")
    let tok = newTokenizer(source)
    while not tok.eof:
      if excludeWs:
        let val = tok.nextExceptWhitespace()
        if !val:
          break
        print &val
      else:
        print tok.next()

    quit(0)

  profileThis "allocate parser":
    let parser = newParser(source)

  profileThis "parse source code":
    var ast = parser.parse()

  if ctx.enabled("dump-no-eval"):
    print ast
    quit 0

  if ctx.enabled("dump-ast"):
    ast.doNotEvaluate = true

  profileThis "allocate runtime":
    var runtime = newRuntime(
      file, ast, InterpreterOpts(test262: ctx.enabled("test262"), dumpBytecode: ctx.enabled("dump-bytecode"))
    )

  profileThis "execution time":
    runtime.run()

  if ctx.enabled("dump-ast"):
    print ast

  if ctx.enabled("dump-runtime-after-exec"):
    print runtime

proc baldeRun(ctx: Input) =
  if not ctx.enabled("verbose", "v"):
    setLogFilter(lvlWarn)

  enableProfiler =
    ctx.enabled("enable-profiler", "P")
  
  if ctx.arguments.len < 1:
    die "`run` requires a file to evaluate."
  
  let arg = ctx.arguments[0]
  execFile(ctx, arg)

proc main() {.inline.} =
  enableLogging()
  
  let input = parseInput()
  if input.enabled("verbose", "v"):
    setLogFilter(lvlAll)

  if input.command.len < 1:
    assert off, "TODO: implement repl"

  case input.command
  of "run": baldeRun(input)
  else:
    die "invalid command: " & input.command

  if enableProfiler:
    writeFile("balde_profiler.txt", toJson profile)

when isMainModule:
  main()
