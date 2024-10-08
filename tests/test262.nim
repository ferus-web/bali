## Test262 runner for Bali
## Copyright (C) 2024 Trayambak Rai and Ferus Authors

import std/[os, osproc, json, posix, strutils, logging, tables, times]
import bali/grammar/prelude
import bali/runtime/prelude
import colored_logger, pretty

const BASE_DIR = "test262/test"

type
  RunResult = enum
    Success
    Error
    Segfault

proc execJS(file: string, dontEval: bool): RunResult =
  case execCmd("./balde run " & file & " --test262" & $(if dontEval: " --dump-ast" else: ""))
  of 0: return Success
  of 1: return Error
  of 139: return Segfault
  else: return Error

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

    var filesToExec = 0

    if not dirExists(BASE_DIR / head):
      error "Invalid testing category: " & head
      quit(1)

    var successful, failed, skipped, segfaulted: seq[string]

    for file in walkDirRec(BASE_DIR / head):
      if not fileExists(file):
        continue
      if not file.endsWith(".js"):
        skipped &= file
        continue

      inc filesToExec

      case execJS(file, dontEval)
      of Success:
        info "Worker for file `" & file & "` has completed execution successfully."
        successful &= file
        continue
      of Error:
        warn "Test for `" & file & "` has failed."
        failed &= file
        continue
      of Segfault:
        warn "!!!! Test for `" & file & "` exited ungracefully with a segmentation fault !!!!"
        segfaulted &= file
        continue

    let endTime = epochTime()
    let secondsTaken = endTime - startTime

    let
      successPercentage = (successful.len / filesToExec) * 100f
      segfaultPercentage = (segfaulted.len / filesToExec) * 100f
      failedPercentage = (failed.len / filesToExec) * 100f

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
      let data = $(
        %*{
          "total": $filesToExec,
          "successful": $successful.len,
          "skipped": $skipped.len,
          "failed": $failed.len,
          "segfaulted": $segfaulted.len,
          "successful_percentage": $successPercentage,
          "runtime_seconds": $secondsTaken
        }
      )
      echo data
      writeFile("test262.json", data)
    else:
      info "Total tests: " & $filesToExec
      info "Successful tests: " & $successPercentage & "% (" & $successful.len & ')'
      info "Failed tests: " & $failedPercentage & "% (" & $failed.len & ')'
      info "Abnormal crashes: " & $segfaultPercentage & "% (" & $segfaulted.len & ')'

    info "It took " & $(secondsTaken / 60) & " minutes to run all of the " & $filesToExec & " tests."

when isMainModule:
  main()
