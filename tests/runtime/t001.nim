import std/[options]
import bali/grammar/prelude
import bali/runtime/prelude
import pretty

#[ Should emit bytecode:
  CLAUSE main
    LOADI 1 32
  END main
]#

var program = newAST()

let fn = function(
  some("outer"),
  @[
    createImmutVal("x", integer(32)), # equivalent to `const x = 32`
    createImmutVal("y", integer(32)),
    ifCond(
      lhs = "x", rhs = "y", ecEqual
    ),
    call("console.log", 
      @[
        atomArg integer 32
      ]
    )
  ]
)
program &= fn

var runtime = newRuntime("t001.js", program)
runtime.run()
