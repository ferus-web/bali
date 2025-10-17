## Some syntactical sugar for making code less clunky.

import std/options
import pkg/[results, shakar]

export shakar

{.push checks: off, inline.}
func `&|`*[T](opt: Option[T], fallback: T): T {.inline.} =
  if opt.isSome:
    return opt.unsafeGet()

  fallback
{.pop.}

func `@`*[T, E](opt: Result[T, E]): E {.inline.} =
  opt.error()

func unpack*[T](opt: Option[T], x: out T): bool {.inline.} =
  if *opt:
    x = unsafeGet(opt)
    return true

  x = default(T)
  false
