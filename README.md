# Bali
Bali is a WIP JavaScript engine written in Nim that aims to be as compliant as possible to the ECMAScript specifications. \
Bali is still not in a usable state yet and is probably unstable. It is not meant to be used in production for now.

I repeat,

Bali is still not in a usable state yet and is probably unstable. It is not meant to be used in production for now.

# Contact Me
You can join the [Ferus Discord Server](https://discord.gg/9MwfGn2Jkb) to discuss Bali and other components of the Ferus web engine.

# Specification Compliance
As of 10th of September, 2024, Bali can successfully run 2% of the entire Test262 suite. There's a lot of work to be done here, so don't shy away from sending in PRs. ;)

# Running code with Bali
You can compile Balde, the Bali debugger by running:
```
$ nimble balde
```
It is primarily used for debugging the engine as of right now, but it runs code fine too.

# Integrating Bali into your applications
Again, Bali is not in a usable state yet. However, it is possible to use Bali in your programs. There is no easy Nim-to-JS conversion layer yet, most of the JS code that calls Nim is using a lot of hacks and bridges provided by Mirage. \
**Balde requires the C++ backend to be used as it depends on simdutf!**

Firstly, add Bali to your project's dependencies.
```
$ nimble add gh:ferus-web/bali
```
Here is a basic example of the API:
```nim
import bali/grammar/prelude
import bali/runtime/prelude

const JS_SRC = """
console.log(\"Hello world!\")
console.log(13 + 37)

var myUrl = new URL("https://github.com/ferus-web/bali")
console.warn(myUrl.origin)
"""

let 
  parser = newParser(JS_SRC) # Feed your JavaScript code to Bali's JavaScript parser
  ast = parser.parse() # Parse an AST out of the tokens
  runtime = newRuntime("myfile.js", ast) # Instantiate the JavaScript runtime.

# Emit Mirage bytecode and pass over control to the Mirage VM.
# NOTE: This is a blocking function and will block this thread until execution is completed (or an error is encountered and the
# interpreter is halted)
runtime.run()
```

# Roadmap
- Getting a grammar to AST parser      [X]
- Getting the MIR emitter working      [X]
- Get arithmetic operations working    [X]
- Console API                          [X]
- While loops                          [X]
- For loops                            [ ]
- Modules                              [ ]
- Async                                [ ]
