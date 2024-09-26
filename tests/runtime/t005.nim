import std/[logging]
import colored_logger
import bali/grammar/prelude
import bali/runtime/prelude
import pretty

addHandler(newColoredLogger())

var program = newAST()
var doMathsArgs: PositionedArguments
doMathsArgs.pushIdent("x")

let fn = function(
  "do_maths",
  @[
    call("console.log",
      doMathsArgs
    )
  ],
  @["x"]
)
program.appendFunctionToCurrentScope(fn)

var args: PositionedArguments
args.pushImmExpr(
  Statement(
    kind: BinaryOp,
    binLeft: atomHolder(integer(13)),
    binRight: atomHolder(integer(37)),
    op: BinaryOperation.Add
  )
)

program.appendToCurrentScope(call("do_maths", args))

var runtime = newRuntime("t001.js", program)
runtime.run()
