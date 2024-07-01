import std/[hashes, logging, options]
import mirage/atom

type
  ExecCondition* = enum
    ecEqual
    ecNotEqual
    ecTrueEqual
    ecNotTrueEqual
    ecGreaterThan
    ecGreaterThanEqual
    ecLesserThan
    ecLesserThanEqual

  CondHands* = object
    lhsIdent*, rhsIdent*: Option[string]
    lhsAtom*, rhsAtom*: Option[MAtom]

  StatementKind* = enum
    CreateImmutVal
    CreateMutVal
    IfCond
    NewFunction
    Call

  CallArgKind* = enum
    cakIdent
    cakAtom

  CallArg* = object
    case kind*: CallArgKind
    of cakIdent:
      ident*: string
    of cakAtom:
      atom*: MAtom

  PositionedArguments* = seq[CallArg]

  Scope* = ref object of RootObj
    prev*, next*: Option[Scope]
    stmts*: seq[Statement]

  Function* = ref object of Scope
    name*: string

  Statement* = object
    case kind*: StatementKind
    of CreateMutVal:
      mutIdentifier*: string
      mutAtom*: MAtom
    of CreateImmutVal:
      imIdentifier*: string
      imAtom*: MAtom
    of IfCond:
      condition*: ExecCondition
      hands*: CondHands
    of Call:
      fn*: string
      arguments*: PositionedArguments
    of NewFunction:
      fnName*: string
      body*: Scope

proc hash*(stmt: Statement): Hash {.inline.} =
  var hash: Hash

  hash = hash !& stmt.kind.int
  case stmt.kind
  of CreateMutVal:
    hash = hash !& hash(
      (
        stmt.mutIdentifier,
        stmt.mutAtom
      )
    )
  of CreateImmutVal:
    hash = hash !& hash(
      (
        stmt.imIdentifier,
        stmt.imAtom
      )
    )
  of IfCond:
    hash = hash !& hash(
      (
        stmt.condition,
        stmt.hands
      )
    )
  of Call:
    hash = hash !& hash(
      (
        stmt.fn,
        stmt.arguments
      )
    )
  of NewFunction:
    hash = hash !& hash(
      (
        stmt.fnName
      )
    )
  else:
    discard

{.push checks: off, inline.}
proc createImmutVal*(name: string, atom: MAtom): Statement =
  Statement(
    kind: CreateImmutVal,
    imIdentifier: name,
    imAtom: atom
  )

proc createMutVal*(name: string, atom: MAtom): Statement =
  Statement(
    kind: CreateMutVal,
    mutIdentifier: name,
    mutAtom: atom
  )

proc identArg*(ident: string): CallArg =
  CallArg(kind: cakIdent, ident: ident)

proc atomArg*(atom: MAtom): CallArg =
  CallArg(kind: cakAtom, atom: atom)

proc expand*(stmt: Statement): seq[Statement] =
  ## Expand one statement (like a Call's atom arguments should load up immutable values)

  case stmt.kind
  of Call:
    for i, arg in stmt.arguments:
      if arg.kind == cakAtom:
        result &= createImmutVal(
          "callarg_" & $hash(stmt) & '_' & $i,
          arg.atom
        ) # XXX: should this be mutable?
  else: discard

proc call*(fn: string, arguments: PositionedArguments): Statement =
  Statement(
    kind: Call,
    fn: fn,
    arguments: arguments
  )

proc ifCond*(
  lhs, rhs: string | MAtom,
  condition: ExecCondition
): Statement =
  var hanth = CondHands()

  when lhs is string:
    info "runtime if-cond builder: lhs is an ident"
    hanth.lhsIdent = some(lhs)

  when rhs is string:
    info "runtime if-cond builder: rhs is an ident"
    hanth.rhsIdent = some(rhs)
  
  when lhs is MAtom:
    info "runtime if-cond builder: lhs is an atom"
    hanth.lhsAtom = some(lhs)

  when rhs is MAtom:
    info "runtime if-cond builder: rhs is an atom"
    hanth.rhsAtom = some(rhs)

  Statement(
    kind: IfCond,
    condition: condition,
    hands: hanth
  )
{.pop.}
