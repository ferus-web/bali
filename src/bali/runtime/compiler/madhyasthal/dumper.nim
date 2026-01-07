## IR -> human-readable string conversion routine(s)
##
## Copyright (C) 2025-2026 Trayambak Rai (xtrayambak at disroot dot org)
import pkg/bali/runtime/compiler/madhyasthal/ir

func dumpInst*(buffer: var string, inst: ir.Inst) =
  buffer &= '('
  buffer &= $inst.kind
  buffer &= ' '

  for i, arg in inst.args:
    case arg.kind
    of avkPos:
      buffer &= '%'
      buffer &= $arg.vreg
    of avkStr:
      buffer &= '`'
      buffer &= arg.str
      buffer &= '`'
    of avkInt:
      buffer &= $arg.vint
    of avkNum:
      buffer &= $arg.flt

    if i < inst.args.len - 1:
      buffer &= ' '

  buffer &= ')'

func dumpInst*(inst: ir.Inst): string =
  var res: string
  dumpInst(res, inst)

  ensureMove(res)

func dumpFunction*(fn: ir.Function): string =
  var buffer = newStringOfCap(512)

  buffer &= '('
  buffer &= fn.name

  if fn.insts.len > 0:
    buffer &= " \n"

  for i, inst in fn.insts:
    buffer &= "  "
    dumpInst(buffer, inst)
    if i < fn.insts.len - 1:
      buffer &= '\n'

  if fn.insts.len > 0:
    buffer &= '\n'
  buffer &= ')'

  move(buffer)
