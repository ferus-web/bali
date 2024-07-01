## Some syntactical sugar for making code less clunky.
## Copyright (C) 2024 Trayambak Rai and Ferus Authors

import std/options

{.push checks: off, inline.}
proc `&`*[T](opt: Option[T]): T =
  opt.unsafeGet()

proc `*`*[T](opt: Option[T]): bool =
  opt.isSome

proc `!`*[T](opt: Option[T]): bool =
  opt.isNone

proc unpack*[T](opt: Option[T], x: var T): bool =
  if *opt:
    x = unsafeGet(opt)
    return true

  false
{.pop.}

template unreachable* =
  assert false, "Unreachable"
