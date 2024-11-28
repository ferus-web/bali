# Package

version         = "0.4.0"
author          = "xTrayambak"
description     = "The Bali JavaScript Engine"
license         = "GPL3"
srcDir          = "src"
backend         = "cpp"
bin             = @["balde", "test262"]
installExt      = @["nim"]
binDir          = "bin"

# Dependencies

requires "nim >= 2.0.2"
requires "mirage >= 1.0.41"
requires "librng >= 0.1.3"
requires "pretty >= 0.1.0"
requires "colored_logger >= 0.1.0"
requires "simdutf >= 5.5.0"
requires "https://github.com/ferus-web/sanchar >= 2.0.2"
requires "jsony >= 1.1.5"
requires "crunchy >= 0.1.11"
requires "climate >= 1.1.1"
requires "results >= 0.5.0"

taskRequires "fmt", "nph#head"
task fmt, "Format code":
  exec "nph src/ tests/"
