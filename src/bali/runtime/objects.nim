## Utility for converting object types to MIR
import std/[tables, logging]
import mirage/atom
import mirage/ir/generator
import bali/internal/sugar

type BaliObject* = object
  fields*: Table[string, MAtom]

proc `[]=`*(obj: var BaliObject, key: string, atom: MAtom) {.inline.} =
  obj.fields[key] = atom

proc inject*(obj: BaliObject, pos: uint, ir: IRGenerator): uint =
  var pos = pos

  for field, atom in obj.fields:
    inc pos
    case atom.kind
    of Integer:
      discard ir.loadInt(pos, atom)
    of String:
      discard ir.loadStr(pos, atom)
    else:
      unreachable

  pos

proc newBaliObject*(fields: openArray[string]): BaliObject {.inline.} =
  var obj = BaliObject(fields: initTable[string, MAtom]())

  for field in fields:
    obj[field] = null()

  obj
