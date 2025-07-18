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
    Boolean = 5
    Object = 6
    Float = 7
    BigInteger = 8
    BytecodeCallable = 9
    NativeCallable = 10
    Undefined = 11

  AtomOverflowError* = object of CatchableError
  SequenceError* = object of CatchableError

  AtomMode* {.pure, size: sizeof(uint8).} = enum
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

proc getStr*(atom: MAtom | JSValue): Option[string] {.inline.} =
  if atom.kind == String:
    return some(atom.str)

  none(string)

proc getInt*(atom: MAtom | JSValue): Option[int] {.inline.} =
  if atom.kind == Integer:
    return some(atom.integer)

  none(int)

proc getBool*(atom: MAtom | JSValue): Option[bool] {.inline.} =
  if atom.kind == Boolean:
    return some atom.state

  none(bool)

proc getIdent*(atom: MAtom | JSValue): Option[string] {.inline.} =
  if atom.kind == Ident:
    return some atom.ident

  none(string)

proc getFloat*(atom: MAtom | JSValue): Option[float64] {.cdecl.} =
  if atom.kind == Float:
    return some atom.floatVal

  none(float64)

proc getNumeric*(atom: MAtom | JSValue): Option[float64] {.inline.} =
  if atom.kind == Integer:
    return some(float(&atom.getInt()))
  elif atom.kind == Float:
    return some(&atom.getFloat())

  none(float64)

proc getSequence*(atom: MAtom | JSValue): Option[seq[MAtom]] {.inline.} =
  if atom.kind == Sequence:
    return some(atom.sequence)

  none(seq[MAtom])

proc getNativeCallable*(atom: MAtom | JSValue): Option[proc()] {.inline.} =
  if atom.kind == NativeCallable:
    return some(atom.fn)

  none(proc())

proc newJSValue*(kind: MAtomKind): JSValue =
  ## Allocate a new `JSValue` using Bali's garbage collector.
  ## A `JSValue` is a pointer to an atom.

  var mem = cast[ptr MAtom](baliAlloc(sizeof(MAtom)))

  {.cast(uncheckedAssign).}:
    mem[].kind = kind

  ensureMove(mem)

proc atomToJSValue*(atom: MAtom): JSValue =
  let kind = if atom.kind != Ident: atom.kind else: String

  var value = newJSValue(kind)
  case atom.kind
  of Null, Undefined:
    discard
  of Ident:
    value.str = atom.ident
  of String:
    value.str = atom.str
  of Integer:
    value.integer = atom.integer
  of Sequence:
    value.sequence = atom.sequence
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

const internStrings = defined(baliExperimentalStringInterning)
when internStrings:
  var interned {.global.}: Table[string, pointer]
  var constantEmptyStr = newJSValue(String)
  constantEmptyStr.str = newStringUninit(1)

proc str*(s: string): JSValue {.inline, cdecl.} =
  when internStrings:
    if s.len < 1:
      return constantEmptyStr

    if s in interned:
      return cast[JSValue](interned[s])

  var mem = newJSValue(String)
  mem.str = s

  when internStrings:
    interned[s] = mem

  mem

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

proc integer*(value: int, inRuntime: bool = false): JSValue {.inline, cdecl.} =
  var mem = newJSValue(Integer)
  mem.integer = value

  ensureMove(mem)

proc integer*(value: uint, inRuntime: bool = false): JSValue {.inline, cdecl.} =
  var mem = newJSValue(Integer)
  mem.integer = int(value)

  ensureMove(mem)

func stackInteger*(value: int): MAtom =
  ## Allocate a Integer atom on the stack.
  ## This is used by the parser.
  MAtom(kind: Integer, integer: value)

func stackInteger*(value: uint): MAtom =
  ## Allocate a Integer atom on the stack.
  ## This is used by the parser.
  MAtom(kind: Integer, integer: int(value))

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

proc stackObj*(): MAtom {.inline, cdecl.} =
  MAtom(kind: Object)
