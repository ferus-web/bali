## JavaScript parser

import std/[options, logging, strutils, tables]
import bali/grammar/[token, tokenizer, ast, errors, statement]
import bali/internal/sugar
import bali/runtime/atom_helpers
import pkg/mirage/atom
import pkg/[results, pretty, yaml]

{.push warning[UnreachableCode]: off.}

type
  ParserOpts* = object
    test262*: bool = false ## Whether to scan for Test262 directives

  Parser* = ref object
    tokenizer*: Tokenizer
    ast: AST
    errors*: seq[ParseError]
    opts*: ParserOpts

    precededByMultilineComment: bool = false
    foundShebang: bool = false

template error(parser: Parser, kind: ParseErrorKind, msg: string) =
  parser.errors &= ParseError(location: parser.tokenizer.location, message: msg)

  return

proc `$`*(error: ParseError): string =
  var buff: string

  case error.kind
  of UnexpectedToken:
    buff &= "unexpected token: " & error.message
  of Other:
    buff &= error.message

  buff & " (line " & $error.location.line & ", column " & $error.location.col & ')'

proc parseArguments*(parser: Parser): Option[PositionedArguments]

proc parseFunctionCall*(parser: Parser, name: string): Option[Statement] =
  let
    args = parser.parseArguments()
    arguments =
      if *args:
        &args
      else:
        newSeq[CallArg](0)

  if name == "$DONOTEVALUATE":
    parser.ast.doNotEvaluate = true

  if name.contains('.'):
    let access = createFieldAccess(name.split('.'))
    var name: string
    var curr = access

    while curr.next != nil:
      curr = curr.next

    name = curr.identifier

    return some call(callFunction(name, access), arguments)
  else:
    return some call(name.callFunction, arguments)

proc parseAtom*(parser: Parser, token: Token): Option[MAtom]

proc parseExpression*(
    parser: Parser, storeIn: Option[string] = none(string)
): Option[Statement] =
  info "parser: parsing arithmetic/binary expression"
  var term = Statement(kind: BinaryOp, binStoreIn: storeIn)

  template parseRHSExpression(otherRight: Statement) =
    debug "parser: " & $otherRight.kind & " will fill right term"
    var copiedTok = deepCopy(parser.tokenizer)
    if not parser.tokenizer.eof() and
        (let andSymbol = parser.tokenizer.nextExceptWhitespace(); *andSymbol):
      case (&andSymbol).kind
      of TokenKind.And, TokenKind.Or:
        let expr = parser.parseExpression()

        if *expr:
          term.binLeft = Statement(
            kind: BinaryOp,
            binStoreIn: storeIn,
            binLeft: term.binLeft,
            binRight: otherRight,
          )
          term.binRight = &expr
          break
        else:
          parser.error Other, "expected expression"
      else:
        parser.tokenizer = move(copiedTok)

  while not parser.tokenizer.eof and (term.binLeft == nil or term.binRight == nil):
    let next = parser.tokenizer.next()

    case next.kind
    of TokenKind.Number:
      debug "parser: whilst parsing arithmetic expr, found number"
      if term.binLeft == nil:
        debug "parser: atom will fill left term"
        term.binLeft = atomHolder(&parser.parseAtom(next))
      else:
        debug "parser: atom will fill right term"
        term.binRight = atomHolder(&parser.parseAtom(next))
    of TokenKind.String:
      if (let err = next.getError(); *err):
        debug "parser: whilst parsing arithmetic expr, found String with error. Adding to syntax error and aborting parsing."
        parser.error Other, &err

      debug "parser: whilst parsing arithmetic expr, found String"
      if term.binLeft != nil:
        debug "parser: atom will fill left term"
        term.binLeft = atomHolder(&parser.parseAtom(next))
      else:
        debug "parser: atom will fill right term"
        term.binRight = atomHolder(&parser.parseAtom(next))
    of TokenKind.Identifier:
      debug "parser: whilst parsing arithmetic expr, found ident"
      if term.binLeft == nil:
        debug "parser: ident will fill left term"
        term.binLeft = identHolder(next.ident)
      else:
        debug "parser: ident will fill right term"
        term.binRight = identHolder(next.ident)
    of TokenKind.Add:
      debug "parser: whilst parsing arithmetic expr, found add operand"
      term.op = BinaryOperation.Add
    of TokenKind.Sub:
      debug "parser: whilst parsing arithmetic expr, found sub operand"
      term.op = BinaryOperation.Sub
    of TokenKind.Mul:
      debug "parser: whilst parsing arithmetic expr, found mult operand"
      term.op = BinaryOperation.Mult
    of TokenKind.Div:
      debug "parser: whilst parsing arithmetic expr, found div operand"
      term.op = BinaryOperation.Div
    of TokenKind.Equal:
      debug "parser: whilst parsing arithmetic expr, found equality operand"
      term.op = BinaryOperation.Equal
    of TokenKind.GreaterThan:
      debug "parser: whilst parsing arithmetic expr, found greater-than operand"
      term.op = BinaryOperation.GreaterThan
    of TokenKind.GreaterEqual:
      debug "parser: whilst parsing arithmetic expr, found greater-than-or-equal-to operand"
      term.op = BinaryOperation.GreaterOrEqual
    of TokenKind.LessThan:
      debug "parser: whilst parsing arithmetic expr, found lesser-than operand"
      term.op = BinaryOperation.LesserThan
    of TokenKind.LessEqual:
      debug "parser: whilst parsing arithmetic expr, found lesser-than-or-equal-to operand"
      term.op = BinaryOperation.LesserOrEqual
    of TokenKind.NotEqual:
      term.op = BinaryOperation.NotEqual
    of TokenKind.Whitespace:
      debug "parser: whilst parsing arithmetic expr, found whitespace"
      if next.isNewline():
        debug "parser: whitespace contains newline, aborting expr parsing"
        break
    of TokenKind.LParen:
      debug "parser: whilst parsing arithmetic expr, found potential right-hand expr"
      if term.op == BinaryOperation.Invalid:
        debug "parser: term.op == Invalid, this probably isn't an expression in the first place..."
        return

      let expr = parser.parseExpression()
      if !expr:
        return
        # parser.error Other, "failed to parse expression"

      term.binRight = &expr
    of TokenKind.RParen:
      debug "parser: whilst parsing arithmetic expr, found right-paren to close off expr; aborting expr parsing"
      parser.tokenizer.pos -= 1
      break
    of TokenKind.True:
      debug "parser: whilst parsing arithmetic expr, found boolean (true)"
      if term.binLeft == nil:
        debug "parser: boolean will fill left term"
        term.binLeft = atomHolder(boolean(true))
      else:
        parseRHSExpression(atomHolder(boolean(true)))
        term.binRight = atomHolder(boolean(true))
    of TokenKind.False:
      debug "parser: whilst parsing arithmetic expr, found boolean (false)"
      if term.binLeft == nil:
        debug "parser: boolean will fill left term"
        term.binLeft = atomHolder(boolean(false))
      else:
        debug "parser: boolean will fill right term"
        term.binRight = atomHolder(boolean(false))
    of TokenKind.Comment:
      debug "parser: whilst parsing arithmetic expr, found comment - ignoring"
      discard
    else:
      debug "parser: met unexpected token " & $next.kind &
        " during tokenization, marking expression parse as failed"
      return

  #[ if term.binRight == nil:
    debug "parser: right term in arithmetic expr is empty but we need to fill it somehow, filling it with boolean `true`"
    debug "FIXME: parser: this is probably not the right thing to do!"
    term.op = BinaryOperation.Equal
    term.binRight = atomHolder(boolean(true)) # TODO: is this the right thing to do in this case? ]#

  if term.binLeft != nil and term.binRight != nil:
    return some term
  else:
    return
    #parser.error Other, "expected left term and right term to complete expression"

