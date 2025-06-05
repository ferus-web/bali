## Atom functions

import std/[options, tables]
import bali/runtime/vm/atom

{.push warning[UnreachableCode]: off, inline.}

func isUndefined*(atom: MAtom | JSValue): bool =
  atom.kind == Undefined

func isObject*(atom: JSValue): bool =
  atom.kind == Object

func isNull*(atom: JSValue): bool =
  atom.kind == Null

func isNumber*(atom: JSValue): bool =
  atom.kind == UnsignedInt or atom.kind == Integer or atom.kind == Float

func isBigInt*(atom: JSValue): bool =
  atom.kind == BigInteger

proc `[]`*(atom: JSValue, name: string): JSValue =
  if atom.kind != Object:
    raise newException(ValueError, $atom.kind & " does not have field access methods")

  atom.objValues[atom.objFields[name]]

proc `[]=`*(atom: JSValue, name: string, value: sink JSValue) =
  if atom.kind != Object:
    raise newException(ValueError, $atom.kind & " does not have field access methods")

  if not atom.objFields.contains(name):
    atom.objValues &= ensureMove(value)
    atom.objFields[name] = atom.objValues.len - 1
  else:
    atom.objValues[atom.objFields[name]] = ensureMove(value)

proc createField*(atom: JSValue, field: string) =
  atom[field] = undefined()

proc contains*(atom: JSValue, name: string): bool =
  atom.objFields.contains(name)

proc tagged*(atom: JSValue, tag: string): Option[JSValue] =
  if atom.contains('@' & tag):
    return some atom['@' & tag]

proc tag*(atom: JSValue, tag: string, value: JSValue) =
  atom['@' & tag] = value

{.pop.}
