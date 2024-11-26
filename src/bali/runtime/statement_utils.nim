import std/[logging]
import bali/grammar/statement
import pretty

proc getValueDefinitions*(body: Scope): seq[string] =
  ## Get all the identifiers that `body` defines

  var defs: seq[string]
  for stmt in body.stmts:
    case stmt.kind
    of CreateMutVal: defs &= stmt.mutIdentifier
    of CreateImmutVal: defs &= stmt.imIdentifier
    of IfStmt:
      defs &= stmt.branchTrue.getValueDefinitions()
      defs &= stmt.branchFalse.getValueDefinitions()
    of WhileStmt:
      defs &= stmt.whBranch.getValueDefinitions()
    else: discard

  defs

proc getValueCaptures*(body: Scope): seq[string] =
  ## Get all the identifiers that `body` captures, aka does not declare and instead just accesses
  ## They need not be actually declared.

  let defs = getValueDefinitions(body)
  var captures: seq[string]

  template capture(x: string) =
    if not defs.contains(x):
      captures &= x
  
  # TODO: expand this list, it currently only includes inc/dec
  for stmt in body.stmts:
    case stmt.kind
    of Increment: capture stmt.incIdent
    of Decrement: capture stmt.decIdent
    else: discard
  
  captures

proc getStateMutators*(expr: Statement): seq[string] =
  var leftTrav = expr.binLeft
  var rightTrav = expr.binRight
  var mutators: seq[string]

  if leftTrav.kind == IdentHolder:
    mutators &= leftTrav.ident

  if rightTrav.kind == IdentHolder:
    mutators &= rightTrav.ident

  mutators

proc whStmtOnlyMutatesItsState*(stmt: Statement, captures: seq[string]): bool =
  ## Returns `true` if the statement only mutates its own state and nothing else.
  
  when not defined(danger): assert(stmt.kind == WhileStmt)

  let mutators = stmt.whConditionExpr.getStateMutators()
  for op in stmt.whBranch.stmts:
    if op.kind notin [Increment, Decrement]:
      return false

  mutators == captures
