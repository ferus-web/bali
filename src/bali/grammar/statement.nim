import std/[hashes, logging, options]
import mirage/atom
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

  Statement* = ref object
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
  else:
    discard

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
proc createImmutVal*(name: string, atom: MAtom): Statement =
  Statement(
    kind: CreateImmutVal,
    imIdentifier: name,
    imAtom: atom
  )

proc returnFunc*: Statement =
  Statement(kind: ReturnFn)

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

proc expand*(stmt: Statement): seq[Statement] =
  ## Expand one statement (like a Call's atom arguments should load up immutable values)

  case stmt.kind
  of Call:
    debug "ir: expand Call statement"
    for i, arg in stmt.arguments:
      if arg.kind == cakAtom:
        debug "ir: load immutable value to expand Call's immediate arguments: " & arg.atom.crush("")
        result &= createImmutVal(
          '@' & $hash(stmt) & '_' & $i,
          arg.atom
        ) # XXX: should this be mutable?
  of ConstructObject:
    debug "ir: expand ConstructObject statement"
    for i, arg in stmt.args:
      if arg.kind == cakAtom:
        debug "ir: load immutable value to ConstructObject's immediate arguments: " & arg.atom.crush("")
        result &= createImmutVal(
          '@' & $hash(stmt) & '_' & $i,
          arg.atom
        ) # XXX: should this be mutable?
  of CallAndStoreResult:
    debug "ir: expand CallAndStoreResult statement by expanding child Call statement"
    result &= expand(stmt.storeFn)
  else: discard

proc call*(fn: string, arguments: PositionedArguments): Statement =
  Statement(
    kind: Call,
    fn: fn,
    arguments: arguments
  )

{.pop.}
