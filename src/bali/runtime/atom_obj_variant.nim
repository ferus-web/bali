## Atom-or-function variant type

import std/options
import bali/internal/sugar
import mirage/atom

type AtomOrFunction*[F] = object
  fn: Option[F]
  atom: Option[MAtom]

{.push inline.}
func `fn=`*[F](af: var AtomOrFunction[F], fn: F) =
  af.fn = some(fn)

  if *af.atom:
    af.atom = none(MAtom)

func `atom=`*[F](af: var AtomOrFunction[F], atom: sink MAtom) =
  af.atom = some(move(atom))

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

func atom*[F](af: AtomOrFunction[F]): MAtom =
  assert(*af.atom, "atom() called but variant contains no atom.")
  &af.atom

func initAtomOrFunction*[F](fn: F): AtomOrFunction[F] =
  AtomOrFunction[F](fn: some(fn))

func initAtomOrFunction*[F](atom: sink MAtom): AtomOrFunction[F] =
  AtomOrFunction[F](atom: some(move(atom)))
{.pop.}
