## Atom functions

import std/tables
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
    atom.objFields[name] = atom.objValues.len
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

func wrap*(val: seq[MAtom]): MAtom =
  sequence(val)
{.pop.}

func undefined*(): MAtom {.inline.} =
  obj()
