import std/tables, parser, pretty, jsvalue, token

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

# WARNING: this is for internal interpreter errors, not JavaScript errors.
proc error*(interpreter: ASTInterpreter, msg: string) =
  echo "\e[0;31m" & "ERROR" & "\e[0m" & ": " & msg
  quit 1

# debug/info
proc info*(interpreter: ASTInterpreter, msg: string) =
  echo "\e[0;32m" & "INFO" & "\e[0m" & ": " & msg

proc handleIfClause*(interpreter: ASTInterpreter, keyword: Token) =
  var 
    ptrLeft: string
    comparison: ComparisonType
    ptrRight: string
    curr: Token = keyword

  while curr != nil:
    if curr.kind == tkComparisonPointerLeft:
      ptrLeft = curr.pName
    elif curr.kind == tkComparison:
      comparison = curr.comparisonType
    elif curr.kind == tkComparisonPointerRight:
      ptrRight = curr.pName
    
    curr = curr.next


  assert ptrLeft.len > 0
  assert ptrRight.len > 0
  assert comparison != ctDefault

  var hashes: tuple[left, right: string]

  if interpreter.inValueSpace(ptrLeft):
    interpreter.info "lhs in valuespace"
    hashes.left = interpreter.get(ptrLeft).hash()
  else:
    interpreter.info "lhs not in valuespace"
    let kind = inferType(ptrLeft)
    if kind == jskNone:
      interpreter.error "kind == jskNone for ptrLeft, cannot create value for hashing!"
    hashes.left = JSValue(payload: ptrLeft).hash()
  
  if interpreter.inValueSpace(ptrRight):
    interpreter.info "rhs in valuespace"
    hashes.right = interpreter.get(ptrRight).hash()
  else:
    interpreter.info "rhs not in valuespace"
    let kind = inferType(ptrRight)
    if kind == jskNone:
      interpreter.error "kind == jskNone for ptrRight, cannot create value for hashing!"
    hashes.right = JSValue(payload: ptrRight).hash()
  
  interpreter.info "Comparing LHS hash to RHS hash"
  case comparison:
    of ctEquality:
      # FIXME: add the quirky equality checker, this currently is too accurate for Brendan Eich.
      keyword.ifStatementComputedResult = hashes.left == hashes.right
    of ctNotEquality:
      keyword.ifStatementComputedResult = hashes.left != hashes.right
    of ctTrueEquality:
      keyword.ifStatementComputedResult = hashes.left == hashes.right
    of ctNotTrueEquality:
      keyword.ifStatementComputedResult = hashes.left != hashes.right
    of ctDefault:
      interpreter.error("WTF? Comparison somehow hit ctDefault even though there is an assertion that prevents that from happening. Something has went terribly, terribly wrong. Debugging time, yay! (or alternatively, conveniently blame it at a bit flip)")

proc step*(interpreter: ASTInterpreter, token: Token = nil, crawl: bool = true) =
  if token.kind == tkDeclaration:
    interpreter.step(token.next)
  elif token.kind == tkLiteral:
    interpreter.info "Assigning " & token.value.payload & " to name: \"" & token.prev.prev.name & "\""
    interpreter.add(token.prev.prev.name, token.value)
  elif token.kind == tkKeyword:
    if token.keyword == "if":
      interpreter.handleIfClause(token)
    else:
      interpreter.error("Unknown keyword \"" & token.keyword & "\"")
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