proc parseConstructor*(parser: Parser): Option[Statement] =
  let next = parser.tokenizer.nextExceptWhitespace()

  if !next:
    parser.error UnexpectedToken, "expected Identifier, got EOF"

  if (&next).kind != TokenKind.Identifier:
    parser.error UnexpectedToken, "expected Identifier, got " & $(&next).kind

  if not parser.tokenizer.eof() and parser.tokenizer.next().kind != TokenKind.LParen:
    parser.error Other, "expected left parenthesis when creating object constructor"

  return some(constructObject((&next).ident, &parser.parseArguments()))

proc parseTypeofCall*(parser: Parser): Option[PositionedArguments] =
  if parser.tokenizer.eof:
    parser.error Other, "expected expression, got EOF"

  let
    tokenizer = parser.tokenizer.deepCopy()
    next = parser.tokenizer.nextExceptWhitespace()
    mustEndWithParen = *next and (&next).kind == TokenKind.LParen

  var metParen = false

  if not mustEndWithParen:
    parser.tokenizer = tokenizer

  var args: PositionedArguments
  while not parser.tokenizer.eof:
    if mustEndWithParen and metParen:
      break

    let token = parser.tokenizer.next()

    if token.isNewline():
      break

    if token.kind == TokenKind.Whitespace:
      continue

    if token.kind == TokenKind.RParen:
      metParen = true
      break

    if token.kind == TokenKind.Identifier:
      args.pushIdent(token.ident)
    else:
      let atom = parser.parseAtom(token)
      if !atom:
        parser.error UnexpectedToken, "expected value or identifier, got " & $token.kind

      args.pushAtom(&atom)

  if mustEndWithParen and not metParen:
    parser.error Other, "missing ) in parenthetical"

  some(args)

