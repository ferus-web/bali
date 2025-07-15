import std/[tables]
import pkg/[gmp]

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

    # GC tags
    marked*: bool

  JSValue* = ptr MAtom
