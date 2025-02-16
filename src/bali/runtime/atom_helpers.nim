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

proc `[]=`*(atom: var JSValue, name: string, value: sink JSValue) =
  if atom.kind != Object:
    raise newException(ValueError, $atom.kind & " does not have field access methods")

  if not atom.objFields.contains(name):
    atom.objValues &= move(value)
    atom.objFields[name] = atom.objValues.len - 1
  else:
    atom.objValues[atom.objFields[name]] = move(value)

proc contains*(atom: JSValue, name: string): bool =
  atom.objFields.contains(name)

proc tagged*(atom: JSValue, tag: string): Option[JSValue] =
  if atom.contains('@' & tag):
    return some atom['@' & tag]

proc wrap*(val: SomeSignedInt | SomeUnsignedInt | string | float | bool): JSValue =
  when val is SomeSignedInt:
    return integer(val.int)

  when val is bool:
    return boolean(val)

  when val is SomeUnsignedInt:
    return uinteger(val.uint)

  when val is string:
    return str(val, inRuntime = true)

  when val is float:
    return floating(val)

proc wrap*[T: not JSValue](val: openArray[T]): JSValue =
  var vec = sequence(newSeq[JSValue](0))

  for v in val:
    vec.sequence &= v.wrap()

  vec

proc wrap*(atom: JSValue): JSValue {.inline.} =
  atom

proc wrap*[A, B](val: Table[A, B]): JSValue =
  var atom = obj()
  for k, v in val:
    atom[$k] = wrap(v)

  atom

proc wrap*[T: object](obj: T): JSValue =
  var mObj = atom.obj()

  for name, field in obj.fieldPairs:
    mObj[name] = field.wrap()

  mObj

proc wrap*(val: seq[JSValue]): JSValue =
  sequence(val)

proc `[]=`*[T: not JSValue](atom: var JSValue, name: string, value: T) =
  atom[name] = wrap(value)

proc tag*[T](atom: var JSValue, tag: string, value: T) =
  atom['@' & tag] = value.wrap()

{.pop.}
