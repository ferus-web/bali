## IR types for Madhyasthal / the midtier JIT compiler for Bali
##
## Copyright (C) 2025 Trayambak Rai (xtrayambak at disroot dot org)

type
  InstKind* {.pure, size: sizeof(uint16).} = enum
    LoadString

  Function* = ref object of RootObj

