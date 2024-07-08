import std/[os, tables]
import bali/grammar/prelude
import bali/runtime/prelude
import pretty
import ../common

enableLogging()
let parser = newParser(
  readFile paramStr 1
)

let ast = parser.parse()
print parser.errors
print ast

let runtime = newRuntime("t003.js", ast)
runtime.run()
