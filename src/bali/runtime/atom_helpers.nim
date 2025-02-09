## Atom functions

import std/[options, tables]
import bali/runtime/vm/atom

{.push warning[UnreachableCode]: off, inline.}

func isUndefined*(atom: MAtom): bool =
  atom.kind == Object and atom.objFields.len < 1

func isObject*(atom: MAtom): bool =
  atom.kind == Object

func isNull*(atom: MAtom): bool =
  atom.kind == Null

func isNumber*(atom: MAtom): bool =
  atom.kind == UnsignedInt or atom.kind == Integer or atom.kind == Float

func isBigInt*(atom: MAtom): bool =
  atom.kind == BigInteger

proc `[]`*(atom: MAtom, name: string): MAtom =
  if atom.kind != Object:
    raise newException(ValueError, $atom.kind & " does not have field access methods")

  atom.objValues[atom.objFields[name]]

proc `[]=`*(atom: var MAtom, name: string, value: sink MAtom) =
  if atom.kind != Object:
    raise newException(ValueError, $atom.kind & " does not have field access methods")

  if not atom.objFields.contains(name):
    atom.objValues &= move(value)
    atom.objFields[name] = atom.objValues.len - 1
  else:
    atom.objValues[atom.objFields[name]] = move(value)

proc contains*(atom: MAtom, name: string): bool =
  atom.objFields.contains(name)

proc tagged*(atom: MAtom, tag: string): Option[MAtom] =
  if atom.contains('@' & tag):
    return some atom['@' & tag]

func wrap*(val: SomeSignedInt | SomeUnsignedInt | string | float | bool): MAtom =
  when val is SomeSignedInt:
    return integer(val.int)

  when val is bool:
    return boolean(val)

  when val is SomeUnsignedInt:
    return uinteger(val.uint)

  when val is string:
    return str(val)

  when val is float:
    return floating(val)

func wrap*[T: not MAtom](val: openArray[T]): MAtom =
  var vec = sequence(newSeq[MAtom](0))

  for v in val:
    vec.sequence &= v.wrap()

  vec

func wrap*(atom: MAtom): MAtom {.inline.} =
  atom

func wrap*[A, B](val: Table[A, B]): MAtom =
  var atom = obj()
  for k, v in val:
    atom[$k] = wrap(v)

  atom

func wrap*[T: object](obj: T): MAtom =
  var mObj = atom.obj()

  for name, field in obj.fieldPairs:
    mObj[name] = field.wrap()

  mObj

func wrap*(val: seq[MAtom]): MAtom =
  sequence(val)

proc `[]=`*[T: not MAtom](atom: var MAtom, name: string, value: T) =
  atom[name] = wrap(value)

proc tag*[T](atom: var MAtom, tag: string, value: T) =
  atom['@' & tag] = value.wrap()

func undefined*(): MAtom =
  obj()

{.pop.}
