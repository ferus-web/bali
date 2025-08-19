## Copy propagation pass implementation
##
## Copyright (C) 2025 Trayambak Rai (xtrayambak at disroot dot org)
import pkg/bali/runtime/compiler/madhyasthal/[pipeline]
import pretty, sets

proc propagateCopies*(pipeline: var pipeline.Pipeline) =
  print pipeline.info.dce