proc parseArray*(parser: Parser): Option[MAtom] =
  # We are assuming that the starting bracket (`[`) has been consumed.
  debug "parser: parsing array"
  if parser.tokenizer.eof:
    parser.error Other, "expected expression, got EOF"

  var
    arr: seq[MAtom]
    prev = TokenKind.LBracket
    metRBracket = false

  while not parser.tokenizer.eof and not metRBracket:
    let token = parser.tokenizer.next()
    if token.kind == TokenKind.Whitespace:
      debug "parser: encountered whitespace whilst parsing array elements, ignoring."
      continue

    if token.kind == TokenKind.RBracket:
      debug "parser: found right bracket whilst parsing array elements, stopping array parsing."
      metRBracket = true
      break

    if token.kind == TokenKind.Comma:
      debug "parser: found comma whilst parsing array elements"
      if prev in {TokenKind.LBracket, TokenKind.Comma}:
        debug "parser: previous token was left bracket or comma, appending `undefined` to array"
        prev = TokenKind.Comma
        arr &= undefined()
      else:
        debug "parser: previous token wasn't those two, continuing."
        prev = TokenKind.Comma

      continue

    if token.kind == TokenKind.Comment:
      debug "parser: found comment whilst parsing array elements"
      continue

    let atom = parser.parseAtom(token)
    if !atom:
      parser.error UnexpectedToken,
        "expected expression, value or name, got " & $token.kind & " instead."

    debug "parser: appending atom to array: " & (&atom).crush()
    arr &= &atom

    prev = token.kind

  if not metRBracket:
    parser.error Other, "array is not closed off by bracket"

  some sequence(arr)

proc parseArrayIndex*(parser: Parser, ident: string): Option[Statement] =
  # We are assuming that the starting bracket (`[`) has been consumed.
  if parser.tokenizer.eof:
    parser.error Other, "expected expression, got EOF"

  template missingRBracket() =
    parser.error Other, "missing ] in index expression"
    return false

  proc checkForRBracket(): bool =
    # Returns a parsing error 
    let closing = parser.tokenizer.nextExceptWhitespace()
    if !closing:
      missingRBracket

    let kind = (&closing).kind
    case kind
    of TokenKind.RBracket:
      return true
    of TokenKind.Comment:
      return checkForRBracket()
    else:
      missingRBracket

  if (let indexToken = parser.tokenizer.nextExceptWhitespace(); *indexToken):
    let
      token = &indexToken
      cTok = deepCopy(parser.tokenizer)
      atom = parser.parseAtom(token)

    if !atom:
      parser.tokenizer = cTok
    else:
      if checkForRBracket():
        return some(arrayAccess(ident, &atom))
      # parser.error UnexpectedToken, "expected expression, got " & $token.kind

    if not checkForRBracket():
      return

    case token.kind
    of TokenKind.Identifier:
      return some(arrayAccess(ident, token.ident))
    else:
      # TODO: Get field accesses via strings inside array index expressions working
      parser.error UnexpectedToken, "expected identifier or numeric, got " & $token.kind
  else:
    parser.error Other, "expected expression, got EOF"

proc expectEqualsSign*(
    parser: Parser, stubDef: proc(): Result[Option[Statement], void]
): Result[Option[Statement], void] =
  # FIXME: this is utterly fucking deranged.
  let nextTok = parser.tokenizer.next()
  case nextTok.kind
  of TokenKind.Semicolon:
    return stubDef()
  of TokenKind.EqualSign:
    return ok(none(Statement))
  of TokenKind.Whitespace:
    if isNewline(nextTok):
      return stubDef()
    else:
      expectEqualsSign parser, stubDef
  else:
    parser.error UnexpectedToken,
      "expected semicolon or equal sign after identifier, got " & $nextTok.kind

proc parseTernaryOp*(
    parser: Parser,
    ident: Option[string] = none(string),
    atom: Option[MAtom] = none(MAtom),
): Option[Statement] =
  assert(
    *ident or *atom,
    "BUG: Expected either initial `ident` or `atom` when parsing ternary operation, got neither?",
  )
  debug "parser: parsing ternary operation"
  var tern = Statement(kind: TernaryOp)
  tern.ternaryCond =
    if *ident:
      identHolder(&ident)
    elif *atom:
      atomHolder(&atom)
    else:
      unreachable
      atomHolder(null())

  debug "parser: parsing ternary's true expression"
  # TODO: add support for expressions like x ? (a + b) : (c + d)
  let trueExpr = parser.tokenizer.nextExceptWhitespace()

  if !trueExpr:
    parser.error UnexpectedToken, "expected expression, got EOF instead"

  let trueKind = (&trueExpr).kind
  case trueKind
  of TokenKind.Number, TokenKind.String:
    tern.trueTernary = atomHolder(&parser.parseAtom(&trueExpr))
  of TokenKind.Identifier:
    tern.trueTernary = identHolder((&trueExpr).ident)
  else:
    parser.error UnexpectedToken,
      "expected value or identifier, got " & $trueKind & " instead"

  # expect `:` to separate the two ternaries
  let expectColon = parser.tokenizer.nextExceptWhitespace()
  if !expectColon or (&expectColon).kind != TokenKind.Colon:
    parser.error Other, "missing `:` in ternary expression"

  debug "parser: parsing ternary's false expression"
  let falseExpr = parser.tokenizer.nextExceptWhitespace()

  if !falseExpr:
    parser.error UnexpectedToken, "expected expression, got EOF instead"

  let falseKind = (&falseExpr).kind
  case falseKind
  of TokenKind.Number, TokenKind.String:
    tern.falseTernary = atomHolder(&parser.parseAtom(&falseExpr))
  of TokenKind.Identifier:
    tern.falseTernary = identHolder((&falseExpr).ident)
  else:
    parser.error UnexpectedToken,
      "expected value or identifier, got " & $falseKind & " instead"

  some(tern)

