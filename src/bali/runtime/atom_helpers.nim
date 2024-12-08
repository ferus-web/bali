## Atom functions

import std/tables
import bali/grammar/statement
import mirage/atom

func isUndefined*(atom: MAtom): bool {.inline.} =
  atom.kind == Object and atom.objFields.len < 1

func isObject*(atom: MAtom): bool {.inline.} =
  atom.kind == Object

func isNull*(atom: MAtom): bool {.inline.} =
  atom.kind == Null

proc `[]`*(atom: MAtom, name: string): MAtom {.inline.} =
  if atom.kind != Object:
    raise newException(ValueError, $atom.kind & " does not have field access methods")

  atom.objValues[atom.objFields[name]]

proc `[]=`*(atom: var MAtom, name: string, value: sink MAtom) {.inline.} =
  if atom.kind != Object:
    raise newException(ValueError, $atom.kind & " does not have field access methods")

  if not atom.objFields.contains(name):
    atom.objValues &= move(value)
    atom.objFields[name] = atom.objValues.len - 1
  else:
    atom.objValues[atom.objFields[name]] = move(value)

{.push inline.}
func wrap*(val: int | uint | string | float): MAtom =
  when val is int:
    return integer(val)

  when val is uint:
    return uinteger(val)

  when val is string:
    return str(val)

  when val is float:
    return floating(val)

func wrap*[T: not MAtom](val: openArray[T]): MAtom =
  var vec = sequence(newSeq[MAtom](0))

  for v in val:
    vec.sequence &= v.wrap()

  vec

func wrap*[T: object](obj: T): MAtom =
  var mObj = atom.obj()

  for name, field in obj.fieldPairs:
    mObj[name] = field.wrap()

  mObj

func wrap*(val: seq[MAtom]): MAtom =
  sequence(val)

proc `[]=`*[T: not MAtom](atom: var MAtom, name: string, value: T) {.inline.} =
  atom[name] = wrap(value)
{.pop.}

func undefined*(): MAtom {.inline.} =
  obj()

