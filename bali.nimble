# Package

version = "0.6.3"
author = "xTrayambak"
description = "The Bali JavaScript Engine"
license = "GPL3"
srcDir = "src"
backend = "cpp"
# bin = @["balde", "test262"]
installExt = @["nim"]
binDir = "bin"

# Dependencies

requires "nim >= 2.2.0"
requires "librng >= 0.1.3"
requires "pretty >= 0.1.0"
requires "colored_logger >= 0.1.0"
requires "simdutf >= 6.1.1"
requires "https://github.com/ferus-web/sanchar >= 2.0.2"
requires "jsony >= 1.1.5"
requires "crunchy >= 0.1.11"
requires "results >= 0.5.0"
requires "noise >= 0.1.10"
requires "fuzzy >= 0.1.0"
requires "yaml >= 2.1.1"
requires "kaleidoscope >= 0.1.1"
requires "https://github.com/ferus-web/nim-gmp >= 0.1.0"
requires "ferrite >= 0.1.3"
requires "icu4nim >= 76.1.0.1"
requires "mimalloc >= 0.3.1"
requires "zippy >= 0.10.16"
requires "nimsimd >= 1.3.2"
requires "flatty >= 0.3.4"
requires "ptr_math >= 0.3.0"

taskRequires "fmt", "nph#master"
task fmt, "Format code":
  exec "nph src/ tests/"

taskRequires "analyze", "nimalyzer >= 0.12.0"
task analyze, "Run the static analyzer":
  exec "nimalyzer nimalyzer.cfg"

task balde, "Compile balde":
  exec "nim c -o:bin/balde src/balde.nim"
