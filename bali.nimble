# Package

version       = "0.2.0"
author        = "xTrayambak"
description   = "The Bali JavaScript Engine"
license       = "MIT"
srcDir        = "src"


# Dependencies

requires "nim >= 2.0.2"
requires "mirage >= 0.1.8"
requires "librng >= 0.1.3"
requires "pretty >= 0.1.0"
requires "colored_logger >= 0.1.0"

task balde, "Compile the Bali debugger":
  exec "nimble uninstall bali"
  exec "nimble install"

  when defined(release):
    exec "nim c -d:release -d:speed -d:flto --out:./balde src/bali/balde.nim"
  else:
    when not defined(gdb):
      exec "nim c --out:./balde src/bali/balde.nim"
    else:
      exec "nim c -d:useMalloc --debugger:native --profiler:on --outer:./balde src/bali/balde.nim"
