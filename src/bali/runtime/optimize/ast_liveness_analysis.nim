## Routines to decide whether a segment of the AST is safely elidable
## Author: Trayambak Rai (xtrayambak at disroot dot org)

#!fmt: off
import pkg/bali/grammar/[statement],
       pkg/bali/runtime/vm/atom,
       pkg/bali/runtime/optimize/[side_effects],
       pkg/shakar
#!fmt: on

proc forLoopIsDead*(loop: Statement): bool =
  assert(loop.kind == ForLoop)

  not forLoopHasObservableSideEffects(loop)

proc conditionalIsDead*(cond: Statement): bool =
  assert(cond.kind == IfStmt)
  assert(cond.conditionExpr.kind == BinaryOp)

  let
    lhs = cond.conditionExpr.binLeft
    rhs = cond.conditionExpr.binRight

  if lhs.kind != AtomHolder and rhs.kind != AtomHolder:
    # We can't prove non-constants as unreachable.
    return false

  let
    leftAtom = lhs.atom
    rightAtom = rhs.atom

  if leftAtom.kind != rightAtom.kind:
    # We can't prove unreachability if the
    # LHS and RHS atoms aren't exactly the same type.
    # We don't perform any coercion ops because that'd cause heap allocations,
    # which we cannot do.
    return false

  let kind = leftAtom.kind

  case cond.conditionExpr.op
  of BinaryOperation.Equal, BinaryOperation.TrueEqual:
    case kind
    of Boolean:
      return &leftAtom.getBool() != &rightAtom.getBool()
    of Integer:
      return &leftAtom.getInt() != &rightAtom.getInt()
    of UnsignedInt:
      return &leftAtom.getUint() != &rightAtom.getUint()
    of Float:
      return &leftAtom.getFloat() != &rightAtom.getFloat()
    else:
      # We cannot prove the unreachability of this conditional.
      return false
  of BinaryOperation.NotEqual, BinaryOperation.NotTrueEqual:
    case kind
    of Boolean:
      return &leftAtom.getBool() == &rightAtom.getBool()
    of Integer:
      return &leftAtom.getInt() == &rightAtom.getInt()
    of UnsignedInt:
      return &leftAtom.getUint() == &rightAtom.getUint()
    of Float:
      return &leftAtom.getFloat() == &rightAtom.getFloat()
    else:
      # We cannot prove the unreachability of this conditional.
      return false
  else:
    # We do not handle this case yet.
    # TODO: More cases? (GreaterThan, LesserThan, etc.)
    return false