proc parseDeclaration*(
    parser: Parser, initialIdent: string, reassignment: bool = false
): Option[Statement] =
  debug "parser: parse declaration"
  var ident = initialIdent

  if not reassignment:
    while not parser.tokenizer.eof:
      let tok = &parser.tokenizer.nextExceptWhitespace()

      case tok.kind
      of TokenKind.Identifier:
        ident = tok.ident
        break
      of TokenKind.EqualSign:
        break # weird quirky javascript feature :3 (I hate brendan eich)
      of TokenKind.Whitespace:
        continue
      of TokenKind.Number:
        parser.error UnexpectedToken, "numeric literal"
      else:
        parser.error UnexpectedToken, $tok.kind

  proc stubDef(): Result[Option[Statement], void] =
    case initialIdent
    of "let", "const":
      return ok(some(createImmutVal(ident, undefined())))
    of "var":
      return ok(some(createMutVal(ident, undefined())))

  if parser.tokenizer.eof():
    if ident == initialIdent:
      parser.error Other, "identifier not defined"
    else:
      return &stubDef()

    unreachable

  let gotEquals = parser.expectEqualsSign(stubDef)
  if *gotEquals: # what the fuck?
    if *(&gotEquals):
      return &gotEquals
    else:
      discard
  else:
    return

  let
    copiedTok = parser.tokenizer.deepCopy()
    expr = parser.parseExpression(ident.some())

  if !expr:
    debug "parser: no expression was parsed, reverting back to old tokenizer state"
    debug "parser: old (now current) = " & $copiedTok.pos & "; new (now old) = " &
      $parser.tokenizer.pos
    parser.tokenizer = copiedTok
  else:
    debug "parser: an expression was successfully parsed, continuing in this state"
    return expr

  var
    atom: Option[MAtom]
    vIdent: Option[string]
    ternary: Option[Statement]
    toCall: Option[Statement]

  while not parser.tokenizer.eof and !vIdent and !atom and !toCall:
    let tok = parser.tokenizer.next()

    case tok.kind
    of TokenKind.String:
      if (let err = tok.getError(); *err):
        parser.error Other, &err

      atom = some(str tok.str)
      break
    of TokenKind.Identifier:
      if not parser.tokenizer.eof():
        let copiedTok = parser.tokenizer.deepCopy()
        let next = parser.tokenizer.nextExceptWhitespace()
        case (&next).kind
        of TokenKind.LParen:
          # this is a function call!
          toCall = parser.parseFunctionCall(tok.ident)
          break
        of TokenKind.LBracket:
          # array access, probably
          toCall = parser.parseArrayIndex(tok.ident)
          break
        of TokenKind.Question:
          ternary = parser.parseTernaryOp(ident = some(tok.ident))
          break
        else:
          vIdent = some(tok.ident)
          break
    of TokenKind.Number:
      if *tok.intVal:
        atom = some(uinteger uint32(&tok.intVal))
      else:
        atom = some(floating(tok.floatVal))
    of TokenKind.Whitespace:
      discard
    of TokenKind.True:
      atom = some(boolean(true))
    of TokenKind.False:
      atom = some(boolean(false))
    of TokenKind.New:
      toCall = parser.parseConstructor()
      break
    of TokenKind.Typeof:
      toCall = some(
        call("BALI_TYPEOF".callFunction(), &parser.parseTypeofCall(), mangle = false)
      )
      break
    of TokenKind.LBracket:
      atom = parser.parseArray()
      break
    else:
      parser.error UnexpectedToken, $tok.kind

  assert not (*atom and *vIdent and *toCall and *ternary),
    "Attempt to assign a value to nothing (something went wrong)"

  if *ternary:
    var tern = &ternary
    tern.ternaryStoreIn = some(ident)
    return some(tern)

  if not reassignment:
    case initialIdent
    of "let", "const":
      if *atom:
        return some(createImmutVal(ident, &atom))
      elif *vIdent:
        return some(copyValImmut(ident, &vIdent))
      elif *toCall:
        return some(callAndStoreImmut(ident, &toCall))
    of "var":
      if *atom:
        return some(createMutVal(ident, &atom))
      elif *vIdent:
        return some(copyValMut(ident, &vIdent))
      elif *toCall:
        return some(callAndStoreMut(ident, &toCall))
    else:
      parser.error UnexpectedToken, "identifier"
  else:
    if not reassignment:
      if *atom:
        return some(createImmutVal(ident, &atom))
      elif *toCall:
        return some(callAndStoreImmut(ident, &toCall))
    else:
      if *atom:
        return some(createMutVal(ident, &atom))
      elif *toCall:
        return some(callAndStoreMut(ident, &toCall))

