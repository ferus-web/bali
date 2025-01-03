## Some syntactical sugar for making code less clunky.

import std/options
import results

{.push checks: off, inline.}
func `*`*[T](opt: Option[T]): bool =
  opt.isSome

func `!`*[T](opt: Option[T]): bool =
  opt.isNone

func `*`*[T, E](opt: Result[T, E]): bool =
  opt.isOk

func `!`*[T, E](opt: Result[T, E]): bool =
  opt.isErr

func `&|`*[T](opt: Option[T], fallback: T): T {.inline.} =
  if opt.isSome:
    return opt.unsafeGet()

  fallback
{.pop.}

func `&`*[T](opt: Option[T]): T {.inline.} =
  opt.unsafeGet()

func `&`*[T, E](opt: Result[T, E]): T {.inline.} =
  opt.get()

func `@`*[T, E](opt: Result[T, E]): E {.inline.} =
  opt.error()

func unpack*[T](opt: Option[T], x: var T): bool {.inline.} =
  if *opt:
    x = unsafeGet(opt)
    return true

  false

template unreachable*() =
  assert false, "Unreachable"
