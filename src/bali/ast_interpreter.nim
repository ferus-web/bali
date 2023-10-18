import std/tables, parser, pretty, jsvalue, token, logging

type
  ASTInterpreter* = ref object of RootObj
    valueSpace: TableRef[string, JSValue]
    ast*: AST
  
    cPos*: int
    cLine*: int

    currValueName*: string

proc add*(interpreter: ASTInterpreter, key: string, value: JSValue) =
  interpreter.valueSpace[key] = value

proc get*(interpreter: ASTInterpreter, key: string): JSValue =
  interpreter.valueSpace[key]

proc inValueSpace*(interpreter: ASTInterpreter, key: string): bool =
  key in interpreter.valueSpace

proc handleIfClause*(interpreter: ASTInterpreter, keyword: Token) =
  var 
    ptrLeft: string
    comparison: ComparisonType
    ptrRight: string
    curr: Token = keyword

  while curr != nil:
    if curr.kind == tkComparisonPointerLeft:
      info "Handling tkComparisonPointerLeft (LHS)"
      ptrLeft = curr.pName
    elif curr.kind == tkComparison:
      info "Handling tkComparison (equation sign)"
      comparison = curr.comparisonType
    elif curr.kind == tkComparisonPointerRight:
      info "Handling tkComparisonPointerRight (RHS)"
      ptrRight = curr.pName
      break
    
    curr = curr.next


  assert ptrLeft.len > 0
  assert ptrRight.len > 0
  assert comparison != ctDefault

  var hashes: tuple[left, right: string]

  if interpreter.inValueSpace(ptrLeft):
    info "lhs in valuespace"
    hashes.left = interpreter.get(ptrLeft).hash()
  else:
    info "lhs not in valuespace"
    let kind = inferType(ptrLeft)
    if kind == jskNone:
      error "kind == jskNone for ptrLeft, cannot create value for hashing!"
    hashes.left = JSValue(payload: ptrLeft).hash()
  
  if interpreter.inValueSpace(ptrRight):
    info "rhs in valuespace"
    hashes.right = interpreter.get(ptrRight).hash()
  else:
    info "rhs not in valuespace"
    let kind = inferType(ptrRight)
    if kind == jskNone:
      error "kind == jskNone for ptrRight, cannot create value for hashing!"
    hashes.right = JSValue(payload: ptrRight).hash()
  
  info "Comparing LHS hash to RHS hash"
  case comparison:
    of ctEquality:
      # FIXME: add the quirky equality checker, this currently is too accurate for Brendan Eich.
      info "Equality comparison (" & ptrLeft & " == " & ptrRight & ")"
      keyword.ifStatementComputedResult = hashes.left == hashes.right
    of ctNotEquality:
      info "Inequality comparison (" & ptrLeft & " != " & ptrRight & ")"
      keyword.ifStatementComputedResult = hashes.left != hashes.right
    of ctTrueEquality:
      info "True equality comparison (" & ptrLeft & " === " & ptrRight & ")"
      keyword.ifStatementComputedResult = hashes.left == hashes.right
    of ctNotTrueEquality:
      info "True inequality comparison (" & ptrLeft & " !== " & ptrRight & ")"
      keyword.ifStatementComputedResult = hashes.left != hashes.right
    of ctDefault:
      error "WTF? Comparison somehow hit ctDefault even though there is an assertion that prevents that from happening. Something has went terribly, terribly wrong. Debugging time, yay! (or alternatively, conveniently blame it at a bit flip)"

proc step*(interpreter: ASTInterpreter, token: Token = nil, crawl: bool = true) =
  if token == nil:
    return

  if token.kind == tkDeclaration:
    sanityCheck(token)
    interpreter.step(token.next)
  elif token.kind == tkLiteral:
    info "Assigning " & token.value.payload & " to name: \"" & token.prev.prev.name & "\""
    interpreter.add(token.prev.prev.name, token.value)
  elif token.kind == tkKeyword:
    if token.keyword == "if":
      interpreter.handleIfClause(token)
    else:
      error("Unknown keyword \"" & token.keyword & "\"")
  else:
    if token.next != nil:
      interpreter.step(token.next)
  
proc interpret*(interpreter: ASTInterpreter) =
  while interpreter.cPos < interpreter.ast.tokens.len:
    interpreter.step(interpreter.ast.tokens[interpreter.cPos])
    inc interpreter.cPos

proc newASTInterpreter*(ast: AST): ASTInterpreter =
  ASTInterpreter(
    valueSpace: newTable[string, JSValue](),
    ast: ast,
    cPos: 0,
    cLine: 0
  )
