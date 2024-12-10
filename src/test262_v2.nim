## Test262 runner, take 2
when not defined(posix):
  {.error: "test262_v2 cannot run on a non-POSIX compliant system.".}

import std/[os, strutils, posix, locks, logging, importutils]
import pkg/[colored_logger]
import bali/grammar/prelude
import mirage/runtime/pulsar/interpreter
import bali/stdlib/errors
import bali/internal/sugar
import bali/runtime/prelude

privateAccess(PulsarInterpreter)

const BASE_DIR = "test262/test"

type
  AgentParentSharedBuffer* = object
    statusLock*, consoleBufferLock*: Lock

    status* {.guard: statusLock.}: bool = false
    consoleBuffer* {.guard: consoleBufferLock.}: string
    sourceBuffer*: string
    fileName*: string

  Report* = object
    passing*: seq[string]
    failing*: seq[string]
    total*: uint

proc dump*(report: Report) =
  echo "Result: $1/$2 error$3" % [$report.failing.len, $report.total, if report.total != 1: "s" else: newString(0)]

proc startAgent*(buffer: pointer) =
  var buffer = cast[ptr AgentParentSharedBuffer](buffer)
  
  let parser = newParser(buffer.sourceBuffer)
  let ast = parser.parse()

  var runtime = newRuntime(buffer.fileName, ast, opts = InterpreterOpts(test262: true))
  runtime.run()
  
  withLock buffer[].statusLock:
    buffer[].status = runtime.vm.trace == nil

proc summonAgent*(report: var Report, file: string) =
  var buffer: AgentParentSharedBuffer
  buffer.statusLock.initLock()
  buffer.consoleBufferLock.initLock()
  withLock buffer.statusLock: buffer.status = false
  withLock buffer.consoleBufferLock: buffer.consoleBuffer = newString(0)
  buffer.sourceBuffer = readFile(file)
  buffer.fileName = file
  
  startAgent(buffer.addr)
  withLock buffer.statusLock:
    if buffer.status:
      info file & " has passed successfully."
      report.passing &= file
    else:
      warn file & " has failed execution."
      report.failing &= file
   
  #var thr: Thread[pointer]
  #createThread(thr, startAgent, buffer.addr)

proc main {.inline.} =
  setDeathCallback(
    proc(_: PulsarInterpreter, exitCode: int = 1) =
      # A temporary hack around exception traces immediately quitting
      warn "Interpreter instance wanted to exit with code: " & $exitCode
  )
  var
    report: Report
    files: seq[string]
    skipped: seq[string]

  let head = paramStr(1)

  for file in walkDirRec(BASE_DIR / head):
    if not fileExists(file):
      continue
    if file.contains("harness"):
      continue
    if not file.endsWith(".js"):
      skipped &= file
      continue

    files &= file

  report.total = files.len.uint

  for file in files:
    report.summonAgent(file)

  report.dump()

when isMainModule:
  main()
