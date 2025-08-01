# Bali Manual
**Author**: Trayambak Rai (xtrayambak at disroot dot org)

**Version Series Targetted**: 0.7.x

This manual is largely inspired by Monoucha's manual.

**WARNING**: Bali is only tested with the default memory management strategy (ORC). It uses ORC extensively and as such, it will probably not compile with other strategies.

**WARNING**: If you embed Bali in your program, you must compile it with the C++ backend as Bali relies on some C++ libraries.

**This manual is largely under construction. Report problems if you can.**

# Table of Contents
* [Introduction](#introduction)
    - [Terms to learn](#terms-to-learn)
        - [Atom](#atom)
    - [Drooling Baby's First Scripts](#drooling-babys-first-scripts)
    - [Baby's First Scripts](#babys-first-scripts)
* [Creating new types](#creating-new-types)
    - [Wrapping Primitives](#wrapping-primitives)
    - [Wrapping our Type](#wrapping-our-type)
    - [Modifying our Type's Prototype](#modifying-our-prototype)
* [Supported ECMAScript APIs](#supported-ecmascript-apis)
    - [The Math type](#the-math-type)
    - [The JSON type](#the-json-type) 
    - [The URL type](#the-url-type)
    - [The BigInt type](#the-bigint-type)
    - [The String type](#the-string-type)
    - [The Date type](#the-date-type)
    - [The Number type](#the-number-type) 
    - [The Set type](#the-set-type)
* [Using Balde](#using-balde)
    - [Running scripts](#running-scripts)
    - [Flags](#flags)
    - [Using the REPL](#using-the-repl)
    - [Experiments](#experiments)
* [Controlling Codegen](#controlling-codegen)
    - [Prelude](#prelude)
    - [Loop Elision](#loop-elision)
    - [Loop Allocation Elision](#loop-allocation-elision)
    - [Return-value register scrubber](#return-value-register-scrubber)
    - [Disabling optimizations](#disabling-optimizations)
* [Using the Native Interface](#using-the-native-interface)
    - [A small example](#a-small-example)

# Introduction
Bali is a JavaScript engine written from scratch in Nim for the [Ferus web engine](https://github.com/ferus-web/ferus). It is designed to be convenient to interface with whilst being fast and compliant. It provides you high-level abstractions as far as humanly possible.

Currently, it has a fairly-fast bytecode VM as well as a baseline JIT compiler for x86-64 SysV systems.

Bali is evolving very quickly, and as such, the API is subject to breaking. Such changes will be generally marked by a bump in the minor version.

## Terms to learn
Although not evident at first, learning these terms will make things much easier for you.

### Atom
An atom is a variant type discriminated by its `kind` field that can be:
- An integer (signed)
- An integer (unsigned)
- A float (64-bit)
- A string
- A sequence (of more atoms, but you can mark it as homogenous to restrict it to one type)
- An object (basically, an overglorified hashmap)
There's also an identifier type, but that's only internally used by Mirage.

A `JSValue` is a pointer to an atom, and it is generally what is used instead of a `MAtom`, to facilitate easier value manipulation.

## Drooling Baby's First Scripts
We'll now learn how to use Bali's `easy` module, which as the name suggests, gives you the simplest-possible way to execute JavaScript in Nim. It is incredibly dumbed down, and you're recommended to not use it for serious projects where more control over the entire execution flow is required.

All you need to is import a single component: `bali/easy`
```nim
import pkg/bali/easy

proc main() =
  var runtime = createRuntimeForSource(
    """
console.log("Goo goo ga ga")
console.log("It doesn't get simpler than this.")
  """
  )

  runtime.run()

when isMainModule:
  main()
```

It's mostly meant to be used as a gentle introduction to using Bali.

## Baby's First Scripts
Now, we'll learn how to write a Nim program that can load and evaluate JavaScript. You'll need to import two of Bali's components:
- The `grammar` module, which as the name suggests, is responsible for lexing and parsing the JavaScript source code into an abstract syntax tree
- The `runtime` module, which takes in the AST and converts it into bytecode that targets the [Mirage/Pulsar](https://github.com/ferus-web/mirage) interpreter.

However, all of the complexities are neatly abstracted away, so you needn't worry about all of that. The API is deceptively simple.
Here's the minimal example.
```nim
import bali/grammar/prelude
import bali/runtime/prelude

# Create a parser.
let parser = newParser("""
console.log("Hello from JavaScript!")
""")

# Parse the source code into an AST.
let ast = parser.parse()

# Instantiate the runtime, which generates the bytecode and runs it.
# You can optionally pass on a filename, it only exists to keep the
# bytecode caching mechanism work.
let runtime = newRuntime("nameofyourfile.js", ast)

# Begin execution. This halts your code until execution is completed.
runtime.run()
```
Let's breakdown what each line does:
- We're creating a parser with `newParser()` and feeding it our source code.
- We're parsing the source code into an abstract syntax tree.
- We're feeding the AST to the runtime.
- We're running the generated bytecode.

That's it! You just executed JavaScript with Bali! Yay.

# Creating new types
Now, let us learn how to create new types. Bali can automatically "wrap" a Nim object into its representative atom.
Bali can do this for primitives like integers, floats, strings and sequences of said primitives as well.

## Wrapping Primitives
Let us try wrapping some primitives into atoms before wrapping a Nim object.
```nim
import std/options
import bali/runtime/prelude

let name = "John Doe"
let age = 24'u
let likes = @["Skating", "Tennis", "Programming"]

let aName = wrap(name)
let aAge = wrap(age)
let aLikes = wrap(likes)

assert aName.kind == String
assert aAge.kind == Integer
assert aLikes.kind == Sequence

assert aName.isSome and aName.getStr().get() == name
assert aAge.isSome and aAge.getInt().get() == age
```
**NOTE**: When you call `wrap()`, Bali allocates the object's on the heap, which is normally controlled by the Boehm GC! Do not free the pointer unless you're 100% sure it's no longer needed. Due to how Bali is designed, deallocating a `JSValue` can cause a ripple effect where other parts of the code holding onto the pointer won't notice it, and will subsequently perform a user-after-free! Henceforth, leave deallocations to the GC, because it's smarter than you.
Here, we just turned Nim types into atoms, which can be of any type, only dictated by their `kind` field. We can also turn the first two atoms back into their original representation.
Unfortunately, it isn't as simple for the sequence, which can be dynamically typed with heterogenous types at this point.
The `getXXX` functions return `Option[requested type]` as they need to safely provide a way to tell if an atom can be of the requested primitive type. 

### Hold up, this isn't how JavaScript engines work!
Yep, they use coercion. You _could_ implement coercion like this using the exception system, but Bali already handles some of the coercion functions that ECMAScript expects. They'll be covered later.

## Wrapping our Type
Assuming you already have the runtime set up via `newRuntime()`, you can define types before `run()` is called.

```nim
type Person* = object
  name*: string
  age*: uint
  likes*: seq[string]

runtime.registerType(prototype = Person, name = "Person")
runtime.setProperty(Person, "name", str("John Doe"))
runtime.setProperty(Person, "age", integer(24'u))
runtime.setProperty(Person, "likes", sequence(@[
  str("Skating"),
  str("Tennis"),
  str("Programming")
]))
```
Here, we're exposing our `Person` type to the JavaScript environment by specifying what fields it has, and also setting those fields.
Now, you can easily just run this in your JS code:
```js
console.log(Person.name) // Log: John Doe
console.log(Person.age) // Log: 24
console.log(Person.likes) // Log: [Skating, Tennis, Programming]
```

## Modifying our Prototype
Now, what if you wanted to add a function that can be called by every instance of your type?
In order to do that, you need to modify its **prototype**. Assume that we want multiple instances of the previously defined `Person` class to be possible.
We need to define a constructor for it.

```nim
runtime.defineConstructor(
    "Person",
    proc =
      let
        name = runtime.ToString(&runtime.argument(1), required = true, message = "Expected `name` argument at pos 1, got {nargs}")
        age = runtime.ToNumber(&runtime.argument(2), required = true, message = "Expected `age` argument at pos 2, got {nargs}")
      
      let person = Person(name: name, age: age.uint)

      ret person
)
```
Now, we can call `new Person("John Doe", 24)` in JavaScript land and get an instance of the `Person` class!
Let us assume you want a `greet` function for all `Person`(s) that returns "<name> greets you back.". We can implement it like this.
```nim
runtime.definePrototypeFn(
    Person,
    "greet",
    proc(value: JSValue) =
      let 
        name = runtime.ToString(value["name"])
        age = runtime.ToNumber(value["age"])

      echo name & " greets you back."
)
```
Let us break that down, shall we?

- `definePrototypeFn`, as the name suggests, sets up a function for a type's prototype. This prototype is copied to all of the instances of that type, and all of the child classes that derive from this one, and so on and so forth.
- You might be wondering what `value` here is. It's actually the `Person` type we called `ret` on to pass it over to JS-land. It's now in the form of an atom, and unfortunately there's no way to easily turn it back into its original representation, atleast right now.

Now, the following code should work fine:
```js
let john = new Person("John Doe", 23)
let jane = new Person("Jane Doe", 28)

john.greet()
jane.greet()
```

# Supported ECMAScript APIs
Bali supports the following ECMAScript APIs.

## The Math Type
The `Math` type contains the following methods.

### `Math.random`
This function uses the global RNG instance created via [librng](https://github.com/xTrayambak/librng) to generate a float between 0 and 1.
**WARNING**: Do _NOT_ tuse this function in places like cryptography! All of the PRNG algorithms used are highly predictable!

#### Using another RNG algorithm
You can pass the following values as arguments for `--define:BaliRNGAlgorithm`:

- `xoroshiro128`: Xoroshiro128
- `xoroshiro128pp`: Xoroshiro128++
- `xoroshiro128ss`: Xoroshiro128**
- `mersenne_twister`: Mersenne Twister
- `marsaglia`: Marsaglia 69069
- `pcg`: PCG
- `lehmer`: Lehmer64
- `splitmix`: Splitmix64

All of them vary in terms of quality, footprint and speed. Bali defaults to `xoroshiro128` as it provides a nice balance between all of those.

### The rest of the functions
All of the functions apart from `Math.hypot` have been implemented.

## The JSON type
The `JSON` type has been implemented using the [jsony](https://github.com/treeform/jsony) parser. It contains a routine to turn Nim's `JsonNode` structs into `JSValue`(s) on the fly.
It is not very spec-compliant yet, and just exists for my convenience.

### Supported Routines
- `JSON.parse()`
- `JSON.stringify()`

## The URL type
The `URL` type is not part of the JavaScript spec, but we implement it anyways. It uses Ferus' [sanchar](https://github.com/ferus-web/sanchar) parser under the hood.

### Supported Routines
- `new URL()` constructor
- `URL.parse()`

## The BigInt type
The `BigInt` type has been implemented, but the vast majority of its routines have not. It uses the [GNU MP BigNum](https://gmplib.org/) library under the hood.

### Supported Routines
- `new BigInt()` constructor
- `BigInt.prototype.toString()`

## The String type
This is perhaps the most complete implemented-by-Bali ECMAScript type here. It uses [Kaleidoscope](https://github.com/xTrayambak/kaleidoscope) and [simdutf](https://github.com/ferus-web/simdutf) under the hood.

### Supported Routines
- `new String()` constructor
- `String.prototype.indexOf()`
- `String.prototype.concat()`
- `String.prototype.trimStart()` / `String.prototype.trimLeft()`
- `String.prototype.trimEnd()` / `String.prototype.trimRight()`
- `String.prototype.toLowerCase()`
- `String.prototype.toUpperCase()`
- `String.prototype.repeat()`
- `String.fromCharCode()`
- `String.prototype.codePointAt()`
- `String.prototype.substring()`
- `String.prototype.charAt()`
- `String.prototype.at()`

## The Date type
This is yet another well-implemented-by-Bali ECMAScript type. It uses a mixture of [LibICU](https://unicode-org.github.io/icu/userguide/icu/) and internal math-based logic, mostly translated from Ladybird's LibJS.

### Supported Routines
- `new Date()` constructor
- `Date.now()`
- `Date.parse()`
- `Date.prototype.getYear()`
- `Date.prototype.getFullYear()`
- `Date.prototype.toString()`
- `Date.prototype.getDay()`
- `Date.prototype.getDate()`

## The Number type
This is just a boxed representation of a number.

### Supported Routines
- `Number.isFinite()`
- `Number.isNaN()`
- `Number.parseInt()`
- `Number.NaN`
- `Number.EPSILON`
- `Number.prototype.toString()`
- `Number.prototype.valueOf()`

## The Set type
The Set type uses a Sequence atom under the hood, with guards to ensure that no duplicated values can get lodged in on accident.

### Supported Routines
- `new Set()`
- `Set.prototype.toString()`
- `Set.prototype.add()`
- `Set.prototype.size()`
- `Set.prototype.delete()`
- `Set.prototype.has()`
- `Set.prototype.clear()`

# Using Balde
Balde, short for "**Bal**i **de**bugger" is a CLI tool that acts both as a script runner and a REPL.

## Running Scripts
Running a JavaScript source file is as simple as:
```command
$ balde path/to/your/file.js
```

## Flags
Balde supports a few flags for easier debugging.

### `--dump-ast`
This flag lets the runtime evaluate the AST for any errors, but does not allow for its execution. Instead, it prints out the AST instead.
This allows for semantic errors to be thrown out. If you want an immediate AST dump, use `--dump-no-eval`.
```command
$ balde path/to/your/file.js --dump-ast
<AST representation>
```

### `--dump-no-eval`
This flag dumps the parsed representation (or AST) of the provided JavaScript source without any further evaluation. It also includes the parsing errors.
```command
$ balde path/to/your/file.js --dump-no-eval
<AST representation>
```

### `--verbose`
This flag allows all debug logs to be shown, which can be used to diagnose bugs in the engine's multiple phases (tokenization, parsing, bytecode generation and runtime).
Beware that this gets very spammy.
```command
$ balde path/to/your/file.js --verbose
<A boat load of logs>
```

### `--dump-tokens`
This flag dumps all of the tokens of a JavaScript source file.
```command
$ balde path/to/your/file.js --dump-tokens
```

## Using the REPL
**WARNING**: The REPL is still a very unstable feature. It is known to have several bugs.
To run the REPL, simply run Balde with no arguments.

## Experiments
Experiments are unstable Bali features that are locked behind an interpreter flag. In order to use them, you need to use the `--enable-experiments` flag.
`--enable-experiments` expects a syntax like this:
```
--enable-experiments:<experiment1>;<experiment2>
```

### Current Experiments
There are currently no active experimental features.

## Controlling Codegen
Bali exposes some levers to turn on/off some code generation features. This features help Bali emit faster bytecode by skipping certain expensive portions of the provided JS source into code that does roughly the same thing.

If the optimized code does not perform the same behaviour as the unoptimized code, that is a bug. You should probably report it to me after you're 100% sure that it isn't a problem on your part.

### Prelude
Bali exposes three code generation optimizations as of right now:
- Loop Elider
- Loop Allocation Eliminator
- Return-value register scrubbing

### Loop Elision
Say, we have some code like this (this is very stupid, most people don't write code like this):
```js
var i = 0
while (i < 999999)
{
    i++
}
```

Bali can successfully prove that the while-loop only exists to modify the loop's state controller (`i`) in a particular way (increment it in this case)
Bali now knows that there is not a need to:
* Waste storage space by generating code for a loop
* Waste CPU cycles by iterating 999999 times
As such, it can compute the result that will be stored at the end in the `i` variable and turns the code into the rough equivalent of this:
```js
var i = 999999
```
This also works for decrements, as intended.

There are a few cases where the loop elision will correctly fallback and actually generate the loop's code if it detects that a loop does more than mutate its own state.
```js
var i = 0
while (i < 999999)
{
    i++ // This is fine.
    console.log(i) // Woops: we can't elide that loop now!
}
```
Now, it realizes that it has to actually generate the loop. Loop elision makes Bali _really_ fast against other JavaScript engines for very specifically cherry picked benchmarks, but serves next to no real-world usage. Yet.

### Loop Allocation Elision
Say, we have some code like this (this actually happens in a lot of places):
```js
while (true)
{
  let x = "Programming se me utsahit hota hun. Me vyavsaik programmer hun, aur tum ise idhar dekh sakte ho. Ye mera kaushal he."
  console.log(x)
}
```
AFAIK, other JavaScript engines like V8 and SpiderMonkey have an internal string interning "cache" to prevent allocating the same string again and again.
Bali takes a different approach, because why not?

Before a loop is about to be generated, Bali runs an optimization pass over the body to check if any allocations can be moved outside the loop's body.
The aforementioned code sample, hence, would be converted into this:
```js
let x = "Programming se me utsahit hota hun. Me vyavsaik programmer hun, aur tum ise idhar dekh sakte ho. Ye mera kaushal he."

while (true)
{
  console.log(x)
}
```

This prevents unnecessary allocations. Yay.

### Return-Value Register Scrubber
This optimization essentially allows the engine to emit the `ZRETV` instruction. This instruction clears the return-value register, which allows the garbage collector to quickly clear up the memory it might occupy. This makes some badly written code no longer result in an OOM. It, however, like most of Bali, is not battle tested and as such, might result in undefined behaviour. It is disabled by default.

### Disabling Optimizations
If you don't want the bytecode generator to spend time optimizing code (you're 100% sure you've written very neat code that will always make your CPU happy or something) or the bytecode generator ends up performing optimization incorrectly (rare, but if it occurs, please file a bug report), then you can disable codegen optimizations.

#### Disabling Optimizations in Balde
Balde exposes the following three flags to control optimizations:
* --disable-loop-elision
* --disable-loop-allocation-elim
* --aggressively-free-retvals
* --disable-jit

#### Disabling Optimizations in Nim code
When instantiating the `Runtime`, you can pass an `InterpreterOpts` struct containing a `CodegenOpts` struct.
```nim
var runtime = newRuntime(
  fileName, ast, 
  InterpreterOpts(
    codegen: CodegenOpts(
      elideLoops: false,
      loopAllocationEliminator: false,
      aggressivelyFreeRetvals: false,
      jitCompiler: false
    )
  )
)
```

# Using the Native Interface
## A small example
Bali exposes a pretty neat two-way interface for native code written in Nim to interact with JavaScript, and vice versa.
Here's a short example. Here's a brief summary of what it does:
- The JavaScript code has a function called "shoutify" which takes in an argument and returns an all-upper-case version of it.
- The Nim code has a function called "greet" which takes in an argument and prints "Hi there, <argument>" to stdout.
- The JS code firstly calls the native greet function, passing "tray" as an argument. As expected, "Hi there, tray" gets printed to stdout.
- After the execution is done, the Nim code tries finding a reference to the "shoutify" function in the global scope.
- Then, it calls this function from Nim-land with the argument "tray".
- The JS function turns this argument all into uppercase ("TRAY") and returns it.
- Then, the Nim-land code gets it back and prints it out.
```nim
import pkg/bali/grammar/prelude
import pkg/bali/runtime/prelude

proc main =
  let parser = newParser(
    """
let greeting = greet("tray") // Here, we're calling a native function written in Nim
console.log(greeting)

function shoutify(name)
{
  // Make a name seem like it's been SHOUTED OUT.
  // This is called by native code.
  var x = new String(name);
  var y = x.toUpperCase() // Fun fact: `toUpperCase()` is native code. So here, we have native code calling interpreted code, which in turn calls more native code. :^)

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

  runtime.run() # Execute what we have so far.
  
  let fn = runtime.get("shoutify") # Get the `shoutify` value reference in the global scope
  if !fn:
    return

  let retval = runtime.call(&fn, str("tray")) # Call the `shoutify` function in bytecode. Pass it the arguments it expects.
  echo "I AM SHOUTING YOUR NAME AT YOU, " & runtime.ToString(retval) # Take its return value and print it out.
```
