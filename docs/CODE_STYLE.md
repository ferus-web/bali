# The Bali Code Style
This document aims to be a vast corpus of rules that a contributor must follow. These range from recommendations to enforcements. They also range from simply code aesthetics to real semantic changes.

Some code in Bali is currently a violation of the rules here. Feel free to send pull requests to fix them.

## General Rules
Each commit made to Bali is passed through [Nimalyzer](https://github.com/thindil/nimalyzer), a static analyzer for Nim. Make sure that none of your code messes with it and/or makes its job harder.

### Minimize the usage of templates to places where it makes sense.
Don't abuse templates. They dilute the codebase with unfollowable stack traces and can also worsen compilation times. \
Whenever you're about to use a template, think to yourself: "Would this be better off as a function?"

Here's the cases where it'd absolutely be better off as a function:
- It isn't capturing anything that would otherwise trigger Nim's memory safety guardrails if the function were to be inlined.
- Turning it into a function would make things more verbose than they need to be, hindering code readability. (A good example of this is the `error` template in the parser.)

Try to avoid templates in the core runtime (the Mirage-Pulsar interpreter), as it makes auditing the code much harder.

### Mark all unreachable cases as such.
The `unreachable` template, defined at `bali/internal/sugar`, should be used to mark code branches that are assumed to be unreachable as such, if the compiler cannot prove that they truly are unreachable. It can also be used as a temporary safe-crash mechanism for features that have not been fully implemented, but it is preferrable to throw a proper error in such cases.

### Defects vs Exceptions
In Nim, defects are unrecoverable errors whilst exceptions are recoverable errors. **Treat them as such.**

```nim
type
  CriticalCodegenBug* = object of ValueError ## We should be able to recover from this, hence the exception...
  OutOfBoundsTokenRead* = object of Defect   ## Something's went terribly wrong, so it's best we just let the program be killed at this point
```

### Use `result` sparingly.
The use of the `result` value makes code ambiguous. Much like the Status IM guide on writing clean Nim, the Bali Code Style recommends you to keep usage of `result` to a bare minimum. \
Only use `result` when you want to set the return value and perform an action afterwards.

### Try to specify the lengths of allocations when possible.
If calculating the length of an allocated buffer like a sequence or string is possible without much hotchpotch and mental gymnastics, do it. \
Remember, `mmap(2)` does not take a single CPU cycle.

A good example of this would be the following code example:
```nim
proc convertUint8SeqToUint16*(data: seq[uint8]): seq[uint16] =
  var converted = newSeq[uint8](data.len) # Preallocate the entire size that we need.
  
  # Good approach
  for i, byt in data:
    converted[i] = uint16(byt)

  # Bad approach
  for byt in data:
    converted &= uint16(byt) # Every time we need extra memory to store the new uint16s, we're allocating more memory.

  move(converted)
```

### Use move semantic markers when needed.
Self-explanatory. This adds an extra layer of clarity to the code, even if not necessary.

```nim
proc somethingSomething: string =
  var x = "hello world"
  x &= "blehhh"

  result = ensureMove(x) # We're indicating that we no longer need x. Any accesses to x beyond this point will generate a compile-time error.
  echo x   # Compile-time error!
```

## Rules for the grammar module (Tokenizer / Parser)
### Do not interact with the JavaScript heap.
Do _**NOT**_, under any circumstances, call any of Bali's JavaScript heap management functions (or functions that indirectly call them) in the grammar module!

The following functions are guaranteed to allocate on the JavaScript heap:
- `str()`
- `uinteger()`
- `integer()`
- `floating()`
- `sequence()`
- `undefined()`
- `obj()`
- `bigint()`
- `ident()`

The following functions are their stack-affine, safe-to-use counterparts:
- `stackStr()`
- `stackUinteger()`
- `stackInteger()`
- `stackFloating()`
- `stackSequence()`
- `stackUndefined()`
- `stackIdent()`

`BigInt` and `Object` are not covered, as they are designed to always be allocated on the heap. Use other ways to represent them in the AST.

Bali is designed in a way that each component can be used individually, so that, say, a JavaScript LSP written in Nim utilizing Bali's parser needn't initialize the JavaScript heap and the unnecessary overhead, complexity, undeterministicness and safety problems that come along with it.
