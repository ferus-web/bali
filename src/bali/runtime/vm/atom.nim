## MAtoms are a dynamic-ish type used by all of Mirage to pass around values from the emitter to the interpreter, 
## to the calling Nim code itself.

import std/[tables, hashes, options]
import pkg/[shakar, gmp]
import ./heap/boehm

{.experimental: "strictDefs".}

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
    Undefined = 12

  AtomOverflowError* = object of CatchableError
  SequenceError* = object of CatchableError

  AtomMode* {.pure.} = enum
    Default = 0
    ReadOnly = 1
    WriteOnly = 2

  MAtom* = object
    case kind*: MAtomKind
    of String:
      str*: string
    of Ident:
      ident*: string
    of Integer:
      integer*: int
    of Sequence:
      sequence*: seq[MAtom]
      lCap*: Option[int]
      lHomogenous*: bool = false
    of UnsignedInt:
      uinteger*: uint
    of Boolean:
      state*: bool
    of Object:
      objFields*: Table[string, int]
      objValues*: seq[JSValue]
    of Undefined: discard
    of Float:
      floatVal*: float64
    of BigInteger:
      bigint*: BigInt
    of BytecodeCallable:
      clauseName*: string
    of NativeCallable:
      fn*: proc()
    of Null: discard

  JSValue* = ptr MAtom

proc hash*(atom: MAtom): Hash =
  var h: Hash = 0

  h = h !& atom.kind.int

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

proc hash*(value: ptr MAtom): Hash {.inline.} =
  hash(value[])

proc crush*(
    atom: MAtom | JSValue, id: string = "", quote: bool = true
): string {.inline.} =
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
  of Undefined:
    return "Undefined"

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

proc getStr*(atom: MAtom | JSValue): Option[string] {.inline.} =
  if atom.kind == String:
    return some(atom.str)

proc getInt*(atom: MAtom | JSValue): Option[int] {.inline.} =
  if atom.kind == Integer:
    return some(atom.integer)

proc getUint*(atom: MAtom | JSValue): Option[uint] {.inline.} =
  if atom.kind == UnsignedInt:
    return some atom.uinteger

proc getIntOrUint*(atom: MAtom | JSValue): Option[uint] {.inline.} =
  if atom.kind == Integer:
    return some(uint(&atom.getInt()))
  elif atom.kind == UnsignedInt:
    return atom.getUint()

proc getBool*(atom: MAtom | JSValue): Option[bool] {.inline.} =
  if atom.kind == Boolean:
    return some atom.state

proc getIdent*(atom: MAtom | JSValue): Option[string] {.inline.} =
  if atom.kind == Ident:
    return some atom.ident

proc getFloat*(atom: MAtom | JSValue): Option[float64] {.cdecl.} =
  if atom.kind == Float:
    return some atom.floatVal

proc getNumeric*(atom: MAtom | JSValue): Option[float64] {.inline.} =
  if atom.kind == Integer:
    return some(float(&atom.getInt()))
  elif atom.kind == UnsignedInt:
    return some(float(&atom.getFloat()))
  elif atom.kind == Float:
    return some(&atom.getFloat())

proc getSequence*(atom: MAtom | JSValue): Option[seq[MAtom]] {.inline.} =
  if atom.kind == Sequence:
    return some(atom.sequence)

proc getNativeCallable*(atom: MAtom | JSValue): Option[proc()] {.inline.} =
  if atom.kind == NativeCallable:
    return some(atom.fn)

proc newJSValue*(kind: MAtomKind): JSValue =
  ## Allocate a new `JSValue` using Bali's garbage collector.
  ## A `JSValue` is a pointer to an atom.

  var mem = cast[ptr MAtom](baliAlloc(sizeof(MAtom)))

  {.cast(uncheckedAssign).}:
    mem[].kind = kind

  ensureMove(mem)

