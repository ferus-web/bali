import std/[tables]
import bali/runtime/[atom_obj_variant, types]

type Prototype* = object
  fields*: Table[string, AtomOrFunction[NativeFunction]]

func initPrototype*(fields: Table[string, AtomOrFunction]): Prototype {.inline.} =
  Prototype(fields: fields)
