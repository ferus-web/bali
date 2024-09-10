import std/[hashes, logging, options, tables]
import mirage/atom
import bali/internal/sugar
import pretty

type
  StatementKind* = enum
    CreateImmutVal
    CreateMutVal
    NewFunction
    Call
    ReturnFn
    CallAndStoreResult
    ConstructObject
    ReassignVal
    ThrowError
    BinaryOp
    IdentHolder
    AtomHolder

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
    name*: string = "outer"
    arguments*: seq[string] ## expected arguments!
  
  BinaryOperation* {.pure.} = enum
    Add
    Sub
    Mult
    Div
    Pow
    Invalid

  Statement* = ref object
    line*, col*: uint = 0
    case kind*: StatementKind
    of CreateMutVal:
      mutIdentifier*: string
      mutAtom*: MAtom
    of CreateImmutVal:
      imIdentifier*: string
      imAtom*: MAtom
    of Call:
      fn*: string
      arguments*: PositionedArguments
    of NewFunction:
      fnName*: string
      body*: Scope
    of ReturnFn:
      retVal*: Option[MAtom]
      retIdent*: Option[string]
    of CallAndStoreResult:
      mutable*: bool
      storeIdent*: string
      storeFn*: Statement
    of ConstructObject:
      objName*: string
      args*: PositionedArguments
    of ReassignVal:
      reIdentifier*: string
      reAtom*: MAtom
    of ThrowError:
      error*: tuple[str: Option[string], exc: Option[void]]
    of BinaryOp:
      binLeft*, binRight*: Statement
      op*: BinaryOperation = BinaryOperation.Invalid
      binStoreIn*: Option[string]
    of IdentHolder:
      ident*: string
    of AtomHolder:
      atom*: MAtom

func hash*(fn: Function): Hash {.inline.} =
  when fn is Scope: # FIXME: really dumb fix to prevent a segfault
    hash(0)
  else:
    hash((fn.name, fn.arguments))

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
  of BinaryOp:
    hash = hash !& hash(
      (stmt.op, stmt.binLeft, stmt.binRight, stmt.binStoreIn)
    )
  else:
    discard

  hash

proc pushIdent*(args: var PositionedArguments, ident: string) {.inline.} =
  args &=
    CallArg(
      kind: cakIdent,
      ident: ident
    )

proc pushAtom*(args: var PositionedArguments, atom: MAtom) {.inline.} =
  args &=
    CallArg(
      kind: cakAtom,
      atom: atom
    )

{.push checks: off, inline.}
proc throwError*(
  errorStr: Option[string],
  errorExc: Option[void] # TODO: implement
): Statement =
  if *errorStr and *errorExc:
    raise newException(ValueError, "Both `errorStr` and `errorExc` are full containers - something has went horribly wrong.")
  
  Statement(
    kind: ThrowError,
    error: (str: errorStr, exc: errorExc)
  )

proc createImmutVal*(name: string, atom: MAtom): Statement =
  Statement(
    kind: CreateImmutVal,
    imIdentifier: name,
    imAtom: atom
  )

proc returnFunc*: Statement =
  Statement(kind: ReturnFn)

proc atomHolder*(atom: MAtom): Statement =
  Statement(kind: AtomHolder, atom: atom)

proc identHolder*(ident: string): Statement =
  Statement(kind: IdentHolder, ident: ident)

proc binOp*(op: BinaryOperation, left, right: Statement, storeIdent: string = ""): Statement =
  Statement(
    kind: BinaryOp,
    binLeft: left, binRight: right,
    op: op,
    binStoreIn: if storeIdent.len > 0: storeIdent.some() else: none(string)
  )

proc reassignVal*(identifier: string, atom: MAtom): Statement =
  Statement(kind: ReassignVal, reIdentifier: identifier, reAtom: atom)

proc returnFunc*(retVal: MAtom): Statement =
  Statement(kind: ReturnFn, retVal: some(retVal))

proc returnFunc*(ident: string): Statement =
  Statement(kind: ReturnFn, retIdent: some(ident))

proc callAndStoreImmut*(ident: string, fn: Statement): Statement =
  Statement(
    kind: CallAndStoreResult,
    mutable: false,
    storeIdent: ident,
    storeFn: fn
  )

proc callAndStoreMut*(ident: string, fn: Statement): Statement =
  Statement(
    kind: CallAndStoreResult,
    mutable: true,
    storeIdent: ident,
    storeFn: fn
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

proc constructObject*(name: string, args: PositionedArguments): Statement =
  Statement(
    kind: ConstructObject,
    objName: name,
    args: args
  )

proc call*(fn: string, arguments: PositionedArguments): Statement =
  Statement(
    kind: Call,
    fn: fn,
    arguments: arguments
  )

{.pop.}
