## Balde - the Bali Debugger
##
## Copyright (C) 2024 Trayambak Rai and Ferus Authors

when not isMainModule:
  {.error: "This file is not meant to be separately imported!".}

import std/[logging]
import bali/runtime/prelude
import climate, colored_logger

proc enableLogging* {.inline.} =
  addHandler newColoredLogger()

proc main {.inline.} =
  const commands = {
    "run": baldeRun,
    "dump-ast": baldeDumpAst,
    "tokenize": baldeTokenize
  }
