import std/[options]
import bali/grammar/prelude
import bali/runtime/prelude
import pretty

var program = newAST()

let fn = function("do_smt", @[call("console.log", @[identArg "arg"])], @["arg"])
let outer = scope(@[call("do_smt", @[atomArg integer 32])])

program.scopes[0] = outer
program.appendFunctionToCurrentScope(fn)

var runtime = newRuntime("t001.js", program)
runtime.run()
