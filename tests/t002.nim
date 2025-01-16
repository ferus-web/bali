import std/[os, tables]
import bali/grammar/prelude
import pretty
import common

enableLogging()
let parser = newParser(
  """
function main() {
  console.log("Hello world!")
}
"""
)

let ast = parser.parse()
print parser.errors
print ast