proc parseStatement*(parser: Parser): Option[Statement]

proc parseFunction*(parser: Parser): Option[Function] =
  info "parser: parse function"
  var name: Option[string]

  while not parser.tokenizer.eof:
    let tok = parser.tokenizer.next()
    case tok.kind
    of TokenKind.Identifier:
      name = some(tok.ident)
      break
    else:
      discard

  if not *name:
    parser.error Other, "function statement requires a name"

  var
    metLParen = false
    metRParen = false
    arguments: seq[string]

  # TODO: parameter parsing
  while not parser.tokenizer.eof:
    let tok = parser.tokenizer.next()

    case tok.kind
    of TokenKind.LParen:
      info "parser: met left-paren"
      metLParen = true
      continue
    of TokenKind.RParen:
      info "parser: met right-paren"
      metRParen = true

      if not metLParen:
        parser.error Other, "missing ( before formal parameters"
    of TokenKind.LCurly:
      info "parser: met beginning of curly bracket block"

      if not metLParen:
        parser.error Other, "missing ( before start of function scope"

      if not metRParen:
        parser.error Other, "missing ) before start of function scope"

      break
    of TokenKind.Whitespace:
      discard
    of TokenKind.Identifier:
      info "parser: appending identifier to expected function argument signature: " &
        tok.ident
      if metRParen:
        parser.error Other, "unexpected identifier after end of function signature"

      arguments &= tok.ident
    else:
      warn "parser (unimplemented): whilst parsing parameters: "
      print tok
      discard # parameter parser goes here :3

  var body: seq[Statement]
  debug "parser: parse function body: " & &name
  while not parser.tokenizer.eof:
    let
      prevPos = parser.tokenizer.pos
      prevLoc = parser.tokenizer.location
      c = parser.tokenizer.nextExceptWhitespace()

    if *c and (&c).kind == TokenKind.RCurly:
      info "parser: met end of curly bracket block"
      break
    else:
      parser.tokenizer.pos = prevPos
      parser.tokenizer.location = prevLoc

    let stmt = parser.parseStatement()
    if not *stmt:
      debug "parser: can't find any more statements for function body: " & &name &
        "; body parsing complete. Waiting for right-curly bracket to finish block."
      continue

    var statement = &stmt
    statement.line = parser.tokenizer.location.line
    statement.col = parser.tokenizer.location.col

    body &= statement

  info "parser: parsed function: " & &name
  some function(&name, body, arguments)

proc parseAtom*(parser: Parser, token: Token): Option[MAtom] =
  info "parser: trying to parse an atom out of " & $token.kind

  case token.kind
  of TokenKind.Number:
    debug "parser: parseAtom: token is Number"
    if *token.intVal:
      debug "parser: parseAtom: token contains integer value"
      return some integer(&token.intVal)
    else:
      debug "parser: parseAtom: token contains floating-point value"
      return some floating(token.floatVal)
  of TokenKind.String:
    if (let err = token.getError(); *err):
      parser.error Other, &err

    debug "parser: parseAtom: token is String"
    return some str(token.str)
  of TokenKind.True:
    return some boolean(true)
  of TokenKind.False:
    return some boolean(false)
  of TokenKind.LBracket:
    return parser.parseArray()
  else:
    return
    # parser.error UnexpectedToken, "expected value, got " & $token.kind & " instead."

