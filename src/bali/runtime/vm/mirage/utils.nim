## Some basic shared code across all of Mirage.

import std/options

{.push checks: on, inline, noSideEffect, gcsafe.}
proc `*`*[T](opt: Option[T]): bool =
  opt.isSome

proc `&`*[T](opt: Option[T]): T =
  unsafeGet opt

{.pop.}
