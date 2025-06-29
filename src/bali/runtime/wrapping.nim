## "Wrapping" convenience functions that can turn various types into their
## Bali JavaScript value representations.
## **NOTE**: All of the functions below are allocating memory on the Bali GC heap and can be nil in the case of an OOM!
import std/[tables]
import
  bali/runtime/vm/atom,
  bali/runtime/atom_helpers,
  bali/stdlib/types/std_string_type,
  bali/runtime/types,
  bali/internal/sugar

proc wrap*(runtime: Runtime, val: SomeInteger | string | float | bool): JSValue =
  when val is SomeInteger:
    return integer(val.int)

  when val is bool:
    return boolean(val)

  when val is string:
    return runtime.newJSString(val)

  when val is float:
    return floating(val)

proc wrap*[T: not JSValue](runtime: Runtime, val: openArray[T]): JSValue =
  var vec = sequence(newSeq[MAtom](0))

  for v in val:
    vec.sequence &= v.wrap()

  vec

proc wrap*[V: JSValue | MAtom](runtime: Runtime, atom: V): V {.inline.} =
  atom

proc wrap*[A, B](runtime: Runtime, val: Table[A, B]): JSValue =
  var atom = obj()
  for k, v in val:
    atom[$k] = wrap(v)

  atom

proc wrap*[T: object](runtime: Runtime, obj: T): JSValue =
  var mObj = atom.obj()

  for name, field in obj.fieldPairs:
    mObj[name] = field.wrap()

  mObj

proc wrap*(runtime: Runtime, val: seq[JSValue]): JSValue =
  var atoms = newSeq[MAtom](val.len)

  for i, value in val:
    atoms[i] = val[i][]

  sequence(ensureMove(atoms))

template `[]`*[T: not JSValue](atom: JSValue, name: string, value: T) =
  atom[name] = runtime.wrap(value)

proc tag*[T](runtime: Runtime, atom: JSValue, tag: string, value: T) =
  atom['@' & tag] = runtime.wrap(atom)
