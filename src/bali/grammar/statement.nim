import std/[hashes, options]
import bali/runtime/vm/atom
import bali/runtime/normalize
import bali/internal/sugar

{.experimental: "strictDefs".}

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
    AccessField
    IfStmt
    CopyValMut
    CopyValImmut
    WhileStmt
    Increment
    Decrement
    Break
    Waste
    AccessArrayIndex
    TernaryOp
    ForLoop
    TryCatch
    CompoundAssignment

  FieldAccess* = ref object
    prev*, next*: FieldAccess
    identifier*: string

  CallArgKind* = enum
    cakIdent
    cakFieldAccess
    cakImmediateExpr
    cakAtom

  CallArg* = object
    case kind*: CallArgKind
    of cakIdent:
      ident*: string
    of cakAtom:
      atom*: MAtom
    of cakFieldAccess:
      access*: FieldAccess
    of cakImmediateExpr:
      expr*: Statement

  PositionedArguments* = seq[CallArg]

  Scope* = ref object of RootObj
    prev*: Option[Scope]
    children*: seq[Scope]
    stmts*: seq[Statement]

  Function* = ref object of Scope
    name*: string = "outer"
    arguments*: seq[string] = @[] ## expected arguments!

  BinaryOperation* {.pure.} = enum
    Add
    Sub
    Mult
    Div
    Pow
    Invalid
    Equal
    TrueEqual
    GreaterThan
    GreaterOrEqual
    LesserThan
    LesserOrEqual
    NotEqual
    NotTrueEqual

  FunctionCall* = object
    field*: Option[FieldAccess]
    ident*: Option[string]
    function*: string

  Statement* = ref object
    line*, col*: uint = 1
    case kind*: StatementKind
    of CreateMutVal:
      mutIdentifier*: string
      mutAtom*: MAtom
    of CreateImmutVal:
      imIdentifier*: string
      imAtom*: MAtom
    of Call:
      fn*: FunctionCall
      arguments*: PositionedArguments
      mangle*: bool
      expectsReturnVal*: bool = false
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
      error*: tuple[str: Option[string], exc: Option[void], ident: Option[string]]
    of BinaryOp:
      binLeft*, binRight*: Statement
      op*: BinaryOperation = BinaryOperation.Invalid
      binStoreIn*: Option[string]
    of IdentHolder:
      ident*: string
    of AtomHolder:
      atom*: MAtom
    of AccessField:
      identifier*: string
      field*: string
    of IfStmt:
      conditionExpr*: Statement
      branchTrue*: Scope
      branchFalse*: Scope
    of CopyValMut:
      cpMutSourceIdent*: string
      cpMutDestIdent*: string
    of CopyValImmut:
      cpImmutSourceIdent*: string
      cpImmutDestIdent*: string
    of WhileStmt:
      whConditionExpr*: Statement
      whBranch*: Scope
    of Increment:
      incIdent*: string
    of Decrement:
      decIdent*: string
    of Waste:
      wstAtom*: Option[MAtom]
      wstIdent*: Option[string]
    of Break: discard
    of AccessArrayIndex:
      arrAccIdent*: string
      arrAccIndex*: Option[MAtom]
      arrAccIdentIndex*: Option[string]
    of TernaryOp:
      ternaryCond*: Statement
      trueTernary*, falseTernary*: Statement
      ternaryStoreIn*: Option[string]
    of ForLoop:
      forLoopInitializer*: Option[Statement]
      forLoopCond*: Option[Statement]
      forLoopIter*: Option[Statement]
      forLoopBody*: Scope
    of TryCatch:
      tryStmtBody*: Scope
      tryCatchBody*: Option[Scope]
      tryErrorCaptureIdent*: Option[string]
    of CompoundAssignment:
      compAsgnOp*: BinaryOperation
      compAsgnTarget*: string
      compAsgnCompounder*: MAtom

func hash*(access: FieldAccess): Hash {.inline.} =
  hash((access.identifier))

proc hash*(scope: Scope): Hash {.inline.}

