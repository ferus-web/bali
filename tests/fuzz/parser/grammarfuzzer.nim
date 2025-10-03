## A simple program to "fuzz" Bali's parser with randomized inputs.
## Any case where the program exits ungracefully is marked as a bug.
## 
## Copyright (C) 2025 Trayambak Rai
import std/[os, osproc, base64, strutils, random, tables, json, tempfiles, terminal]
import pkg/bali/grammar/prelude
import ./mutator

type
  Verdict {.pure, size: sizeof(uint8).} = enum
    Failed = 0
    Passed = 1
    ParsingError = 2

  Run = object
    input: string
    path: string
    verdict: Verdict

  State = object
    runs: seq[Run]

proc randomStrBuffer(): string =
  var buffer = newStringOfCap(512)
  for i in 0 .. rand(28 .. 510):
    buffer &= sample(Digits + Letters + Whitespace)

  ensureMove(buffer)

proc tryParse(state: var State, i: uint64, exe: string, buff: string) =
  state.runs[i].input = buff

  let path = genTempPath("grammarfuzzer", "-input.js")
  writeFile(path, buff)

  state.runs[i].path = path

  let process = startProcess(command = exe, args = ["try", path])
  let exitCode = process.waitForExit()
  process.close()

  case exitCode
  of 0:
    state.runs[i].verdict = Verdict.Passed
  of 4:
    state.runs[i].verdict = Verdict.ParsingError
  else:
    state.runs[i].verdict = Verdict.Failed

proc displayOutputPretty(state: State) {.sideEffect.} =
  for i, run in state.runs:
    let (file, bg, fg, text) =
      case run.verdict
      of Verdict.Failed:
        (stderr, bgRed, fgBlack, "FAIL")
      of Verdict.Passed:
        (stdout, bgGreen, fgWhite, "PASS")
      of Verdict.ParsingError:
        (stdout, bgYellow, fgBlack, "PARSING ERROR")

    styledWrite(file, bg, fg, text, resetStyle, styleBright, " Run " & $(i + 1))

    if run.verdict == Verdict.ParsingError:
      styledWriteLine(file, " (input file: ", fgBlue, run.path, resetStyle, ")")
    elif run.verdict == Verdict.Passed:
      stdout.write('\n')
    elif run.verdict == Verdict.Failed:
      stdout.write('\n')
      styledWriteLine(
        file, bg, fg, "INPUT FILE", resetStyle, " ", fgBlue, "`", resetStyle,
        styleBright, run.path, resetStyle, fgBlue, "`", resetStyle,
      )

proc displayOutputJson(state: State) {.sideEffect.} =
  stdout.write($(%*state) & '\n')

proc randomBuffer(): string =
  if rand(0 .. 16) > 0:
    genCode()
  else:
    randomStrBuffer()

proc main() =
  if paramCount() < 2:
    quit "Usage: grammarfuzzer [run | try] [iterations/128 | path] [?mode/pretty]"

  if existsEnv("GFUZZ_SEED"):
    randomize(parseInt(getEnv("GFUZZ_SEED")))

  let cmd = paramStr(1)

  case cmd
  of "run":
    let bin = getAppFilename()
    let iter =
      try:
        parseUint(paramStr(2))
      except ValueError:
        128'u

    var state: State
    state.runs = newSeq[Run](iter)
    for i in 0 ..< iter:
      let buff = randomBuffer()
      tryParse(state, i, bin, buff)

      if state.runs[i].verdict == Verdict.Passed:
        removeFile(state.runs[i].path)
    let mode =
      if paramCount() > 2:
        paramStr(3)
      else:
        "pretty"

    case mode
    of "pretty":
      displayOutputPretty(state)
    of "json":
      displayOutputJson(state)
    else:
      quit "Invalid output dumper: `" & mode & "`; valid options are:\n* pretty"

    for run in state.runs:
      if run.verdict == Verdict.Failed:
        quit(1)

    quit(0)
  of "try":
    let parser = newParser(readFile(paramStr(2)))
    let ast = parser.parse()

    if ast.errors.len > 0:
      quit(4)
    else:
      quit(0)
  else:
    quit "Invalid mode: `" & cmd & '`'

when isMainModule:
  main()
