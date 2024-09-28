import std/tables
import bali/grammar/prelude
import pretty
import ../common

enableLogging()
let parser = newParser(
  """
function main() {
  let x = "e"
  let y = "this is truly a moment"
}

main()
"""
)

let ast = parser.parse()
print parser.errors
print ast
