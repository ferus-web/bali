import std/[os, tables]
import bali/grammar/prelude
import pretty
import ../common

enableLogging()
let parser = newParser(readFile(paramStr(1)))

let ast = parser.parse()
print parser.errors
print ast
