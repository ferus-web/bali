## MAtoms are a dynamic-ish type used by all of Mirage to pass around values from the emitter to the interpreter, 
## to the calling Nim code itself.
##

import std/[strutils, tables, hashes, options]
import pkg/gmp
import ./heap/boehm
import ./utils

type
  MAtomKind* {.size: sizeof(uint8).} = enum
    Null = 0
    String = 1
    Integer = 2
    Sequence = 3
    Ident = 4
    UnsignedInt = 5
    Boolean = 6
    Object = 7
    Float = 8
    BigInteger = 9
    BytecodeCallable = 10
    NativeCallable = 11

  AtomOverflowError* = object of CatchableError
  SequenceError* = object of CatchableError

  MAtom* = object
    case kind*: MAtomKind
    of String:
      str*: string
    of Ident:
      ident*: string
    of Integer:
      integer*: int
    of Sequence:
      sequence*: seq[JSValue]
      lCap*: Option[int]
      lHomogenous*: bool = false
    of UnsignedInt:
      uinteger*: uint
    of Boolean:
      state*: bool
    of Object:
      objFields*: Table[string, int]
      objValues*: seq[JSValue]
    of Null: discard
    of Float:
      floatVal*: float64
    of BigInteger:
      bigint*: BigInt
    of BytecodeCallable:
      clauseName*: string
    of NativeCallable:
      fn*: proc()

  JSValue* = ptr MAtom

#[ proc `=destroy`*(dest: MAtom) =
  case dest.kind
  of String:
    `=destroy`(dest.str)
  of Ident:
    `=destroy`(dest.ident)
  of Sequence:
    for atom in dest.sequence:
      `=destroy`(atom)
  of Object:
    for atom in dest.objValues:
      `=destroy`(atom)
  else:
    discard
]#

#[
proc `=copy`*(dest: var MAtom, src: MAtom) =
  `=destroy`(dest)
  wasMoved dest

  dest.kind = src.kind
  case src.kind
  of String:
    dest.str = cast[string](alloc(sizeof src.str))
    for i, elem in 0..<dest.str.len:
      dest.str[i] = elem
  of Integer:
    var ival = cast[ptr int](alloc(sizeof int))
    ival[] = src.integer

    dest.integer = ival
  of Sequence:
    dest.sequence = cast[seq[MAtom]](alloc(sizeof src.sequence))

    for i, elem in src.sequence:
      dest.sequence[i] = elem
  of Ref:
    var sval = cast[string](alloc(sizeof str.link))
    
    for i, elem in src.link:
      sval[i] = src.link[i]

    dest.reference = deepCopy(src.reference)
    dest.link = sval
  of Null: discard
]#

proc hash*(atom: MAtom): Hash =
  var h: Hash = 0

  case atom.kind
  of String:
    h = h !& atom.str.hash()
  of Ident:
    h = h !& atom.ident.hash()
  of Integer:
    h = h !& atom.integer.hash()
  of Object:
    for k, v in atom.objFields:
      h = h !& k.hash()
      h = h !& v.hash()

    h = h !& atom.objValues.hash()
  of Sequence:
    h = h !& atom.sequence.hash()
    h = h !& atom.lCap.hash()
    h = h !& atom.lHomogenous.hash()
  of UnsignedInt:
    h = h !& atom.uinteger.hash()
  of Boolean:
    h = h !& atom.state.hash()
  of Float:
    h = h !& atom.floatVal.hash()
  else:
    discard

  !$h

proc hash*(value: ptr MAtom): Hash {.inline.} = hash(value[])

proc crush*(atom: JSValue, id: string = "", quote: bool = true): string {.inline.} =
  case atom.kind
  of String:
    if quote:
      result &= '"' & atom.str & '"'
    else:
      result &= atom.str
  of Integer:
    result &= $atom.integer
  of UnsignedInt:
    result &= $atom.uinteger
  of Ident:
    result &= atom.ident
  of Boolean:
    result &= $atom.state
  of Sequence:
    result &= '[' # sequence guard open

    for i, item in atom.sequence:
      result &= item.crush(id & "_mseq_" & $i)

      if i + 1 < atom.sequence.len:
        result &= ", "

    result &= ']' # sequence guard close
  of Float:
    result &= $atom.floatVal
  of Null:
    return "NULL"
  of BigInteger:
    return $atom.bigint
  of Object:
    return "Object"
  of BytecodeCallable:
    return "Callable [" & atom.clauseName & ']'
  of NativeCallable:
    return "Native Callable"

