import std/unittest
import
  pkg/bali/runtime/prelude,
  pkg/bali/grammar/prelude,
  pkg/bali/stdlib/errors,
  pkg/pretty,
  pkg/bali/runtime/vm/interpreter/interpreter

var success {.threadvar.}: bool

test "death callback test":
  var parser = newParser(
    """
throw "meow meow mrrp"
  """
  )

  let ast = parser.parse()

  var runtime = newRuntime("tdeathcallback.js", ast)
  runtime.deathCallback = proc(interp: PulsarInterpreter) =
    raise newException(IOError, "Yippee.")

  expect IOError:
    runtime.run()
