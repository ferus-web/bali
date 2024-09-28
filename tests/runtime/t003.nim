import std/tables
import bali/grammar/prelude
import bali/runtime/prelude
import pretty
import ../common

enableLogging()
let parser = newParser(
  """
function main() {
  let x = "e"
  let y = "this is truly a moment"
  console.log(x)
}

main()
"""
)

let ast = parser.parse()
print parser.errors
print ast

let runtime = newRuntime("t003.js", ast)
runtime.run()