proc setCap*(atom: var MAtom, cap: int) {.inline.} =
  case atom.kind
  of Sequence:
    atom.lCap = some(cap)
  else:
    raise newException(
      ValueError, "Attempt to set cap on a non-container atom: " & $atom.kind
    )

proc getCap*(atom: var MAtom): int {.inline.} =
  case atom.kind
  of Sequence:
    if *atom.lCap:
      return &atom.lCap
  else:
    raise newException(
      ValueError, "Attempt to get the cap of a non-container atom: " & $atom.kind
    )

  high(int)

proc markHomogenous*(atom: var MAtom) {.inline.} =
  if atom.kind == Sequence:
    atom.lHomogenous = true
  else:
    raise newException(
      ValueError,
      "Attempt to mark a " & $atom.kind &
        " as a homogenous data type. Only List(s) can be marked as such.",
    )

proc getStr*(atom: JSValue): Option[string] {.inline.} =
  if atom.kind == String:
    return some(atom.str)

proc getInt*(atom: JSValue): Option[int] {.inline.} =
  if atom.kind == Integer:
    return some(atom.integer)

proc getBool*(atom: JSValue): Option[bool] {.inline.} =
  if atom.kind == Boolean:
    return some atom.state

proc getIdent*(atom: JSValue): Option[string] {.inline.} =
  if atom.kind == Ident:
    return some atom.ident

proc getUint*(atom: JSValue): Option[uint] {.inline.} =
  if atom.kind == UnsignedInt:
    return some atom.uinteger

proc getFloat*(atom: JSValue): Option[float64] {.inline.} =
  if atom.kind == Float:
    return some atom.floatVal

proc getSequence*(atom: JSValue): Option[seq[JSValue]] {.inline.} =
  if atom.kind == Sequence:
    return some(atom.sequence)

proc newJSValue*(kind: MAtomKind): JSValue =
  ## Allocate a new `JSValue` using Bali's garbage collector.
  ## A `JSValue` is a pointer to an atom.
  var mem = cast[ptr MAtom](baliAlloc(sizeof(MAtom)))

  {.cast(uncheckedAssign).}:
    mem[].kind = kind

  ensureMove(mem)

proc str*(s: string, inRuntime: bool = false): JSValue {.inline.} =
  var mem = newJSValue(String)
  mem.str = s
    
  ensureMove(mem)

proc ident*(ident: string, inRuntime: bool = false): JSValue {.inline.} =
  var mem = newJSValue(Ident)
  mem.ident = ident
    
  ensureMove(mem)

proc integer*(i: int, inRuntime: bool = false): JSValue =
  var mem = newJSValue(Integer)
  mem.integer = i

  ensureMove(mem)

proc uinteger*(u: uint, inRuntime: bool = false): JSValue =
  var mem = newJSValue(UnsignedINt)
  mem.uinteger = u

  ensureMove(mem)

proc boolean*(b: bool, inRuntime: bool = false): JSValue =
  var mem = newJSValue(Boolean)
  mem.state = b

  ensureMove(mem)

proc bytecodeCallable*(clause: string, inRuntime: bool = false): JSValue =
  var mem = newJSValue(BytecodeCallable)
  mem.clauseName = clause

  ensureMove(mem)

proc getBytecodeClause*(atom: JSValue): Option[string] =
  if atom.kind == BytecodeCallable:
    return some(atom.clauseName)

proc floating*(value: float64, inRuntime: bool = false): JSValue =
  var mem = newJSValue(Float)
  mem.floatVal = value

  mem

proc boolean*(s: string, inRuntime: bool = false): Option[JSValue] =
  try:
    return some(boolean(parseBool(s)))
  except ValueError:
    discard

proc null*(inRuntime: bool = false): JSValue {.inline.} =
  newJSValue(Null)

proc sequence*(s: seq[JSValue], inRuntime: bool = false): JSValue {.inline.} =
  if inRuntime:
    var mem = newJSValue(Sequence)
    mem.sequence = s

    ensureMove(mem)
  else:
    var mem = MAtom(kind: Sequence, sequence: s)
    mem.addr

proc bigint*(value: SomeSignedInt | string): JSValue =
  var mem = newJSValue(BigInteger)
  mem.bigint = initBigInt(value)
  
  ensureMove(mem)

proc obj*(): JSValue {.inline.} =
  var mem = newJSValue(Object)
  mem.objFields = initTable[string, int]()
  mem.objValues = newSeq[JSValue]()
  
  ensureMove(mem)
