## Balde - the Bali Debugger
##
## Author(s):
## Trayambak Rai (xtrayambak at disroot dot org)

when not isMainModule:
  {.error: "This file is not meant to be separately imported!".}

import std/[strutils, terminal, times, tables, os, options, monotimes, logging, json]
import bali/grammar/prelude
import bali/internal/sugar
import bali/runtime/prelude
import bali/private/argparser
import bali/runtime/vm/heap/[prelude, boehm]
import pkg/[colored_logger, jsony, pretty, noise, fuzzy]

const Version {.strdefine: "NimblePkgVersion".} = "<version not defined>"

type DumpMode = enum
  dmPretty
  dmJson
  dmJsonPretty

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

proc allocRuntime*(
    ctx: Input, file: string, ast: AST, repl: bool = false, dumpIRFor: seq[string]
): Runtime =
  let test262 = ctx.enabled("test262")
  var runtime = newRuntime(
    file,
    ast,
    InterpreterOpts(
      test262: test262,
      dumpBytecode: ctx.enabled("dump-bytecode", "D"),
      repl: repl,
      insertDebugHooks: ctx.enabled("insert-debug-hooks", "H"),
      codegen: CodegenOpts(
        elideLoops: not ctx.enabled("disable-loop-elision"),
        loopAllocationEliminator: not ctx.enabled("disable-loop-allocation-elim"),
        aggressivelyFreeRetvals: ctx.enabled("aggressively-free-retvals"),
        deadCodeElimination: not ctx.enabled("disable-dead-code-elim"),
        jitCompiler: not ctx.enabled("disable-jit", "Nz") and not repl,
      ),
      jit: JITOpts(madhyasthalDumpIRFor: dumpIRFor),
    ),
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

proc allocRuntime*(ctx: Input, file: string): Runtime =
  let test262 = ctx.enabled("test262")
  var runtime = newRuntime(
    file = file,
    opts = InterpreterOpts(
      test262: test262,
      dumpBytecode: ctx.enabled("dump-bytecode", "D"),
      repl: false,
      insertDebugHooks: ctx.enabled("insert-debug-hooks", "H"),
      codegen: CodegenOpts(
        elideLoops: not ctx.enabled("disable-loop-elision"),
        loopAllocationEliminator: not ctx.enabled("disable-loop-allocation-elim"),
        aggressivelyFreeRetvals: not ctx.enabled("aggressively-free-retvals"),
        deadCodeElimination: not ctx.enabled("disable-dead-code-elim"),
        jitCompiler: not ctx.enabled("disable-jit", "Nz"),
      ),
    ),
    predefinedBytecode = readFile(file),
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

proc dumpStatisticsPretty(runtime: Runtime) =
  let stats = runtime.dumpStatistics()

  stdout.styledWriteLine(styleBright, "Runtime Statistics", resetStyle)
  stdout.styledWriteLine(
    fgGreen,
    "Atoms Allocated",
    resetStyle,
    ": ",
    styleBright,
    $stats.atomsAllocated,
    resetStyle,
  )

  when defined(nimAllocStats):
    stdout.styledWriteLine(
      fgGreen,
      "Traced Allocations (Nim-land heap)",
      resetStyle,
      ": ",
      styleBright,
      $stats.numAllocations,
      resetStyle,
    )
    stdout.styledWriteLine(
      fgGreen,
      "Traced Deallocations (Nim-land heap)",
      resetStyle,
      ": ",
      styleBright,
      $stats.numDeallocations,
      resetStyle,
    )
  else:
    stdout.styledWriteLine(
      "* ", styleItalic, styleBright,
      "Cannot show Nim's traced allocations/deallocations; compile Balde with ",
      resetStyle, fgGreen, "--define:nimAllocStats", resetStyle, styleItalic,
      " to see allocation/deallocation statistics.",
    )

  stdout.styledWriteLine(
    fgGreen,
    "Bytecode Size (KB)",
    resetStyle,
    ": ",
    styleBright,
    $stats.bytecodeSize,
    resetStyle,
  )
  stdout.styledWriteLine(
    fgGreen,
    "Code Breaks Generated",
    resetStyle,
    ": ",
    styleBright,
    $stats.breaksGenerated,
    resetStyle,
  )
  stdout.styledWriteLine(
    fgGreen,
    "VM State",
    resetStyle,
    ": ",
    (if stats.vmHasHalted: fgGreen else: fgRed),
    (if stats.vmHasHalted: "Halted" else: "Running"),
    resetStyle,
  )
  stdout.styledWriteLine(
    fgGreen,
    "Field Accesses",
    resetStyle,
    ": ",
    styleBright,
    $stats.fieldAccesses,
    resetStyle,
  )
  stdout.styledWriteLine(
    fgGreen,
    "Typeof Calls",
    resetStyle,
    ": ",
    styleBright,
    $stats.typeofCalls,
    resetStyle,
  )
  stdout.styledWriteLine(
    fgGreen,
    "Clauses Generated",
    resetStyle,
    ": ",
    styleBright,
    $stats.clausesGenerated,
    resetStyle,
  )
  stdout.styledWriteLine(
    fgGreen,
    "GC Heap Size",
    resetStyle,
    ": ",
    styleBright,
    $boehmGetHeapSize(),
    resetStyle,
  )

proc getDumpIRForList(ctx: Input): seq[string] =
  if *ctx.flag("madhyasthal-dump-ir-fns"):
    return split(&ctx.flag("madhyasthal-dump-ir-fns"), ';')

  newSeq[string](0)

func `%`(
    t: tuple[str: Option[string], exc: Option[void], ident: Option[string]]
): JsonNode =
  if *t.str:
    return newJString &t.str

  if *t.exc:
    return "exception".newJString

  if *t.ident:
    return newJString &t.ident

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

  if ctx.enabled("dump-tokens", "T"):
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
    if ctx.enabled("dump-statistics"):
      var runtime =
        allocRuntime(ctx, file = file, ast = ast, dumpIRFor = newSeq[string](0))
      runtime.dumpStatisticsPretty()

    quit 0

  if ctx.enabled("dump-ast"):
    ast.doNotEvaluate = true

  profileThis "allocate runtime":
    var runtime =
      allocRuntime(ctx, file = file, ast = ast, dumpIRFor = getDumpIRForList(ctx))

  profileThis "execution time":
    runtime.run()

  if ctx.enabled("dump-ast"):
    var rawMode = ctx.flag("dump-mode")
    if !rawMode:
      rawMode = some("pretty")

    let mode =
      case &rawMode
      of "pretty":
        dmPretty
      of "json":
        dmJson
      of "json-pretty":
        dmJsonPretty
      else:
        die "invalid mode for dump-mode: " & &rawMode
        dmPretty

    case mode
    of dmPretty:
      print ast
    else:
      die "dump mode not implemented"

  if ctx.enabled("dump-statistics"):
    runtime.dumpStatisticsPretty()

  if ctx.enabled("dump-runtime-after-exec"):
    print runtime

proc execBytecodeFile(file: string) =
  if not fileExists(file):
    die "file not found:", file

  let perms = getFilePermissions(file)
  if fpGroupRead notin perms and fpUserRead notin perms:
    die "access denied:", file

  let bytecode = readFile(file)
  if bytecode.len < 1:
    die "empty bytecode file: " & file

  let runtime = newRuntime(file = file, ast = AST(), predefinedBytecode = bytecode)
  runtime.run()

proc baldeRun(ctx: Input) =
  if not ctx.enabled("verbose", "v"):
    setLogFilter(lvlWarn)

  enableProfiler = ctx.enabled("enable-profiler", "P")

  let arg = ctx.command
  execFile(ctx, arg)

proc baldeRepl(ctx: Input) =
  var prevRuntime: Runtime
  var noise = Noise.init()
  let dumpIRFor = getDumpIRForList(ctx)

  template evaluateSource(ast: AST) =
    var runtime = allocRuntime(ctx, "<repl>", ast, repl = true, dumpIRFor = dumpIRFor)
    if prevRuntime != nil:
      runtime.values = prevRuntime.values
      runtime.vm.stack = prevRuntime.vm.stack
        # Copy all atoms of the previous runtime to the new one

    runtime.run()
    prevRuntime = runtime

  echo "Welcome to Balde, with Bali v" & Version
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
    if not ok:
      break

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
        if value == nil:
          echo $i & ": uninitialized"
          continue

        echo $i & ": " & value.crush() & " <" & $value.kind & '>'
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

        let index =
          try:
            parseInt(args[1])
          except ValueError as exc:
            styledWriteLine(
              stdout, fgRed, "could not parse index for .express", resetStyle, ": ",
              styleBright, exc.msg, resetStyle,
            )
            continue

        if index < prevRuntime.vm.stack.len - 1:
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
            styledWriteLine(
              stdout,
              fgRed,
              "Parse Error",
              resetStyle,
              ": ",
              styleBright,
              $error,
              resetStyle,
            )
        else:
          noise.historyAdd(line)
          evaluateSource ast

  when promptHistory:
    discard noise.historySave(file)

proc showHelp() {.noReturn.} =
  let name = getAppFilename().splitPath().tail
  echo """
Usage: $1 [options] [script]

  The Bali Debugger provides a command line interface to the Bali JavaScript engine.
  If no files are provided for execution, then Balde starts a read-eval-print-loop (REPL)
  session.

Version: $2

Options:
  --help, -h                              Show this message.
  --verbose, -v                           Show additional debug logs, useful for debugging the engine.
  --dump-bytecode, -D                     Dump bytecode for the next evaluation.
  --dump-tokens, -T                       Dump tokens for the provided file.
  --dump-ast                              Dump the abstract syntax tree for the JavaScript file.
  --dump-no-eval                          Dump the abstract syntax tree for the JavaScript file, bypassing the IR generation phase entirely.
  --enable-experiments:<a>;<b>; ... <z>   Enable certain experimental features that aren't stable yet.
  --insert-debug-hooks, -H                Insert some debug hooks that expose JavaScript code to the engine's internals.
  --test262                               Insert some functions similar to those found in Test262.
  --dump-statistics                       Dump some diagnostic statistics from the runtime.
  --incremental                           Set the garbage collector mode to incremental, potentially reducing GC latency.
  --version, -V                           Output the version of Bali/Balde in the standard output
  --evaluate-bytecode, -B                 Evaluate the provided source as bytecode instead of parsing it as JavaScript.

Codegen Flags:
  --disable-loop-elision                  Don't attempt to elide loops in the IR generation phase.
  --disable-loop-allocation-elim          Don't attempt to rewrite loops to avoid unnecessary atom allocations.
  --aggressively-free-retvals             Aggressively zero-out the return-value register.
  --disable-dead-code-elim                Disable dead code elimination during the codegen phase.
  --disable-jit                           Disable the baseline JIT compiler.
""" %
    [name, Version]
  quit(0)

proc main() {.inline.} =
  enableLogging()

  let input = parseInput()
  if input.enabled("version", "V"):
    echo "Bali: " & Version
    echo "Boehm-Demers-Weiser GC: " & $boehmVersion()
    echo "Bali is developed by the Ferus Project. All of the source code is licensed under the GNU General Public License 3."
    quit(0)

  if input.enabled("verbose", "v"):
    setLogFilter(lvlAll)

  if input.enabled("help", "h"):
    showHelp()

  if input.command.len < 1:
    if not input.enabled("verbose", "v"):
      setLogFilter(lvlError)

    baldeRepl(input)
    quit(0)

  initializeGC(GCKind.Boehm, input.enabled("incremental"))

  if input.command.len > 0:
    if not input.enabled("evaluate-bytecode", "B"):
      baldeRun(input)
    else:
      execBytecodeFile(input.command)
  else:
    baldeRepl(input)

  if enableProfiler:
    writeFile("balde_profiler.txt", toJson profile)

when isMainModule:
  main()
