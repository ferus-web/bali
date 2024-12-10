import std/tables
import bali/runtime/atom_helpers
import pretty

print wrap(3)
print wrap(":^)")
print wrap(@[3, 4, 5])
print wrap(@[3.wrap, ":^)".wrap, @[3, 4, 5].wrap])

type
  NestedType* = object
    hi*: string = "Hi there!"

  EpicClass* = object
    name*: string = "A very epic class"
    nested*: NestedType

print wrap(EpicClass())
