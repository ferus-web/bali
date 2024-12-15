## Balde - the Bali Debugger
##
## Author(s):
## Trayambak Rai (xtrayambak at disroot dot org)

when not isMainModule:
  {.error: "This file is not meant to be separately imported!".}

import std/[strutils, terminal, times, tables, os, monotimes, logging]
import bali/grammar/prelude
import bali/internal/sugar
import bali/runtime/prelude
import bali/private/argparser
import pkg/[colored_logger, jsony, pretty, noise, fuzzy]

const Version {.strdefine: "NimblePkgVersion".} = "<version not defined>"

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

proc allocRuntime*(ctx: Input, file: string, ast: AST, repl: bool = false): Runtime =
  let test262 = ctx.enabled("test262")
  var runtime = newRuntime(
    file, ast, InterpreterOpts(test262: test262, dumpBytecode: ctx.enabled("dump-bytecode"), repl: repl)
  )
  let expStr = ctx.flag("enable-experiments")

  var success = true
  let exps =
    if *expStr: 
      split(&expStr, ';')
    else:
      newSeq[string](0)

  for experiment in exps:
    if not runtime.opts.experiments.setExperiment(experiment, true):
      success = false
      break

  if not success:
    assert(*expStr)
    error "Failed to enable certain experiments."
    quit(1)

  if *expStr and not ctx.enabled("disable-experiment-warning"):
    info "You have enabled certain experiments."
    info "By enabling them, you know that the engine will be more unstable than it already is."
    info "These features are not production ready!"

  runtime

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
    let parser = newParser(source, opts = ParserOpts(test262: ctx.enabled("test262")))

  profileThis "parse source code":
    var ast = parser.parse()

  if ctx.enabled("dump-no-eval"):
    print ast
    quit 0

  if ctx.enabled("dump-ast"):
    ast.doNotEvaluate = true

  profileThis "allocate runtime":
    var runtime = allocRuntime(ctx, file = file, ast = ast)

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
  
  let arg = ctx.command
  execFile(ctx, arg)

proc baldeRepl(ctx: Input) =
  var prevRuntime: Runtime
  var noise = Noise.init()

  template evaluateSource(line: string) =
    let ast = newParser(line).parse()
    var runtime = allocRuntime(ctx, "<repl>", ast, repl = true)
    if prevRuntime != nil:
      runtime.values = prevRuntime.values
      runtime.vm.stack = prevRuntime.vm.stack # Copy all atoms of the previous runtime to the new one
    runtime.run()
    prevRuntime = runtime

  echo "Welcome to Balde, with Bali v" & Version
  echo "Keep in mind that this is still a heavily work-in-progress feature. Bugs are bound to occur."
  echo "Start typing JavaScript expressions to evaluate them."
  echo "Type .quit to exit the REPL."

  let prompt = Styler.init(fgYellow, "REPL", resetStyle, " > ")
  noise.setPrompt(prompt)

  when promptCompletion:
    proc completionHook(noise: var Noise, text: string): int =
      if prevRuntime == nil:
        return

      for ident in prevRuntime.values:
        if ident.kind != vkInternal and fuzzyMatchSmart(text, ident.identifier) >= 0.5f:
          noise.addCompletion(ident.identifier)

    noise.setCompletionHook(completionHook)

  when promptHistory:
    var file = getHomeDir() / ".balde_history"
    discard noise.historyLoad(file)

  while true:
    let ok = noise.readLine()
    if not ok: break

    let line = noise.getLine()

    case line
    of ".quit":
      discard noise.historySave(file)
      quit(0)
    of ".help":
      echo """
.quit          - Quit the REPL
.help          - Show this message
.clear_history - Clear the REPL's history
.dump_stack    - Dump the stack of the previous evaluation, if there was one.
.dump_gc       - Dump Nim's GC statistics
.express       - Express an atom from the stack address of a previous evaluation, if there was one.

You can also just type in JavaScript expressions to evaluate them."""
    of ".clear_history":
      noise.historyClear()
    of ".dump_stack":
      if prevRuntime == nil:
        echo "Nothing has been evaluated yet."
        continue

      for i, value in prevRuntime.vm.stack:
        echo $i & ": " & prevRuntime.ToString(value) & " <" & $value.kind & '>'
    of ".dump_gc":
      echo GC_getStatistics()
    else:
      if line.startsWith(".express"):
        if prevRuntime == nil:
          echo "Nothing has been evaluated yet."
          continue

        let args = line.split(' ')
        if args.len < 2:
          styledWriteLine(stdout, fgRed, ".express expects 1 argument!", resetStyle)
          continue

        let index = try:
          parseUint(args[1])
        except ValueError as exc:
          styledWriteLine(stdout, fgRed, "could not parse index for .express", resetStyle, ": ", styleBright, exc.msg, resetStyle)
          continue

        if prevRuntime.vm.stack.contains(index):
          print prevRuntime.vm.stack[index]
        else:
          echo "No value exists at index: " & $index & '\n' &
              "Run .dump_stack to see all values."
          continue
      else:
        let parser = newParser(line)
        let ast = parser.parse()

        if ast.errors.len > 0:
          for error in ast.errors:
            styledWriteLine(stdout, fgRed, "Parse Error", resetStyle, ": ", styleBright, error.message, resetStyle)
        else:
          noise.historyAdd(line)
          evaluateSource line

  when promptHistory:
    discard noise.historySave(file)

proc main() {.inline.} =
  enableLogging()
  
  let input = parseInput()
  if input.enabled("version", "V"):
    echo Version
    quit(0)

  if input.enabled("verbose", "v"):
    setLogFilter(lvlAll)

  if input.command.len < 1:
    if not input.enabled("verbose", "v"):
      setLogFilter(lvlError)

    baldeRepl(input)
    quit(0)
  
  if input.command.len > 0:
    baldeRun(input)
  else:
    baldeRepl(input)

  if enableProfiler:
    writeFile("balde_profiler.txt", toJson profile)

when isMainModule:
  main()
