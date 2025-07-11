import
  pkg/bali/runtime/prelude, pkg/bali/grammar/prelude, pkg/bali/stdlib/errors, pkg/pretty

var parser = newParser(
  """
function x() { console.log("hi") }

x()
"""
)

let ast = parser.parse()

setDeathCallback(
  proc(_: auto, exitCode: int) =
    echo "oopsies"
)

var runtime = newRuntime("tdeathcallback.js", ast)
runtime.run()
