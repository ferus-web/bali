## The Bali "easy" module.
## 
## Use this to make Bali's already-simple API even simpler. Get all of Bali's uses while on easy-mode.
## It doesn't get easier than this. :^)
import std/os
import pkg/bali/grammar/[ast, parser], pkg/bali/runtime/prelude

export prelude

proc createRuntimeForSource*(source: string): Runtime =
  ## Parse a JavaScript `source` string and
  ## create an execution runtime for it.

  var parser = newParser(source)
  let ast = parser.parse()

  newRuntime("<eval>", ast)

proc createRuntimeForFile*(file: string): Runtime =
  ## Parse a JavaScript file's contents and
  ## create an execution runtime for it.
  ##
  ## This function handles some cases for the file itself (like it not existing).
  if not fileExists(file):
    raise newException(
      IOError,
      "Failed to open JavaScript source file `" & file & "`: File does not exist!",
    )

  var parser = newParser(readFile(file))
  let ast = parser.parse()

  newRuntime(file, ast)

proc isValidJS*(source: string): bool =
  ## Given a JavaScript source, parse it to check whether it is free
  ## of any syntactical errors.
  ##
  ## This function returns `true` if the following condition is met,
  ## and `false` otherwise.
  var parser = newParser(source)
  let ast = parser.parse()

  ast.errors.len < 1
