## IR types for Madhyasthal / the midtier JIT compiler for Bali
##
## Copyright (C) 2025 Trayambak Rai (xtrayambak at disroot dot org)

type
  InstKind* {.pure, size: sizeof(uint16).} = enum
    LoadString
    LoadUndefined

  ArgVariantKind* {.size: sizeof(uint8).} = enum
    avkInt
    avkPos
    avkStr

  ArgVariant* = object
    case kind*: ArgVariantKind
    of avkInt: vint*: int
    of avkPos: vreg*: uint32
    of avkStr: str*: string
  
  Inst* = object
    kind*: InstKind
    args*: array[2, ArgVariant]

  Function* = ref object
    name*: string
    insts*: seq[Inst]

{.push inline.}
func loadStr*(pos: uint32, str: string): Inst =
  Inst(
    kind: LoadString,
    args: [ArgVariant(kind: avkPos, vreg: pos), ArgVariant(kind: avkStr, str: str)]
  )

func loadUndefined*(pos: uint32): Inst =
  Inst(
    kind: LoadUndefined,
    args: [ArgVariant(kind: avkPos, vreg: pos), ArgVariant()]
  )
{.pop.}
