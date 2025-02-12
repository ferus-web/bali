## Atom-or-function variant type

import std/options
import bali/internal/sugar
import bali/runtime/vm/atom

type AtomOrFunction*[F] = object
  fn: Option[F]
  atom: Option[JSValue]

{.push inline.}
func `fn=`*[F](af: var AtomOrFunction[F], fn: F) =
  af.fn = some(fn)

  if *af.atom:
    af.atom = none(MAtom)

func `atom=`*[F](af: var AtomOrFunction[F], atom: JSValue) =
  af.atom = some(atom)

  if *af.fn:
    af.fn = none(typeof(F))

func fn*[F](af: AtomOrFunction[F]): F =
  assert(*af.fn, "fn() called but variant contains no function.")
  &af.fn

func isFn*[F](af: AtomOrFunction[F]): bool =
  assert(
    not (*af.fn and *af.atom),
    "AtomOrFunction variant simultaneously contains atom and function!",
  )

  *af.fn

func isAtom*[F](af: AtomOrFunction[F]): bool =
  assert(
    not (*af.fn and *af.atom),
    "AtomOrFunction variant simultaneously contains atom and function!",
  )

  *af.atom

func atom*[F](af: AtomOrFunction[F]): JSValue =
  assert(*af.atom, "atom() called but variant contains no atom.")
  &af.atom

func initAtomOrFunction*[F](fn: F): AtomOrFunction[F] =
  AtomOrFunction[F](fn: some(fn))

func initAtomOrFunction*[F](atom: JSValue): AtomOrFunction[F] =
  AtomOrFunction[F](atom: some(atom))
{.pop.}
