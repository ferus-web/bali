## This is the first example of how to embed Bali into your Nim program.
import pkg/bali/easy

proc main() =
  var runtime = createRuntimeForSource(
    """
console.log("Hello Bali!")
console.log("This is cool, isn't it? :D")
  """
  )

  runtime.run()

when isMainModule:
  main()