proc atomToJSValue*(atom: MAtom): JSValue =
  var value = newJSValue(atom.kind)
  case atom.kind
  of Null, Undefined, Ident:
    discard
  of String:
    value.str = atom.str
  of Integer:
    value.integer = atom.integer
  of Sequence:
    value.sequence = atom.sequence
    value.lCap = atom.lCap
    value.lHomogenous = atom.lHomogenous
  of UnsignedInt:
    value.uinteger = atom.uinteger
  of Boolean:
    value.state = atom.state
  of Object:
    value.objFields = atom.objFields
    value.objValues = atom.objValues
      # TODO: this might be dangerous. perhaps we should run `atomToJSValue` on all the objvalues too.
  of Float:
    value.floatval = atom.floatVal
  of BigInteger:
    value.bigint = atom.bigint
  of BytecodeCallable:
    value.clauseName = atom.clauseName
  of NativeCallable:
    value.fn = atom.fn

  move(value)

proc str*(s: string, inRuntime: bool = false): JSValue {.inline, cdecl.} =
  var mem = newJSValue(String)
  mem.str = s

  ensureMove(mem)

func stackStr*(s: string): MAtom =
  ## Allocate a String atom on the stack.
  ## This is used by the parser.
  MAtom(kind: String, str: s)

proc ident*(ident: string): JSValue {.inline, cdecl.} =
  var mem = newJSValue(Ident)
  mem.ident = ident

  ensureMove(mem)

func stackIdent*(i: string): MAtom =
  ## Allocate a Ident atom on the stack.
  ## This is used by the parser.
  MAtom(kind: Ident, ident: i)

proc integer*(i: int, inRuntime: bool = false): JSValue {.inline, cdecl.} =
  var mem = newJSValue(Integer)
  mem.integer = i

  ensureMove(mem)

func stackInteger*(i: int): MAtom =
  ## Allocate a Integer atom on the stack.
  ## This is used by the parser.
  MAtom(kind: Integer, integer: i)

proc uinteger*(u: uint, inRuntime: bool = false): JSValue {.inline, cdecl.} =
  var mem = newJSValue(UnsignedInt)
  mem.uinteger = u

  ensureMove(mem)

func stackUinteger*(u: uint): MAtom =
  ## Allocate a UnsignedInt atom on the stack.
  ## This is used by the parser.
  MAtom(kind: UnsignedInt, uinteger: u)

proc boolean*(b: bool, inRuntime: bool = false): JSValue {.inline, cdecl.} =
  var mem = newJSValue(Boolean)
  mem.state = b

  ensureMove(mem)

proc nativeCallable*(fn: proc()): JSValue {.inline, cdecl.} =
  var mem = newJSValue(NativeCallable)
  mem.fn = fn

  ensureMove(mem)

func stackBoolean*(b: bool): MAtom =
  MAtom(kind: Boolean, state: b)

proc bytecodeCallable*(clause: string): JSValue {.cdecl.} =
  var mem = newJSValue(BytecodeCallable)
  mem.clauseName = clause

  ensureMove(mem)

func stackBytecodeCallable*(clause: string): MAtom =
  MAtom(kind: BytecodeCallable, clauseName: clause)

proc getBytecodeClause*(atom: JSValue): Option[string] =
  if atom.kind == BytecodeCallable:
    return some(atom.clauseName)

  none(string)

proc floating*(value: float64): JSValue {.cdecl.} =
  var mem = newJSValue(Float)
  mem.floatVal = value

  mem

func stackFloating*(value: float64): MAtom =
  MAtom(kind: Float, floatVal: value)

proc undefined*(): JSValue {.inline, cdecl.} =
  newJSValue(Undefined)

func stackUndefined*(): MAtom =
  MAtom(kind: Undefined)

proc null*(inRuntime: bool = false): JSValue {.inline, cdecl.} =
  newJSValue(Null)

func stackNull*(): MAtom =
  MAtom(kind: Null)

proc sequence*(s: seq[MAtom]): JSValue {.inline, cdecl.} =
  var mem = newJSValue(Sequence)
  mem.sequence = s

  ensureMove(mem)

func stackSequence*(s: seq[MAtom]): MAtom {.inline.} =
  MAtom(kind: Sequence, sequence: s)

proc bigint*(value: SomeSignedInt | string): JSValue {.inline, cdecl.} =
  var mem = newJSValue(BigInteger)
  mem.bigint = initBigInt(value)

  ensureMove(mem)

proc obj*(): JSValue {.inline, cdecl.} =
  var mem = newJSValue(Object)
  mem.objFields = initTable[string, int]()
  mem.objValues = newSeq[JSValue]()

  ensureMove(mem)