proc parseArguments*(parser: Parser): Option[PositionedArguments] =
  info "parser: parse arguments for function call"
  var
    metEnd = false
    args: PositionedArguments
    idx = -1

  while not parser.tokenizer.eof():
    inc idx
    let copiedTok = deepCopy(parser.tokenizer)

    if (let expr = parser.parseExpression(); *expr):
      debug "parser: whilst parsing arguments in function call, found expression"
      args.pushImmExpr(&expr)
      continue
    else:
      debug "parser: found no expression, reverting tokenizer back to its old state."
      parser.tokenizer = copiedTok

    let token = parser.tokenizer.next()

    case token.kind
    of TokenKind.Whitespace, TokenKind.Comma:
      discard
    of TokenKind.Identifier:
      let
        prevPos = parser.tokenizer.pos
        prevLocation = parser.tokenizer.location

      case parser.tokenizer.next().kind
      of TokenKind.LParen:
        # function!
        let
          call = parser.parseFunctionCall(token.ident)
          resIdent = "@0_" & $idx

        parser.ast.appendToCurrentScope(callAndStoreMut(resIdent, &call))
        args.pushIdent(resIdent)
      else:
        parser.tokenizer.pos = prevPos
        parser.tokenizer.location = prevLocation

        if token.ident.contains('.'):
          # field access!
          let splitted = token.ident.split('.')
          if splitted.len < 2:
            parser.error Other, "expected name after . operator"

          args.pushFieldAccess(createFieldAccess(splitted))
        else:
          args.pushIdent(token.ident)
    of TokenKind.Number, TokenKind.String:
      let atom = parser.parseAtom(token)

      if !atom:
        parser.error Other, "expected atom, got malformed data instead."
          # FIXME: make this less vague!

      args.pushAtom(&atom)
    of TokenKind.True:
      args.pushAtom(boolean(true))
    of TokenKind.False:
      args.pushAtom(boolean(false))
    of TokenKind.RParen:
      metEnd = true
      break
    of TokenKind.New:
      # constructor!
      let
        call = parser.parseConstructor()
        resIdent = "@0_" & $idx

      parser.ast.appendToCurrentScope(callAndStoreMut(resIdent, &call))
      args.pushIdent(resIdent)
    else:
      parser.error UnexpectedToken, $token.kind

  if not metEnd:
    parser.error Other, "missing ) after argument list."

  some args

proc parseThrow*(parser: Parser): Option[Statement] =
  info "parser: parsing throw-expr"

  var
    throwStr: Option[string]
    throwIdent: Option[string]
    throwErr: Option[void] # TODO: implement stuff like `throw new URIError();`

  while not parser.tokenizer.eof:
    let next = parser.tokenizer.next()

    if next.kind == TokenKind.Whitespace and next.isNewline():
      parser.error UnexpectedToken,
        "no line break is allowed between 'throw' and its expression"

    if next.kind == TokenKind.String:
      throwStr = some(next.str)
      break

    if next.kind == TokenKind.Identifier:
      throwIdent = some(next.ident)
      break

  if !throwStr and !throwErr and !throwIdent:
    parser.error Other, "throw statement is missing an expression"

  some(throwError(throwStr, throwErr, throwIdent))

proc parseReassignment*(parser: Parser, ident: string): Option[Statement] =
  info "parser: parsing re-assignment to identifier: " & ident

  var
    atom: Option[MAtom]
    vIdent: Option[string]
    toCall: Option[Statement]

  while not parser.tokenizer.eof and !vIdent and !atom:
    let tok = parser.tokenizer.next()

    case tok.kind
    of TokenKind.String, TokenKind.Number, TokenKind.Null:
      debug "parser: whilst parsing re-assignment, found atom token: " & $tok.kind
      atom = parser.parseAtom(tok)
    of TokenKind.Identifier:
      debug "parser: whilst parsing re-assignment, found identifier: " & tok.ident
      if not parser.tokenizer.eof():
        let copied = parser.tokenizer.deepCopy()
        let next = parser.tokenizer.nextExceptWhitespace()
        if *next and (&next).kind == TokenKind.LParen:
          # this is a function call!
          toCall = parser.parseFunctionCall(tok.ident)
          break
        else:
          parser.tokenizer = copied

      # just an ident copy
      vIdent = some(tok.ident)
      break
    of TokenKind.Whitespace:
      discard
    of TokenKind.New:
      let next = parser.tokenizer.nextExceptWhitespace()

      if !next:
        parser.error UnexpectedToken, "expected Identifier, got EOF"

      if (&next).kind != TokenKind.Identifier:
        parser.error UnexpectedToken, "expected Identifier, got " & $(&next).kind

      if not parser.tokenizer.eof() and parser.tokenizer.next().kind != TokenKind.LParen:
        parser.error Other, "expected left parenthesis when creating object constructor"

      toCall = some(constructObject((&next).ident, &parser.parseArguments()))
      break
    else:
      parser.error UnexpectedToken, $tok.kind

  if *atom:
    return some(reassignVal(ident, &atom))
  elif *vIdent:
    return some(copyValMut(ident, &vIdent))
  elif *toCall:
    return some(callAndStoreMut(ident, &toCall))

