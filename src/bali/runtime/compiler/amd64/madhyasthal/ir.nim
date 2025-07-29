## IR types for Madhyasthal / the midtier JIT compiler for Bali
##
## Copyright (C) 2025 Trayambak Rai (xtrayambak at disroot dot org)

type
  InstKind* {.pure, size: sizeof(uint16).} = enum
    LoadString
    LoadUndefined
    LoadNumber
    LoadBoolean
    LoadNull
    ZeroRetval
    ReadProperty
    ReadScalarRegister

  Register* {.size: sizeof(uint8), pure.} = enum
    ReturnValue = 0
    CallArgument = 1
    Error = 2

  ArgVariantKind* {.size: sizeof(uint8).} = enum
    avkInt
    avkPos
    avkStr
    avkNum

  ArgVariant* = object
    case kind*: ArgVariantKind
    of avkInt: vint*: int
    of avkPos: vreg*: uint32
    of avkStr: str*: string
    of avkNum: flt*: float
  
  Inst* = object
    kind*: InstKind
    args*: array[2, ArgVariant]

  Function* = ref object
    name*: string
    insts*: seq[Inst]

{.push inline.}
func loadStr*(pos: uint32, str: string): Inst =
  Inst(
    kind: InstKind.LoadString,
    args: [ArgVariant(kind: avkPos, vreg: pos), ArgVariant(kind: avkStr, str: str)]
  )

func loadUndefined*(pos: uint32): Inst =
  Inst(
    kind: InstKind.LoadUndefined,
    args: [ArgVariant(kind: avkPos, vreg: pos), ArgVariant()]
  )

func loadNumber*(pos: uint32, value: float): Inst =
  Inst(
    kind: InstKind.LoadNumber,
    args: [ArgVariant(kind: avkPos, vreg: pos), ArgVariant(kind: avkNum, flt: value)]
  )

func loadBoolean*(pos: uint32, value: bool | int): Inst =
  Inst(
    kind: InstKind.LoadBoolean,
    args: [ArgVariant(kind: avkPos, vreg: pos), ArgVariant(kind: avkInt, vint: cast[int](value))]
  )

func loadNull*(pos: uint32): Inst =
  Inst(
    kind: InstKind.LoadNull,
    args: [ArgVariant(kind: avkPos, vreg: pos), ArgVariant()]
  )

func zeroRetval*(): Inst =
  Inst(
    kind: InstKind.ZeroRetval,
    args: [ArgVariant(), ArgVariant()]
  )

func readProperty*(sourcePos: uint32, field: string): Inst =
  Inst(
    kind: InstKind.ReadProperty,
    args: [ArgVariant(kind: avkPos, vreg: sourcePos), ArgVariant(kind: avkStr, str: field)]
  )

func readScalarRegister*(register: Register, dest: uint32): Inst =
  Inst(
    kind: InstKind.ReadScalarRegister,
    args: [ArgVariant(kind: avkInt, vint: int(register)), ArgVariant(kind: avkPos, vreg: dest)]
  )
{.pop.}
