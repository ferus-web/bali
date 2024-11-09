## Some syntactical sugar for making code less clunky.

import std/options

{.push checks: off, inline.}
func `*`*[T](opt: Option[T]): bool =
  opt.isSome

func `!`*[T](opt: Option[T]): bool =
  opt.isNone
{.pop.}

func `&`*[T](opt: Option[T]): T {.inline.} =
  opt.unsafeGet()

func unpack*[T](opt: Option[T], x: var T): bool {.inline.} =
  if *opt:
    x = unsafeGet(opt)
    return true

  false

template unreachable*() =
  assert false, "Unreachable"
