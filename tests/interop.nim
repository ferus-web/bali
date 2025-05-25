import bali/grammar/prelude
import bali/runtime/prelude
import bali/internal/sugar

proc main() {.inline.} =
  let parser = newParser(
    """
let greeting = greet("tray")
console.log(greeting)

function shoutify(name)
{
  // Make a name seem like it's been SHOUTED OUT.
  var x = new String(name);
  var y = x.toUpperCase()

  return y
}
"""
  )
  let ast = parser.parse()
  var runtime = newRuntime("interop.js", ast)

  runtime.defineFn(
    "greet",
    proc() =
      let arg = runtime.ToString(&runtime.argument(1))
      ret str("Hi there, " & arg)
    ,
  )

  runtime.run()
  
  let fn = runtime.get("shoutify")
  if !fn:
    return

  let retval = runtime.call(&fn, str("tray"))
  echo "I AM SHOUTING YOUR NAME AT YOU, " & runtime.ToString(retval)

when isMainModule:
  main()
