## Test262 runner for Bali

import std/[os, osproc, json, posix, strutils, logging, math, times]
import colored_logger

const BASE_DIR = "test262/test"

type RunResult = enum
  Success
  Error
  Segfault

proc execJS(
    file: string, dontEval: bool, num, total: uint, timeout: uint = 10
): RunResult =
  info " [ " & $num & " / " & $total & " / " & $(round(num.int / total.int * 100, 1)) &
    "% ] " & file
  let cmd =
    "timeout --signal=SIGKILL " & $timeout & " ./bin/balde " & file & " --test262" &
    $(if dontEval: " --dump-ast" else: "")

  echo cmd
  case execCmd(cmd)
  of 0:
    return Success
  of 139:
    return Segfault
  else:
    return Error

proc main() {.inline.} =
  addHandler(newColoredLogger())
  addHandler(newFileLogger("test262.log"))

  let startTime = epochTime()

  if paramCount() < 1:
    quit """
test262 [cmd] [arguments]

Commands:
  run-all-tests-rec           Recursively run all tests in a directory using Balde

Flags:
  --dont-evaluate             All tests that can be parsed are marked as a success
"""

  let cmd = paramStr(1)
  let dontEval = paramCount() >= 3 and paramStr(3) == "--dont-evaluate"

  discard existsOrCreateDir("outcomes")

  case cmd
  of "run-all-tests-rec":
    if paramCount() < 2:
      quit "`run-all-tests-rec` expects HEAD as a directory to start recursive test execution from."

    let head = paramStr(2)

    var files: seq[string]

    if not dirExists(BASE_DIR / head):
      error "Invalid testing category: " & head
      quit(1)

    var successful, failed, skipped, segfaulted: seq[string]

    for file in walkDirRec(BASE_DIR / head):
      if not fileExists(file):
        continue
      if file.contains("harness"):
        continue
      if not file.endsWith(".js"):
        skipped &= file
        continue

      files &= file

    for i, file in files:
      case execJS(file, dontEval, i.uint, files.len.uint)
      of Success:
        info "Worker for file `" & file & "` has completed execution successfully."
        successful &= file
        continue
      of Error:
        warn "Test for `" & file & "` has failed."
        failed &= file
        continue
      of Segfault:
        warn "!!!! Test for `" & file &
          "` exited ungracefully with a segmentation fault !!!!:7"
        segfaulted &= file
        continue

    let endTime = epochTime()
    let secondsTaken = endTime - startTime

    let
      successPercentage = (successful.len / files.len) * 100f
      segfaultPercentage = (segfaulted.len / files.len) * 100f
      failedPercentage = (failed.len / files.len) * 100f

    if failed.len > 0:
      info "The following tests have failed:"
      for i, fail in failed:
        if i > 16:
          echo "  ... and " & $(failed.len - i) & " more."
          break

        echo "  * " & fail

    if segfaulted.len > 0:
      info "The following tests have abnormally exited:"
      for i, seg in segfaulted:
        if i > 16:
          echo "  ... and " & $(segfaulted.len - i) & " more."
          break

        echo "  * " & seg

    if paramCount() > 1 and paramStr(2) == "json":
      let data =
        $(
          %*{
            "total": $files.len,
            "successful": $successful.len,
            "skipped": $skipped.len,
            "failed": $failed.len,
            "segfaulted": $segfaulted.len,
            "successful_percentage": $successPercentage,
            "runtime_seconds": $secondsTaken,
          }
        )
      echo data
      writeFile("test262.json", data)
    else:
      info "Total tests: " & $files.len
      info "Successful tests: " & $successPercentage & "% (" & $successful.len & ')'
      info "Failed tests: " & $failedPercentage & "% (" & $failed.len & ')'
      info "Abnormal crashes: " & $segfaultPercentage & "% (" & $segfaulted.len & ')'

    var dumpBufferFail, dumpBufferSucc: string
    for passed in successful:
      dumpBufferSucc &= passed & '\n'

    for fail in failed:
      dumpBufferFail &= fail & '\n'

    writeFile("failed.txt", dumpBufferFail)
    writeFile("success.txt", dumpBufferSucc)

    info "It took " & $(secondsTaken / 60) & " minutes to run all of the " & $files.len &
      " tests."

when isMainModule:
  main()
