## Small wrapper around GNU C standard library function `strtoul`
## Copyright (C) 2024 Trayambak Rai and Ferus Authors

import std/options

proc strtoul*(c: cstring, endptr: ptr char, size: cint): uint {.importc, header: "<stdlib.h>".}

proc strToUint*(str: string, size: int): Option[uint] {.inline.} =
  var 
    cstr = cast[cstring](str)
    endptr: char

  let converted = strtoul(cstr, addr endptr, size.cint)

  if endptr == '\0':
    return some(converted)