proc parseScope*(parser: Parser): seq[Statement] =
  ## Firstly, parse the opening right-facing curly bracket (`{`), and then
  ## add every statement that is parsed to a vector of statements until a left-facing
  ## curly bracket (`}`) is encountered.

  if parser.tokenizer.eof:
    parser.error Other, "expected left curly bracket, got EOF instead"

  if (let tok = parser.tokenizer.nextExceptWhitespace(); *tok):
    if (&tok).kind != TokenKind.LCurly:
      parser.error Other, "expected left curly bracket"

  var stmts: seq[Statement]

  while not parser.tokenizer.eof:
    let
      prevPos = parser.tokenizer.pos
      prevLoc = parser.tokenizer.location
      c = parser.tokenizer.nextExceptWhitespace()

    if *c and (&c).kind == TokenKind.RCurly:
      debug "parser: met end of curly bracket block"
      break
    else:
      parser.tokenizer.pos = prevPos
      parser.tokenizer.location = prevLoc

    let stmt = parser.parseStatement()

    if not *stmt:
      debug "parser: can't find any more statements for scope; body parsing complete"
      break

    var statement = &stmt
    statement.line = parser.tokenizer.location.line
    statement.col = parser.tokenizer.location.col

    stmts &= statement

  stmts

proc parseExprInParenWrap*(parser: Parser, token: TokenKind): Option[Statement] =
  ## Parse an expression that is currently wrapped in parenthesis
  ## like `(x == 32)`. Used when parsing if statements and while loops.
  debug "parser: parsing possible expression in parenthesis wrap for token kind: " &
    $token

  if parser.tokenizer.eof:
    parser.error Other, "expected conditions after control-flow token, got EOF instead"

  if (let tok = parser.tokenizer.nextExceptWhitespace(); *tok):
    if (&tok).kind != TokenKind.LParen:
      parser.error Other, "expected left parenthesis after " & $token & " token"

  let copiedTok = parser.tokenizer.deepCopy()
  var expr = parser.parseExpression()
  if !expr:
    let copiedTokPhase2 = parser.tokenizer.deepCopy()
    parser.tokenizer = copiedTok

    let atom = parser.parseAtom(parser.tokenizer.next())
    if !atom:
      parser.tokenizer = copiedTokPhase2
      parser.error Other, "expected expression, got nothing instead"
    else:
      let holder = atomHolder(&atom)
      expr = some Statement(
        kind: BinaryOp, binLeft: holder, binRight: holder, op: BinaryOperation.Equal
      )

  debug "parser: whilst parsing expression in parenthesis wrap: found expression!"

  if (let tok = parser.tokenizer.nextExceptWhitespace(); *tok):
    if (&tok).kind != TokenKind.RParen:
      parser.error Other,
        "expected right parenthesis after expression, got " & $(&tok).kind

  debug "parser: whilst parsing expression in parenthesis wrap: grammar was satisfied, returning expression"

  expr