proc hash*(call: FunctionCall): Hash {.inline.} =
  var hash = Hash(0)
  if *call.field:
    hash = hash !& hash(&call.field)

  if *call.ident:
    hash = hash !& hash(&call.ident)

  hash

proc hash*(stmt: Statement): Hash {.inline.} =
  var hash = Hash(0)

  hash = hash !& stmt.kind.int
  case stmt.kind
  of CreateMutVal:
    hash = hash !& hash((stmt.mutIdentifier, stmt.mutAtom))
  of CreateImmutVal:
    hash = hash !& hash((stmt.imIdentifier, stmt.imAtom))
  of Call:
    hash = hash !& hash((stmt.fn, stmt.arguments))
  of NewFunction:
    hash = hash !& hash((stmt.fnName))
  of BinaryOp:
    hash = hash !& hash((stmt.op, stmt.binLeft, stmt.binRight, stmt.binStoreIn))
  of IfStmt:
    hash = hash !& hash((stmt.conditionExpr))
  of AccessField:
    hash = hash !& hash((stmt.identifier, stmt.field))
  of AtomHolder:
    hash = hash !& hash(stmt.atom)
  of IdentHolder:
    hash = hash !& hash(stmt.ident)
  of WhileStmt:
    hash = hash !& hash((stmt.whConditionExpr, stmt.whBranch))
  else:
    discard

  hash

proc hash*(fn: Function): Hash {.inline.} =
  when fn is Scope: # FIXME: really dumb fix to prevent a segfault
    hash(0)
  else:
    hash((fn.name, fn.arguments))

proc hash*(scope: Scope): Hash {.inline.} =
  var hash = Hash(0)

  if *scope.prev:
    hash = hash(&scope.prev)

  hash

proc pushIdent*(args: var PositionedArguments, ident: string) {.inline.} =
  args &= CallArg(kind: cakIdent, ident: ident)

proc createFieldAccess*(splitted: seq[string]): FieldAccess =
  ## From a sequence of identifiers (assuming they are in sorted order of accesses),
  ## create a `FieldAccess`, which has a "view" of the top of the field access chain.
  var
    top = FieldAccess(identifier: splitted[0])
    curr = top

  for ident in splitted[1 ..< splitted.len]:
    var acc = FieldAccess(identifier: ident)
    curr.next = acc
    acc.prev = curr

    curr = acc

  top

proc pushFieldAccess*(args: var PositionedArguments, access: FieldAccess) {.inline.} =
  args &= CallArg(kind: cakFieldAccess, access: access)

proc pushAtom*(args: var PositionedArguments, atom: MAtom) {.inline.} =
  args &= CallArg(kind: cakAtom, atom: atom)

proc pushImmExpr*(args: var PositionedArguments, expr: Statement) {.inline.} =
  assert expr.kind == BinaryOp, "Attempt to push non expression"
  args &= CallArg(kind: cakImmediateExpr, expr: expr)

{.push checks: off, inline.}
proc throwError*(
    errorStr: Option[string], errorExc: Option[void], errorIdent: Option[string]
): Statement =
  if *errorStr and *errorExc and *errorIdent:
    raise newException(
      ValueError,
      "Both `errorStr` and `errorExc` are full containers - something has went horribly wrong.",
    )

  Statement(kind: ThrowError, error: (str: errorStr, exc: errorExc, ident: errorIdent))

proc createImmutVal*(name: string, atom: MAtom): Statement =
  Statement(kind: CreateImmutVal, imIdentifier: name, imAtom: atom)

proc breakStmt*(): Statement =
  Statement(kind: Break)

proc returnFunc*(): Statement =
  Statement(kind: ReturnFn)

proc waste*(atom: MAtom): Statement =
  Statement(kind: Waste, wstAtom: atom.some())

proc waste*(ident: string): Statement =
  Statement(kind: Waste, wstIdent: ident.some())

proc forLoop*(
    initializer, condition, incrementor: Option[Statement], body: Scope
): Statement =
  Statement(
    kind: ForLoop,
    forLoopInitializer: initializer,
    forLoopCond: condition,
    forLoopIter: incrementor,
    forLoopBody: body,
  )

proc increment*(ident: string): Statement =
  Statement(kind: Increment, incIdent: ident)

