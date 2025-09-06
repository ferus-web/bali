# Bali
Bali (ˈbɑːli) is a work-in-progress JavaScript lexer, parser and interpreter written in Nim that aims to be as compliant as possible to the ECMAScript specifications. \
Bali is still not in a usable state yet and is probably unstable. It is not meant to be used in production for now.

Bali has a bytecode VM as well as two tiers of x86-64 JIT compilers (baseline and midtier).
It also has a tiering mechanism in place to promote functions from the VM to the Baseline JIT to the Midtier JIT as they get hotter.

Bali is licensed under the BSD-3 license, allowing you to freely embed it in any of your programs.

# Integrating Bali into your programs
Bali is still an alpha-quality project, but here's how you can embed Bali into your Nim programs.
With it, you can:
- Use JavaScript as a configuration language for your programs
- Write stuff for the JS ecosystem with Nim
and much, much more. (It becomes more useful as it advances!)

For more information, check out the `examples/` directory as well as the [Bali Manual](https://bali.xtrayambak.xyz).

# Usage
* Bali is integrated into the [Ferus web engine](https://github.com/ferus-web/ferus) and used as the JavaScript runtime's backend
* It is integrated into [Basket](https://github.com/xTrayambak/basket), a fast app launcher for Wayland compositors for configuration. \
Have a cool project that you use Bali in? Open a PR and add it here! :^)

# How compliant is it?
Thanks to [@CanadaHonk](https://github.com/CanadaHonk), Bali is now on [test262.fyi](https://test262.fyi/#|bali)! \
You can check how much Bali progresses/regresses by each day's run.

# How "well written" is it?
Bali is formatted using the [nph](https://github.com/arnetheduck/nph) code formatter and each commit is statically analyzed by [Nimalyzer](https://github.com/thindil/nimalyzer).

It isn't indicative of the code quality, but I do put some extent into making the code slightly readable. :^)

# How fast is it?
With some recent codegen optimizations, Bali is already pretty fast on cherry-picked benchmarks. Bali can perform some optimizations when it is generating code for the provided JavaScript source, granted that it can prove that there is an opportunity to optimize away things.

It also has some rudimentary dead code elimination for some cases.

**CPU**: AMD Ryzen 5 5600H (12) @ 4.28 GHz \
**RAM**: 16 GB + 32GB swap

## Iterating 999999999 times and incrementing an integer each loop
Bali has some loop elision optimizations in place which can fully eliminate an expensive loop when it sees the opportunity.

**NOTE**: The "JIT" benchmark is actually misleading, because here the "hot part" of the code is fully removed during bytecode generation.
The JIT is never triggered since there's nothing to optimize.
As such, both of these benchmarks are actually just running in the interpreter. :^)

**Try it for yourself**: [Source code](tests/data/iterate-for-no-reason-001.js)
| Engine                  | Time Taken                                                     |
| ----------------------- | -------------------------------------------------------------- |
| Bali (Interpreter)      | 3.9ms (best case) - 5.9ms (worst case)                         |
| Bali (JIT)              | 3.9ms (best case) - 6.0ms (worst case)                         |   

This proves that the JIT barely worsens the worst case scenario.

## Finding a substring in a moderately large string
Bali's string-find function (`String.prototype.indexOf`) is SIMD-accelerated, and as such, is pretty fast.

**NOTE**: The "JIT" benchmark is actually misleading, because here the "hot part" of the code is fully removed during bytecode generation.
The JIT is never triggered since there's nothing to optimize.
As such, both of these benchmarks are actually just running in the interpreter. :^)

**Try it for yourself**: [Source code](tests/data/string-find-001.js)
| Engine                     | Time Taken                                   |
| -------------------------- | -------------------------------------------- |
| Bali (Interpreter)         | 4.1ms (best case) - 6.1ms (worst case)       |
| Bali (JIT)                 | 4.1ms (best case) - 7.1ms (worst case)       |

## JIT-triggering microbenchmark
This script is intentionally designed to make Bali's profiling mechanism catch onto it and optimize it.

**Try it for yourself**: [Source code](tests/data/trigger-jit-001.js)
| Engine                     | Time Taken                                   |
| -------------------------- | -------------------------------------------- |
| Bali (Interpreter)         | 586.9ms (best case) - 601.3ms (worst case)   |
| Bali (JIT)                 | 356.7ms (best case) - 374.5ms (worst case)   |

Here, the JIT is **1.65x** faster than the interpreter!

# Contact Me
You can join the [Ferus Discord Server](https://discord.gg/9MwfGn2Jkb) to discuss Bali and other components of the Ferus web engine.

# Specification Compliance
As of 9th of November, 2024, Bali can successfully run 1% of the entire Test262 suite* (I believe that our test runner is currently under-estimating).
There's a lot of work to be done here, so don't shy away from sending in PRs. ;)

# Running code with Bali
You can compile Balde, the Bali debugger by running:
```
$ nimble build balde
```
You can run it with no arguments and it'll start up in a REPL. \
It is primarily used for debugging the engine as of right now, but it runs code fine too.

# Integrating Bali into your applications
**Bali requires the C++ backend to be used as it depends on simdutf and LibICU!**

You need to provide Bali with three dependencies: **simdutf**, **icu** (version 76) and **gmp**. Most of these can be installed via your system's package manager.

Firstly, add Bali to your project's dependencies.
```
$ nimble add gh:ferus-web/bali
```
Here is a basic example of the API:
```nim
import pkg/bali/grammar/prelude
import pkg/bali/runtime/prelude

const JS_SRC = """
console.log("Hello world!")
console.log(13 + 37)

var myUrl = new URL("https://github.com/ferus-web/bali")
console.warn(myUrl.origin)

var commitsToBali = 171
while (commitsToBali < 2000) {
    commitsToBali++
    console.log(commitsToBali)
}

for (var x = 0; x < 32; x++) { console.log("Hello, number", x) }

try
{
    throw "woe be upon ye";
} catch (error_thingy)
{
    console.log(error_thingy)
}

const encoded = btoa("Hello base64")

let lemonade = fetchLemonade(4)
console.log(lemonade)
"""

let 
  parser = newParser(JS_SRC) # Feed your JavaScript code to Bali's JavaScript parser
  ast = parser.parse() # Parse an AST out of the tokens
  runtime = newRuntime("myfile.js", ast) # Instantiate the JavaScript runtime.

# define a native function which is exposed to the JavaScript code
runtime.defineFn(
    "fetchLemonade",
    proc =
      let num = runtime.ToNumber(&runtime.argument(1))

      if num == 0 or num > 1:
        ret str("You have " & $num & " lemonades!")
      else:
        ret str("You have a lemonade!")
)

# Emit Mirage bytecode and pass over control to the Mirage VM.
# NOTE: This is a blocking function and will block this thread until execution is completed (or an error is encountered and the
# interpreter is halted)
runtime.run()
```

# Roadmap
- [X] Getting a grammar to AST parser
- [X] Getting the MIR emitter working
- [X] Get arithmetic operations working
- [X] Console API
- [X] While loops
- [X] Nested object field access
- [X] `typeof`
- [X] Arrays
- [X] REPL
- [X] String prototype
- [X] Date prototype
- [X] Ternary operations
- [X] Functions as values
- [X] For-loops
- [X] Try-catch clauses
- [X] Compound assignments
- [X] x86-64 JIT compiler (2 tiers)
- [ ] Modules
- [ ] Async
