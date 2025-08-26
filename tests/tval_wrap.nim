import std/tables
import pkg/bali/runtime/prelude
import pkg/bali/runtime/wrapping
import pretty

var runtime = newRuntime("tval_wrap.js")

print wrap(runtime, 3)
print wrap(runtime, ":^)")
print wrap(runtime, @[3, 4, 5])
print wrap(runtime, @[runtime.wrap(3), runtime.wrap ":^)", runtime.wrap @[3, 4, 5]])

type
  NestedType* = object
    hi*: string = "Hi there!"

  EpicClass* = object
    name*: string = "A very epic class"
    nested*: NestedType

print wrap(runtime, EpicClass())