proc arrayAccess*(ident: string, index: MAtom): Statement =
  Statement(kind: AccessArrayIndex, arrAccIdent: ident, arrAccIndex: index.some)

proc arrayAccess*(ident: string, index: string): Statement =
  Statement(kind: AccessArrayIndex, arrAccIdent: ident, arrAccIdentIndex: index.some)

proc decrement*(ident: string): Statement =
  Statement(kind: Decrement, decIdent: ident)

proc whileStmt*(condition: Statement, body: Scope): Statement =
  Statement(kind: WhileStmt, whConditionExpr: condition, whBranch: body)

proc ifStmt*(condition: Statement, body, elseScope: Scope): Statement =
  Statement(
    kind: IfStmt, conditionExpr: condition, branchTrue: body, branchFalse: elseScope
  )

proc atomHolder*(atom: MAtom): Statement =
  Statement(kind: AtomHolder, atom: atom)

proc identHolder*(ident: string): Statement =
  Statement(kind: IdentHolder, ident: ident)

proc copyValMut*(dest, source: string): Statement =
  Statement(kind: CopyValMut, cpMutSourceIdent: source, cpMutDestIdent: dest)

proc copyValImmut*(dest, source: string): Statement =
  Statement(kind: CopyValImmut, cpImmutSourceIdent: source, cpImmutDestIdent: dest)

proc binOp*(
    op: BinaryOperation, left, right: Statement, storeIdent: string = ""
): Statement =
  Statement(
    kind: BinaryOp,
    binLeft: left,
    binRight: right,
    op: op,
    binStoreIn:
      if storeIdent.len > 0:
        storeIdent.some()
      else:
        none(string),
  )

proc reassignVal*(identifier: string, atom: MAtom): Statement =
  Statement(kind: ReassignVal, reIdentifier: identifier, reAtom: atom)

proc returnFunc*(retVal: MAtom): Statement =
  Statement(kind: ReturnFn, retVal: some(retVal))

proc returnFunc*(ident: string): Statement =
  Statement(kind: ReturnFn, retIdent: some(ident))

proc callAndStoreImmut*(ident: string, fn: Statement): Statement =
  var fn = fn
  fn.expectsReturnVal = true
  Statement(kind: CallAndStoreResult, mutable: false, storeIdent: ident, storeFn: fn)

proc callAndStoreMut*(ident: string, fn: Statement): Statement =
  var fn = fn
  fn.expectsReturnVal = true
  Statement(kind: CallAndStoreResult, mutable: true, storeIdent: ident, storeFn: fn)

proc createMutVal*(name: string, atom: MAtom): Statement =
  Statement(kind: CreateMutVal, mutIdentifier: name, mutAtom: atom)

proc identArg*(ident: string): CallArg =
  CallArg(kind: cakIdent, ident: ident)

proc atomArg*(atom: MAtom): CallArg =
  CallArg(kind: cakAtom, atom: atom)

proc constructObject*(name: string, args: PositionedArguments): Statement =
  Statement(kind: ConstructObject, objName: name, args: args)

proc call*(
    fn: FunctionCall,
    arguments: PositionedArguments,
    mangle: bool = true,
    expectsReturnVal: bool = false,
): Statement =
  Statement(
    kind: Call,
    fn: fn,
    arguments: arguments,
    mangle: mangle,
    expectsReturnVal: expectsReturnVal,
  )

proc callFunction*(name: string): FunctionCall =
  FunctionCall(function: name)

proc callFunction*(name: string, ident: string): FunctionCall =
  FunctionCall(function: name, ident: some(ident))

proc callFunction*(name: string, field: FieldAccess): FunctionCall =
  FunctionCall(function: name, field: some field)

proc compoundAssignment*(
  op: BinaryOperation,
  target: string,
  compounder: MAtom
): Statement =
  Statement(
    kind: CompoundAssignment,
    compAsgnTarget: target,
    compAsgnCompounder: compounder,
    compAsgnOp: op
  )

{.pop.}

proc normalizeIRName*(call: FunctionCall): string =
  return normalizeIRName(call.function)
