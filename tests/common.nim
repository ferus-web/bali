import std/[logging]
import pretty, colored_logger

proc enableLogging* {.inline.} =
  addHandler newColoredLogger()

export pretty
