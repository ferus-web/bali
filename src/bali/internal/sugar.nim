## Some syntactical sugar for making code less clunky.
## Copyright (C) 2024 Trayambak Rai and Ferus Authors

import std/options

proc `&`*[T](opt: Option[T]): T {.inline.} =
  opt.unsafeGet()

proc `*`*[T](opt: Option[T]): bool {.inline.} =
  opt.isSome

proc `!`*[T](opt: Option[T]): bool {.inline.} =
  opt.isNone

template unreachable* =
  assert false, "Unreachable"
