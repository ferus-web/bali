import std/[options, tables], jsvalue

const
  BALI_MAX_TRAVERSALS {.intdefine.} = 65536

type
  TokenKind* = enum
    tkScope # just here for scopes that house more tokens
    tkDeclaration # let, var, const
    tkOperator # all operators
    tkIdentifier # identifiers for declarations
    tkAssignment # assignment operator (=)
    tkLiteral # literal value, converted to JSValue
    tkKeyword # if, else, while, etc.
    tkComparison # comparison operator
    tkComparisonPointerLeft # not to be confused with real pointers! These just help the AST interpreter know what values it needs to fetch from the namespace!
    tkComparisonPointerRight # not to be confused with real pointers! These just help the AST interpreter know what values it needs to fetch from the namespace!

  OperatorKind* = enum
    okEqualsEquals
    okGreater
    okLesser
    okNotEquals

  ComparisonType* = enum
    ctEquality        # ==
    ctNotEquality     # !=
    ctTrueEquality    # ===
    ctNotTrueEquality # !==
    ctDefault

  Token* = ref object of RootObj
    prev*: Token
    next*: Token

    case kind*: TokenKind:
      of tkDeclaration:
        mutable*: bool
      of tkOperator:
        opKind*: OperatorKind
      of tkIdentifier:
        name*: string
      of tkLiteral:
        value*: JSValue
      of tkComparison:
        comparisonType*: ComparisonType
      of tkComparisonPointerLeft, tkComparisonPointerRight:
        pName*: string
      of tkKeyword:
        keyword*: string

        ifStatementComputedResult*: bool
      of tkScope:
        valueSpace*: TableRef[string, JSValue]
        tokens*: seq[Token]
      of tkAssignment: discard

proc `$`*(tk: TokenKind): string =
  case tk:
    of tkDeclaration:
      return "Declaration (let/const/var)"
    of tkOperator:
      return "Operator"
    of tkIdentifier:
      return "Value Identifier"
    of tkAssignment:
      return "Assignment (=)"
    of tkLiteral:
      return "Literal (JSValue)"
    of tkKeyword:
      return "Keyword"
    of tkComparison:
      return "Comparison Operator"
    of tkComparisonPointerLeft:
      return "Comparison Pointer LHS"
    of tkComparisonPointerRight:
      return "Comparison Pointer RHS"
    of tkScope:
      return "Scope"

#[
  Segfault preventer 7000

  Please call this before any operation as it is a good safety net.
]#
proc sanityCheck*(token: Token) =
  case token.kind:
    of tkAssignment:
      assert token.prev != nil and token.next != nil, "Assignment needs a prev node (identifier) and next node (literal)"
      assert token.prev.kind == tkIdentifier and token.next.kind == tkLiteral, "Assignment prev node must be identifier and next node must be literal"
    else:
      discard

proc getAbsoluteParent*(token: Token): Token =
  var parent = token.prev

  while parent.prev != nil:
    parent = parent.prev

  parent

proc getAbsoluteChild*(token: Token): Token =
  var child = token.next

  while child.next != nil:
    child = child.next

  child

proc traverseUntilChildFound*(token: Token, kind: TokenKind): Option[Token] =
  var
    idx = 0
    child = token.next

  while idx < BALI_MAX_TRAVERSALS and child.kind != kind:
    if child.next != nil:
      child = child.next
    else:
      break

  
  if child.kind == kind:
    return some(child)

proc traverseUntilParentFound*(token: Token, kind: TokenKind): Option[Token] =
  var
    idx = 0
    parent = token.prev

  while idx < BALI_MAX_TRAVERSALS:
    inc idx
    if parent.prev != nil:
      parent = parent.prev
    
    if parent.kind == kind:
      break

  if parent.kind == kind:
    return some(parent)

proc getValue*(token: Token): JSValue =
  var value: JSValue

  if token.kind == tkLiteral:
    value = token.value
  else:
    let lit = token.traverseUntilChildFound(tkLiteral)
    assert lit.isSome
    value = lit.get().value

  value
