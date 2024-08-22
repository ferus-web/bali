import std/[os, osproc, json, posix, strutils, logging, tables]
import bali/grammar/prelude
import bali/runtime/prelude
import colored_logger, pretty

const BASE_DIR = "test262/test"

proc execJS(file: string): bool =
  execCmd("./balde run " & file) == 0

proc main {.inline.} =
  addHandler(newColoredLogger())
  addHandler(newFileLogger("test262.log"))

  if paramCount() < 1:
    quit """
test262 [cmd] [arguments]

Commands:
  run-all-tests-rec           Recursively run all tests in a directory using Balde
"""

  let cmd = paramStr(1)

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

    var
      successful, failed: seq[string]

    for file in walkDirRec(BASE_DIR / head):
      if not fileExists(file): continue
      if not file.endsWith(".js"): continue

      inc filesToExec

      if execJS(file):
        info "Worker for file `" & file & "` has completed execution successfully."
        successful &= file
        continue
      else:
        warn "Test for `" & file & "` has failed."
        failed &= file
        continue
    
    let
      successPercentage = (successful.len / filesToExec) * 100f
      failedPercentage = (failed.len / filesToExec) * 100f
    
    if failed.len > 0:
      info "The following tests have failed:"
      for i, fail in failed:
        if i > 16:
          echo "  ... and " & $(failed.len - i) & " more."
          break

        echo "  * " & fail
    
    info "Total tests: " & $filesToExec
    info "Successful tests: " & $successPercentage & "% (" & $successful.len & ')'
    info "Failed tests: " & $failedPercentage & "% (" & $failed.len & ')'
      
when isMainModule: main()
