import std/options
import pkg/bali/runtime/atom_type

type
  Registers* = object
    retVal*: Option[JSValue]
    callArgs*: seq[JSValue]
    error*: Option[JSValue]
