## Atom functions
## Copyright (C) 2024 Trayambak Rai
import std/tables
import mirage/atom

func isUndefined*(atom: MAtom): bool {.inline.} =
  atom.kind == Object and atom.objFields.len < 1

func isObject*(atom: MAtom): bool {.inline.} =
  atom.kind == Object

func isNull*(atom: MAtom): bool {.inline.} =
  atom.kind == Null