proc parseStatement*(parser: Parser): Option[Statement] =
  if parser.tokenizer.eof:
    parser.error Other, "expected statement, got EOF instead."

  let tok = parser.tokenizer.nextExceptWhitespace()

  if !tok:
    return #parser.error Other, "expected statement, got whitespace/EOF instead."

  let token = &tok

  case token.kind
  of TokenKind.Let:
    if token.containsUnicodeEsc:
      parser.error Other, "keyword `let` cannot contain unicode escape(s)"

    info "parser: parse let-expr"
    return parser.parseDeclaration("let")
  of TokenKind.Const:
    if token.containsUnicodeEsc:
      parser.error Other, "keyword `const` cannot contain unicode escape(s)"

    info "parser: parse const-expr"
    return parser.parseDeclaration("const")
  of TokenKind.Var:
    if token.containsUnicodeEsc:
      parser.error Other, "keyword `var` cannot contain unicode escape(s)"

    info "parser: parse var-expr"
    return parser.parseDeclaration("var")
  of TokenKind.Function:
    if token.containsUnicodeEsc:
      parser.error Other, "keyword `function` cannot contain unicode escape(s)"

    info "parser: parse function declaration"
    let fnOpt = parser.parseFunction()

    if !fnOpt:
      parser.error Other, "unexpected end of input"

    var fn = &fnOpt

    var scope = parser.ast.scopes[0]

    while *scope.next:
      scope = &scope.next

    fn.prev = some(scope)
    scope.next = some(Scope(fn))
  of TokenKind.Identifier:
    let
      prevPos = parser.tokenizer.pos
      prevLoc = parser.tokenizer.location

    if not parser.tokenizer.eof():
      let next = parser.tokenizer.nextExceptWhitespace()

      if !next:
        #[ var args: PositionedArguments
        args.pushIdent(token.ident)
        return call(
          fn = callFunction(
            "log",
            createFieldAccess(@["console"])
          ),
          arguments = move(args)
        ).some() ]#
        return waste(token.ident).some()

      case (&next).kind
      of TokenKind.LParen:
        return parser.parseFunctionCall(token.ident) #some call(token.ident, arguments)
      of TokenKind.EqualSign:
        return parser.parseReassignment(token.ident)
      of TokenKind.Increment:
        return some increment(token.ident)
      of TokenKind.Decrement:
        return some decrement(token.ident)
      else:
        parser.error UnexpectedToken,
          "expected left parenthesis, increment, decrement or equal sign, got " &
            $(&next).kind
    else:
      return waste(token.ident).some()

    # parser.tokenizer.pos = prevPos
    # parser.tokenizer.location = prevLoc
  of TokenKind.Return:
    if token.containsUnicodeEsc:
      parser.error Other, "keyword `return` cannot contain unicode escape(s)"

    let
      prevPos = parser.tokenizer.pos
      prevLoc = parser.tokenizer.location

    while not parser.tokenizer.eof():
      let next = parser.tokenizer.next()

      case next.kind
      of TokenKind.Identifier:
        return some returnFunc(next.ident)
      of TokenKind.Number, TokenKind.String:
        return some returnFunc(&parser.parseAtom(next))
      of TokenKind.Whitespace:
        if next.whitespace.contains(strutils.Newlines):
          return some returnFunc()
      else:
        parser.error UnexpectedToken, "expected expression, got " & $next.kind

    parser.tokenizer.pos = prevPos
    parser.tokenizer.location = prevLoc
    return some returnFunc()
  of TokenKind.Throw:
    if token.containsUnicodeEsc:
      parser.error Other, "keyword `throw` cannot contain unicode escape(s)"

    info "parser: parse throw-expr"
    return parser.parseThrow()
  of TokenKind.If:
    if token.containsUnicodeEsc:
      parser.error Other, "keyword `if` cannot contain unicode escape(s)"

    let expr = parser.parseExprInParenWrap(TokenKind.If)
    if !expr:
      return

    # body parsing
    debug "parser: parse if-statement body"
    let body = parser.parseScope()
    var elseBody: seq[Statement]

    if not parser.tokenizer.eof and (
      let nextToken = parser.tokenizer.nextExceptWhitespace()
      *nextToken and (&nextToken).kind == TokenKind.Else
    ): # FIXME: untangle this shitshow
      debug "parser: parse if-statement else-body"
      elseBody = parser.parseScope()

    var lastScope = parser.ast.scopes[parser.ast.currentScope]
    var exprScope = Scope(stmts: body)
    var elseScope = Scope(stmts: elseBody)
    exprScope.prev = some(lastScope)
    elseScope.prev = some(lastScope)

    return some ifStmt(&expr, exprScope, elseScope)
  of TokenKind.While:
    if token.containsUnicodeEsc:
      parser.error Other, "keyword `while` cannot contain unicode escape(s)"

    let expr = parser.parseExprInParenWrap(TokenKind.While)
    if !expr:
      return

    let body = parser.parseScope()
    let lastScope = parser.ast.scopes[parser.ast.currentScope]
    var bodyScope = Scope(stmts: body)

    bodyScope.prev = some(lastScope)
    return some whileStmt(&expr, bodyScope)
  of TokenKind.New:
    if token.containsUnicodeEsc:
      parser.error Other, "keyword `new` cannot contain unicode escape(s)"

    let expr = parser.parseConstructor()
    if !expr:
      parser.error Other, "expected expression for `new`"

    return expr
  of TokenKind.Shebang:
    if parser.foundShebang:
      parser.error Other, "one file cannot have two shebangs"
    else:
      if parser.ast.scopes[parser.ast.currentScope].stmts.len > 0:
        parser.error Other, "shebang must be placed prior to other directives"

      if parser.precededByMultilineComment:
        parser.error Other, "shebang cannot be preceded by multiline comment"

      parser.foundShebang = true
  of TokenKind.Semicolon, TokenKind.Comma:
    discard
  of TokenKind.InvalidShebang:
    parser.error Other, "shebang cannot be preceded by whitespace"
  of TokenKind.Break:
    return some breakStmt()
  of TokenKind.String, TokenKind.Number, TokenKind.Null:
    return some waste(&parser.parseAtom(token))
  of TokenKind.Comment:
    if token.multiline:
      parser.precededByMultilineComment = true

    if parser.opts.test262:
      try:
        yaml.load(token.comment, parser.ast.test262)
      except CatchableError as exc:
        discard
  of TokenKind.Typeof:
    return
      some(call("BALI_TYPEOF".callFunction, &parser.parseTypeofCall(), mangle = false))
  else:
    parser.error UnexpectedToken, "unexpected token: " & $token.kind

proc parse*(parser: Parser): AST {.inline.} =
  parser.ast = newAST()

  while not parser.tokenizer.eof():
    let stmt = parser.parseStatement()

    if *stmt:
      var statement = &stmt
      statement.line = parser.tokenizer.location.line
      statement.col = parser.tokenizer.location.col
      parser.ast.appendToCurrentScope(statement)

  parser.ast.errors = deepCopy(parser.errors)
  parser.ast

proc newParser*(
    input: string, opts: ParserOpts = default(ParserOpts)
): Parser {.inline.} =
  Parser(tokenizer: newTokenizer(input), opts: opts)

{.pop.}
