## IR types for Madhyasthal / the midtier JIT compiler for Bali
##
## Copyright (C) 2025 Trayambak Rai (xtrayambak at disroot dot org)

type
  InstKind* {.pure, size: sizeof(uint16).} = enum
    LoadString
    LoadUndefined
    LoadNumber
    LoadBoolean

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
{.pop.}
