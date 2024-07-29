import std/[options]
import mirage/atom
import bali/internal/sugar

type
  Gate* {.pure.} = enum
    And
    Or

  Comparison* {.pure.} = enum
    Equate
    NotEquate

  Condition* = ref object
    next*: tuple[cond: Option[Condition], gate: Gate]

    identA*, identB*: Option[string]
    atomA*, atomB*: Option[MAtom]
    comparison*: Comparison

proc append*(cond: Condition, child: Condition, gate: Gate) =
  var next = cond
  while *next.next.cond:
    next = &next.next.cond

  next.next.cond = some(child)
  next.next.gate = gate
