import bali/grammar/prelude
import bali/runtime/prelude
import bali/internal/sugar

proc main() {.inline.} =
  let parser = newParser(
    """
let greeting = greet("tray")
console.log(greeting)
"""
  )
  let ast = parser.parse()
  let runtime = newRuntime("interop.js", ast)

  runtime.defineFn(
    "greet",
    proc() =
      let arg = runtime.ToString(&runtime.argument(1))
      ret str("Hi there, " & arg)
    ,
  )

  runtime.run()

when isMainModule:
  main()
