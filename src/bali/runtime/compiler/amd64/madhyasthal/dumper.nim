## IR -> human-readable string conversion routine(s)
##
## Copyright (C) 2025 Trayambak Rai (xtrayambak at disroot dot org)
import pkg/bali/runtime/compiler/amd64/madhyasthal/ir

proc dumpInst*(buffer: var string, inst: ir.Inst) =
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

proc dumpFunction*(fn: ir.Function): string =
  var buffer = newStringOfCap(512)

  buffer &= '('
  buffer &= fn.name
  buffer &= " \n"
  
  for i, inst in fn.insts:
    buffer &= "  "
    dumpInst(buffer, inst)
    if i < fn.insts.len - 1:
      buffer &= '\n'
  
  buffer &= '\n'
  buffer &= ')'

  move(buffer)
