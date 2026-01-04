## JavaScript parser
##
## Copyright (C) 2024-2026 Trayambak Rai (xtrayambak@disroot.org)

import std/[options, strutils, tables, sequtils]
import bali/grammar/[token, tokenizer, ast, errors, statement]
import pkg/bali/runtime/vm/atom
import pkg/[results, pretty, yaml, shakar]

{.push warning[UnreachableCode]: off.}

type
  ParserOpts* = object
    test262*: bool = false ## Whether to scan for Test262 directives

  TableParsingState* {.pure.} = enum
    Key
    Colon
    Value

  Parser* = ref object
    tokenizer*: Tokenizer
    ast: AST
    lines: seq[string]
    errors*: seq[ParseError]
    opts*: ParserOpts

    precededByMultilineComment: bool = false
    foundShebang: bool = false

template error(parser: Parser, errorKind: ParseErrorKind, msg: string) =
  const inf = instantiationInfo()
  parser.errors &=
    ParseError(kind: errorKind, location: parser.tokenizer.location, message: msg)

  return

func `$`*(error: ParseError): string =
  var buff: string

  case error.kind
  of UnexpectedToken:
    buff &= "unexpected token: " & error.message
  of Other:
    buff &= error.message

  buff & " (line " & $error.location.line & ", column " & $error.location.col & ')'

{.push gcsafe.}
proc parseArguments(parser: Parser): Option[PositionedArguments]

proc parseFunctionCall(parser: Parser, name: string): Option[Statement] =
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

proc parseAtom(parser: Parser, token: Token): Option[Statement]

func tokenToArithBinOp(token: TokenKind): BinaryOperation {.raises: [ValueError].} =
  case token
  of TokenKind.Add:
    BinaryOperation.Add
  of TokenKind.Sub:
    BinaryOperation.Sub
  of TokenKind.Div:
    BinaryOperation.Div
  of TokenKind.Mul:
    BinaryOperation.Mult
  else:
    raise newException(ValueError, "Invalid token for arithmetic operation: " & $token)

proc parseExpression(
    parser: Parser, storeIn: Option[string] = none(string), ignoreTerms: bool = false
): Option[Statement] =
  var term = Statement(kind: BinaryOp, binStoreIn: storeIn)

  template parseRHSExpression(otherRight: Statement) =
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
        parser.tokenizer = ensureMove(copiedTok)

  while not parser.tokenizer.eof and (term.binLeft == nil or term.binRight == nil):
    let next = parser.tokenizer.next()

    case next.kind
    of TokenKind.Number:
      if term.binLeft == nil:
        term.binLeft = &parser.parseAtom(next)
      else:
        term.binRight = &parser.parseAtom(next)
    of TokenKind.String:
      if (let err = next.getError(); *err):
        parser.error Other, &err

      if term.binLeft == nil:
        term.binLeft = &parser.parseAtom(next)
      else:
        term.binRight = &parser.parseAtom(next)
    of TokenKind.Identifier:
      if term.binLeft == nil:
        term.binLeft = identHolder(next.ident)
      else:
        term.binRight = identHolder(next.ident)
    of TokenKind.Add:
      term.op = BinaryOperation.Add
    of TokenKind.Sub:
      term.op = BinaryOperation.Sub
    of TokenKind.Mul:
      term.op = BinaryOperation.Mult
    of TokenKind.Div:
      term.op = BinaryOperation.Div
    of TokenKind.Equal:
      term.op = BinaryOperation.Equal
    of TokenKind.TrueEqual:
      term.op = BinaryOperation.TrueEqual
    of TokenKind.GreaterThan:
      term.op = BinaryOperation.GreaterThan
    of TokenKind.GreaterEqual:
      term.op = BinaryOperation.GreaterOrEqual
    of TokenKind.LessThan:
      term.op = BinaryOperation.LesserThan
    of TokenKind.LessEqual:
      term.op = BinaryOperation.LesserOrEqual
    of TokenKind.NotEqual:
      term.op = BinaryOperation.NotEqual
    of TokenKind.Whitespace:
      if next.isNewline():
        break
    of TokenKind.LParen:
      if term.op == BinaryOperation.Invalid:
        return

      let expr = parser.parseExpression()
      if !expr:
        return
        # parser.error Other, "failed to parse expression"

      term.binRight = &expr
    of TokenKind.RParen:
      parser.tokenizer.pos -= 1
      break
    of TokenKind.True:
      if term.binLeft == nil:
        term.binLeft = atomHolder(stackBoolean(true))
      else:
        parseRHSExpression(atomHolder(stackBoolean(true)))
        term.binRight = atomHolder(stackBoolean(true))
    of TokenKind.False:
      if term.binLeft == nil:
        term.binLeft = atomHolder(stackBoolean(false))
      else:
        term.binRight = atomHolder(stackBoolean(false))
    of TokenKind.Comment:
      discard
    else:
      return

  #[ if term.binRight == nil:
    term.op = BinaryOperation.Equal
    term.binRight = atomHolder(boolean(true)) # TODO: is this the right thing to do in this case? ]#

  if not parser.tokenizer.eof:
    # Look ahead for any remaining bits
    let copied = parser.tokenizer.pos
    let tok = parser.tokenizer.nextExceptWhitespace()

    # TODO: Handle parentheses too
    if *tok and
        (&tok).kind in {TokenKind.Add, TokenKind.Sub, TokenKind.Div, TokenKind.Mul}:
      let expr = parser.parseExpression(ignoreTerms = true)
      if !expr:
        parser.error Other, "expected valid expression after " & $(&tok).kind

      term.binRight = Statement(
        kind: BinaryOp,
        op: tokenToArithBinOp((&tok).kind),
        binLeft: term.binRight,
        binRight: &expr,
      )
    else:
      parser.tokenizer.pos = copied

  if ignoreTerms:
    return some term

  if term.binLeft != nil and term.binRight != nil:
    return some term
  else:
    return
    #parser.error Other, "expected left term and right term to complete expression"

proc parseConstructor(parser: Parser): Option[Statement] =
  let next = parser.tokenizer.nextExceptWhitespace()

  if !next:
    parser.error UnexpectedToken, "expected Identifier, got EOF"

  if (&next).kind != TokenKind.Identifier:
    parser.error UnexpectedToken, "expected Identifier, got " & $(&next).kind

  if parser.tokenizer.eof or parser.tokenizer.next().kind != TokenKind.LParen:
    return some(constructObject((&next).ident, @[]))

  return some(constructObject((&next).ident, &parser.parseArguments()))

proc parseTypeofCall(parser: Parser): Option[PositionedArguments] =
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

      args.pushImmExpr(&atom)

  if mustEndWithParen and not metParen:
    parser.error Other, "missing ) in parenthetical"

  some(args)

#[
proc parseTable(parser: Parser): Option[MAtom] =
  # We are assuming that the starting curly bracket (`{`) has been consumed.
  if parser.tokenizer.eof:
    parser.error Other, "expected expression, got EOF"

  var
    table: seq[(MAtom, MAtom)]
    currentKey: MAtom

    metRCurly = false
    state = TableParsingState.Key

  while not parser.tokenizer.eof and not metRCurly:
    let token = parser.tokenizer.next()

    case state
    of TableParsingState.Key:
      let key =
        case token.kind
        of TokenKind.Identifier:
          stackStr(token.ident)
        of TokenKind.String:
          stackStr(token.str)
        of TokenKind.Number:
          &parser.parseAtom(token)
        of TokenKind.RCurly:
          metRCurly = true
          break
          stackNull()
        of TokenKind.Whitespace:
          continue
          stackNull()
        else:
          parser.error UnexpectedToken, $token.kind & " (expected identifier or string)"

      table.add((key, stackNull()))
      currentKey = key
      state = TableParsingState.Colon
    of TableParsingState.Colon:
      case token.kind
      of TokenKind.Colon:
        state = TableParsingState.Value
      of TokenKind.Whitespace:
        discard
      else:
        parser.error Other,
          "expected Colon after property id, got " & $token.kind & " instead"
    of TableParsingState.Value:
      case token.kind
      of TokenKind.Identifier:
        parser.error Other, "identifiers are not supported in maps yet"
      of TokenKind.Whitespace:
        discard
      else:
        let atom = parser.parseAtom(token)
        if !atom:
          parser.error UnexpectedToken, "expected value, got " & $token.kind

        table &= (currentKey, &atom)
        state = TableParsingState.Key

  if not metRCurly:
    parser.error Other, "property list must be ended by }"
]#

proc parseArray(parser: Parser): Option[Statement] =
  # We are assuming that the starting bracket (`[`) has been consumed.
  if parser.tokenizer.eof:
    parser.error Other, "expected expression, got EOF"

  var
    arr: MixedLiteralChildren
    prev = TokenKind.LBracket
    metRBracket = false

  while not parser.tokenizer.eof and not metRBracket:
    let token = parser.tokenizer.next()
    if token.kind == TokenKind.Whitespace:
      continue

    if token.kind == TokenKind.RBracket:
      metRBracket = true
      break

    if token.kind == TokenKind.Comma:
      if prev in {TokenKind.LBracket, TokenKind.Comma}:
        prev = TokenKind.Comma
        arr &= atomHolder(stackUndefined())
      else:
        prev = TokenKind.Comma

      continue

    if token.kind == TokenKind.Comment:
      continue

    if token.kind == TokenKind.Identifier:
      arr &= identHolder(token.ident)
    else:
      let atom = parser.parseAtom(token)
      if !atom:
        parser.error UnexpectedToken,
          "expected expression, value or name, got " & $token.kind & " instead."

      arr &= &atom

    # Just a check to see if the next token is valid.
    # From valid, according to the grammar rules, it can only be two tokens:
    # `,` and `]` to add another element and to close off the parsing algorithm
    # respectively.
    var copiedTok = deepCopy(parser.tokenizer)
    while not parser.tokenizer.eof:
      if (let tok = parser.tokenizer.nextExceptWhitespace(); *tok):
        let kind = (&tok).kind
        if kind == TokenKind.Comment:
          continue

        if kind notin {TokenKind.Comma, TokenKind.RBracket}:
          parser.error UnexpectedToken,
            "expected comma (,) or right bracket (]) after array element, got " & $kind
        else:
          parser.tokenizer = ensureMove(copiedTok)
          break
      else:
        parser.error Other, "missing ] after element list"

    prev = token.kind

  if not metRBracket:
    parser.error Other, "array is not closed off by bracket"

  some createArrayLiteral(arr)

proc parseArrayIndex(parser: Parser, ident: string): Option[Statement] =
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

proc expectEqualsSign(
    parser: Parser, stubDef: proc(): Result[Option[Statement], void] {.gcsafe.}
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

proc parseTernaryOp(
    parser: Parser,
    ident: Option[string] = none(string),
    atom: Option[MAtom] = none(MAtom),
): Option[Statement] =
  assert(
    *ident or *atom,
    "BUG: Expected either initial `ident` or `atom` when parsing ternary operation, got neither?",
  )
  var tern = Statement(kind: TernaryOp)
  tern.ternaryCond =
    if *ident:
      identHolder(&ident)
    elif *atom:
      atomHolder(&atom)
    else:
      unreachable
      atomHolder(stackNull())

  # TODO: add support for expressions like x ? (a + b) : (c + d)
  let trueExpr = parser.tokenizer.nextExceptWhitespace()

  if !trueExpr:
    parser.error UnexpectedToken, "expected expression, got EOF instead"

  let trueKind = (&trueExpr).kind
  case trueKind
  of TokenKind.Number, TokenKind.String:
    tern.trueTernary = &parser.parseAtom(&trueExpr)
  of TokenKind.Identifier:
    tern.trueTernary = identHolder((&trueExpr).ident)
  else:
    parser.error UnexpectedToken,
      "expected value or identifier, got " & $trueKind & " instead"

  # expect `:` to separate the two ternaries
  let expectColon = parser.tokenizer.nextExceptWhitespace()
  if !expectColon or (&expectColon).kind != TokenKind.Colon:
    parser.error Other, "missing `:` in ternary expression"

  let falseExpr = parser.tokenizer.nextExceptWhitespace()

  if !falseExpr:
    parser.error UnexpectedToken, "expected expression, got EOF instead"

  let falseKind = (&falseExpr).kind
  case falseKind
  of TokenKind.Number, TokenKind.String:
    tern.falseTernary = &parser.parseAtom(&falseExpr)
  of TokenKind.Identifier:
    tern.falseTernary = identHolder((&falseExpr).ident)
  else:
    parser.error UnexpectedToken,
      "expected value or identifier, got " & $falseKind & " instead"

  some(tern)

proc parseFunction(
  parser: Parser, name: Option[string] = none(string)
): Option[Function]

proc parseDeclaration(
    parser: Parser, initialIdent: string, reassignment: bool = false
): Option[Statement] =
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
      return ok(some(createImmutVal(ident, stackUndefined())))
    of "var":
      return ok(some(createMutVal(ident, stackUndefined())))

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
    parser.tokenizer = copiedTok
  else:
    return expr

  var
    atom: Option[MAtom]
    vIdent: Option[string]
    ternary: Option[Statement]
    toCall: Option[Statement]
    declareFn: Option[Function]

  while not parser.tokenizer.eof and !vIdent and !atom and !toCall:
    let tok = parser.tokenizer.next()

    case tok.kind
    of TokenKind.String:
      if (let err = tok.getError(); *err):
        parser.error Other, &err

      atom = some(stackStr tok.str)
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
        atom = some(stackInteger(&tok.intVal))
      else:
        atom = some(stackFloating(tok.floatVal))
    of TokenKind.Whitespace:
      discard
    of TokenKind.True:
      atom = some(stackBoolean(true))
    of TokenKind.False:
      atom = some(stackBoolean(false))
    of TokenKind.New:
      toCall = parser.parseConstructor()
      break
    of TokenKind.Typeof:
      toCall = some(
        call("BALI_TYPEOF".callFunction(), &parser.parseTypeofCall(), mangle = false)
      )
      break
    of TokenKind.LBracket:
      ternary = parser.parseArray()
      break
    # FIXME: Make table parsing work again
    #
    # of TokenKind.LCurly:
    #  atom = parser.parseTable()
    #  break
    of TokenKind.Function:
      let fn = parser.parseFunction(name = some(ident))
      declareFn = fn
    of TokenKind.Semicolon:
      if (!atom and !vIdent and !toCall and !ternary and !declareFn):
        parser.error UnexpectedToken, "expected value, got semicolon instead"

      break
    else:
      parser.error UnexpectedToken, $tok.kind

  assert not (*atom and *vIdent and *toCall and *ternary and *declareFn),
    "Attempt to assign a value to nothing (something went wrong)"

  if *ternary:
    var tern = &ternary
    tern.storeIn = some(ident)
    return some(tern)

  if *declareFn:
    return
      some(defineFunction(&declareFn, some(parser.ast.scopes[parser.ast.currentScope])))

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

proc parseStatement(parser: Parser): Option[Statement]

proc parseFunction(
    parser: Parser, name: Option[string] = none(string)
): Option[Function] =
  let nameOpt = name
  var name: Option[string]

  if !nameOpt:
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
  else:
    name = nameOpt

  var
    metLParen = false
    metRParen = false
    arguments: seq[string]

  # TODO: parameter parsing
  var last: Option[TokenKind]
  while not parser.tokenizer.eof:
    let tok = parser.tokenizer.next()

    case tok.kind
    of TokenKind.LParen:
      metLParen = true
      last = some(TokenKind.LParen)
      continue
    of TokenKind.RParen:
      metRParen = true

      if not metLParen:
        parser.error Other, "missing ( before formal parameters"

      last = some(TokenKind.RParen)
    of TokenKind.LCurly:
      if not metLParen:
        parser.error Other, "missing ( before start of function scope"

      if not metRParen:
        parser.error Other, "missing ) before start of function scope"

      break
    of TokenKind.Whitespace:
      last = some(TokenKind.Whitespace)
    of TokenKind.Identifier:
      if metRParen:
        parser.error Other, "unexpected identifier after end of function signature"

      # If the identifier is not preceded by:
      # - Commas
      # - Whitespace 
      # - Left parenthesis
      # Then raise a parsing error
      # Example of erroneous sample this will catch:
      # function x(a b c) { }
      #            ^^^^^ It should be (a, b, c)
      if *last and &last notin {TokenKind.Comma, TokenKind.Whitespace, TokenKind.LParen}:
        parser.error Other, "unexpected identifier after " & $(&last)

      arguments &= tok.ident
      last = some(TokenKind.Identifier)
    of TokenKind.Comma:
      if !last:
        parser.error Other, "expected identifier for parameter name, got comma instead."

      if &last == TokenKind.Comma:
        parser.error UnexpectedToken, "expected identifier, got Comma instead"

      last = some(TokenKind.Comma)
    else:
      print tok
      discard # parameter parser goes here :3

  var body: seq[Statement]
  var metRCurly = false
  while not parser.tokenizer.eof:
    let
      prevPos = parser.tokenizer.pos
      prevLoc = parser.tokenizer.location
      c = parser.tokenizer.nextExceptWhitespace()

    if *c and (&c).kind == TokenKind.RCurly:
      metRCurly = true
      break
    else:
      parser.tokenizer.pos = prevPos
      parser.tokenizer.location = prevLoc

    let stmt = parser.parseStatement()
    if not *stmt:
      continue

    var statement = &stmt
    statement.line = parser.tokenizer.location.line
    statement.col = parser.tokenizer.location.col

    body &= statement

  if not metRCurly:
    parser.error Other, "function body must end with curly bracket"

  some function(&name, body, arguments)

proc parseAtom(parser: Parser, token: Token): Option[Statement] =
  case token.kind
  of TokenKind.Number:
    #[ if *token.intVal:
      return some stackInteger(&token.intVal)
    else:
      return some stackFloating(token.floatVal) ]#
    return some atomHolder(stackFloating(token.floatVal))
  of TokenKind.String:
    if (let err = token.getError(); *err):
      parser.error Other, &err

    return some atomHolder stackStr(token.str)
  of TokenKind.True:
    return some atomHolder stackBoolean(true)
  of TokenKind.False:
    return some atomHolder stackBoolean(false)
  of TokenKind.LBracket:
    return parser.parseArray()
  # FIXME: Make table parsing work again
  #
  # of TokenKind.LCurly:
  # return parser.parseTable()
  else:
    return
    # parser.error UnexpectedToken, "expected value, got " & $token.kind & " instead."

proc parseArguments(parser: Parser): Option[PositionedArguments] =
  var
    metEnd = false
    args: PositionedArguments
    idx = -1
    last: Option[TokenKind]
    lastData: Option[Token]

  while not parser.tokenizer.eof and not metEnd:
    inc idx
    let copiedTok = deepCopy(parser.tokenizer)

    if (let expr = parser.parseExpression(); *expr):
      args.pushImmExpr(&expr)
      continue
    else:
      parser.tokenizer = copiedTok

    let token = parser.tokenizer.next()

    case token.kind
    of TokenKind.Whitespace:
      discard
    of TokenKind.Comma:
      if *last and &last == TokenKind.Comma:
        parser.error UnexpectedToken,
          "expected identifier, value or right parenthesis after comma, got another comma instead."

      last = some(TokenKind.Comma)
    of TokenKind.Identifier:
      last = some(TokenKind.Identifier)
      lastData = some(token)
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
    of TokenKind.Number, TokenKind.String, TokenKind.LParen, TokenKind.LCurly:
      last = some(token.kind)
      let atom = parser.parseAtom(token)

      if !atom:
        parser.error Other, "expected atom, got malformed data instead."
          # FIXME: make this less vague!

      args.pushImmExpr(&atom)
    of TokenKind.True:
      last = some(TokenKind.True)
      args.pushAtom(stackBoolean(true))
    of TokenKind.False:
      last = some(TokenKind.False)
      args.pushAtom(stackBoolean(false))
    of TokenKind.RParen:
      last = some(TokenKind.RParen)
      metEnd = true
    of TokenKind.New:
      last = some(TokenKind.New)
      # constructor!
      let
        call = parser.parseConstructor()
        resIdent = "@0_" & $idx

      parser.ast.appendToCurrentScope(callAndStoreMut(resIdent, &call))
      args.pushIdent(resIdent)
    of TokenKind.LBracket:
      if !last or &last != TokenKind.Identifier:
        # If there was no identifier immediately preceding this, we're at an array literal
        let arr = parser.parseArray()
        if !arr:
          parser.error Other, "got malformed array while parsing arguments"

        args.pushImmExpr(&arr)
      else:
        # Else, we're at an array index.
        let access = parser.parseArrayIndex((&lastData).ident)
        if !access:
          parser.error Other, "got malformed array indexing while parsing arguments"

        discard
          args.pop() # We should remove the last argument, it was accidentally added in.
        args.pushImmExpr(&access)
    else:
      parser.error UnexpectedToken, $token.kind

  if not metEnd:
    parser.error Other, "missing ) after argument list."

  some args

proc parseThrow(parser: Parser): Option[Statement] =
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

  var stmt = throwError(throwStr, throwErr, throwIdent)
  stmt.source = parser.lines[parser.tokenizer.location.line]

  some(ensureMove(stmt))

proc parseReassignment(parser: Parser, ident: string): Option[Statement] =
  var expr: Option[Statement]

  if not parser.tokenizer.eof:
    let copiedTok = parser.tokenizer.deepCopy()
    expr = parser.parseExpression()

    if !expr:
      parser.tokenizer = copiedTok
    else:
      expr.applyThis:
        this.binStoreIn = some(ident)
        this.source = parser.lines[copiedTok.location.line]

      return expr

  var
    atom: Option[Statement]
    vIdent: Option[string]
    toCall: Option[Statement]

  while not parser.tokenizer.eof and !vIdent and !atom:
    let tok = parser.tokenizer.next()

    case tok.kind
    of TokenKind.String, TokenKind.Number, TokenKind.Null:
      atom = parser.parseAtom(tok)
    of TokenKind.Identifier:
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
    var reassignExpr = reassignVal(ident, &atom)
    reassignExpr.source = parser.lines[parser.tokenizer.location.line]

    return some(ensureMove(reassignExpr))
  elif *vIdent:
    var copyExpr = copyValMut(ident, &vIdent)
    copyExpr.source = parser.lines[parser.tokenizer.location.line]

    return some(ensureMove(copyExpr))
  elif *toCall:
    var callStoreExpr = callAndStoreMut(ident, &toCall)
    callStoreExpr.source = parser.lines[parser.tokenizer.location.line]

    return some(ensureMove(callStoreExpr))

proc parseScope(parser: Parser): seq[Statement] =
  ## Firstly, parse the opening right-facing curly bracket (`{`), and then
  ## add every statement that is parsed to a vector of statements until a left-facing
  ## curly bracket (`}`) is encountered.

  if parser.tokenizer.eof:
    parser.error Other, "expected left curly bracket, got EOF instead"

  let ephTok = deepCopy(parser.tokenizer)
  var singleExpr = false
  if (let tok = parser.tokenizer.nextExceptWhitespace(); *tok):
    if (&tok).kind != TokenKind.LCurly:
      # This is likely a single expression for the body
      singleExpr = true
      parser.tokenizer = ephTok

  inc parser.ast.currentScope
  parser.ast.scopes.setLen(parser.ast.currentScope + 1)
  parser.ast.scopes[parser.ast.currentScope] = Scope()
  var stmts: seq[Statement]
  var metRCurly = false

  while not parser.tokenizer.eof:
    if not singleExpr:
      let
        prevPos = parser.tokenizer.pos
        prevLoc = parser.tokenizer.location
        c = parser.tokenizer.nextExceptWhitespace()

      if *c and (&c).kind == TokenKind.RCurly:
        metRCurly = true
        break
      else:
        parser.tokenizer.pos = prevPos
        parser.tokenizer.location = prevLoc

    let stmt = parser.parseStatement()

    if not *stmt:
      continue

    var statement = &stmt
    statement.line = parser.tokenizer.location.line
    statement.col = parser.tokenizer.location.col
    statement.source = parser.lines[parser.tokenizer.location.line]

    stmts &= statement

    if singleExpr:
      break

  dec parser.ast.currentScope

  if not metRCurly and not singleExpr:
    parser.error Other, "scope body must end with curly bracket"

  stmts

proc parseExprInParenWrap(parser: Parser, token: TokenKind): Option[Statement] =
  ## Parse an expression that is currently wrapped in parenthesis
  ## like `(x == 32)`. Used when parsing if statements and while loops.

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
      let holder = &atom
      expr = some Statement(
        kind: BinaryOp, binLeft: holder, binRight: holder, op: BinaryOperation.Equal
      )

  if (let tok = parser.tokenizer.nextExceptWhitespace(); *tok):
    if (&tok).kind != TokenKind.RParen:
      parser.error Other,
        "expected right parenthesis after expression, got " & $(&tok).kind

  expr

proc parseForLoop(parser: Parser): Option[Statement] =
  ## Parse a for-loop expression.
  ## **Basic Rules**
  ##
  ## for (< initializer >; < condition >; < incrementer >) { < body > }
  ##
  ## - We're assuming that the `for` token has already been hit.
  template expectSemicolon(section: string) =
    let sectionEndingSemicolon = parser.tokenizer.nextExceptWhitespace()
    if !sectionEndingSemicolon:
      parser.error Other, "expected semicolon after " & section & ", got EOF."

    if (&sectionEndingSemicolon).kind != TokenKind.Semicolon:
      parser.error UnexpectedToken,
        "expected semicolon after " & section & ", got " &
          $(&sectionEndingSemicolon).kind

  # Verify that we're heading towards a parenthesis
  let parenTok = parser.tokenizer.nextExceptWhitespace()
  if !parenTok:
    parser.error Other, "expected left facing parenthesis, got EOF instead."

  if (&parenTok).kind != TokenKind.LParen:
    parser.error UnexpectedToken,
      "expected left facing parenthesis, got " & $(&parenTok).kind

  # Now, parse the next statement you can see.
  # This is the initializer.
  # Revert back if there's nothing.
  var copiedTok = parser.tokenizer.deepCopy()
  let initializer = parser.parseStatement()
  if !initializer:
    parser.tokenizer = ensureMove(copiedTok)

  # Now, expect a semicolon.
  expectSemicolon "initializer"

  # Now, parse the next statement you can see.
  # This is the condition.
  # Revert back if there's nothing.
  copiedTok = parser.tokenizer.deepCopy()
  let condition = parser.parseExpression()
  if !condition:
    parser.tokenizer = ensureMove(copiedTok)

  # Now, expect a semicolon
  expectSemicolon "conditional"

  # Now, parse the next statement you can see.
  # This is the incrementor.
  # Revert back if there's nothing.
  copiedTok = parser.tokenizer.deepCopy()
  let incrementor = parser.parseStatement()
  if !incrementor:
    parser.tokenizer = ensureMove(copiedTok)

  # Now, parse the n- just kidding
  # Expect left parenthesis
  let endingParen = parser.tokenizer.nextExceptWhitespace()
  if !endingParen:
    parser.error Other,
      "expected right facing parenthesis to close for-expression, got EOF."

  if (&endingParen).kind != TokenKind.RParen:
    parser.error UnexpectedToken,
      "expected right facing parenthesis to close for-expression, got " &
        $(&endingParen).kind

  let body = Scope(stmts: parser.parseScope())

  return some(forLoop(initializer, condition, incrementor, body))

proc parseTryClause(parser: Parser): Option[Statement] =
  ## Parse a try-catch clause.
  var statement = Statement(kind: TryCatch)
  statement.tryStmtBody = Scope(stmts: parser.parseScope())
  statement.source = parser.lines[parser.tokenizer.location.line]

  let copied = parser.tokenizer.deepCopy()

  if not copied.eof and
      (let tok = copied.nextExceptWhitespace(); *tok and (&tok).kind == TokenKind.Catch):
    # There's a catch clause.
    parser.tokenizer = copied

    let copiedParen = parser.tokenizer.deepCopy()
    if not copiedParen.eof and (
      let paren = copiedParen.nextExceptWhitespace()
      *paren and (&paren).kind == TokenKind.LParen
    ):
      parser.tokenizer = copiedParen
      let ident = parser.tokenizer.consumeIdentifier()
        # The identifier into which we can capture the error value into
      statement.tryErrorCaptureIdent = some(ident.ident)

      if not parser.tokenizer.eof and
          (let endingParen = parser.tokenizer.nextExceptWhitespace(); *endingParen):
        if (&endingParen).kind != TokenKind.RParen:
          parser.error UnexpectedToken,
            "expected right parenthesis, got " & $((&endingParen).kind)
      else:
        parser.error Other, "expected right parenthesis after identifier, got EOF."

    statement.tryCatchBody = some(Scope(stmts: parser.parseScope()))

  some(ensureMove(statement))

proc parseCompoundAssignment(
    parser: Parser, target: string, compound: Token
): Option[Statement] =
  if parser.tokenizer.eof:
    parser.error Other,
      "expected equal-sign to start compound assignment, got EOF instead."

  let expEquals = parser.tokenizer.next()
  if expEquals.kind != TokenKind.EqualSign:
    parser.error Other,
      "expected equal-sign to start compound assignment, got " & $expEquals.kind &
        " instead."

  let copiedTok = parser.tokenizer.deepCopy()
  let expr = parser.parseExpression()
  var atom: Option[Statement]
  var identifier: Option[string]

  if !expr:
    parser.tokenizer = copiedTok

    let next = &parser.tokenizer.nextExceptWhitespace()

    case next.kind
    of TokenKind.Identifier:
      identifier = some(next.ident)
    else:
      # FIXME: Make this a more concrete
      # set of TokenKind(s) instead of just an else.
      atom = parser.parseAtom(next)

  if *expr:
    parser.error Other, "Compound assignment with expressions is not supported yet"

  var binOp: BinaryOperation
  case compound.kind
  of TokenKind.Mul:
    # <target> *= <expr>|<atom>
    binOp = BinaryOperation.Mult
  of TokenKind.Add:
    # <target> += <expr>|<atom>
    binOp = BinaryOperation.Add
  of TokenKind.Sub:
    binOp = BinaryOperation.Sub
  of TokenKind.Div:
    binOp = BinaryOperation.Div
  else:
    parser.error UnexpectedToken,
      "expected multiplication, addition, subtraction or division as compound, got " &
        $compound.kind & " instead"

  if *atom:
    var asgnExpr = compoundAssignment(binOp, target = target, compounder = &atom)
    asgnExpr.source = parser.lines[parser.tokenizer.location.line]

    return some(ensureMove(asgnExpr))
  elif *identifier:
    var asgnExpr = compoundAssignment(binOp, target = target, compounder = &identifier)
    asgnExpr.source = parser.lines[parser.tokenizer.location.line]

    return some(ensureMove(asgnExpr))
  else:
    parser.error Other,
      "expected expression, literal or identifier after compound assignment"

proc parseStatement(parser: Parser): Option[Statement] =
  if parser.tokenizer.eof:
    return

  let tok = parser.tokenizer.nextExceptWhitespace()
  if !tok:
    return #parser.error Other, "expected statement, got whitespace/EOF instead."

  let token = &tok

  # TODO: decrease the cyclomatic complexity here.
  case token.kind
  of TokenKind.Let:
    if token.containsUnicodeEsc:
      parser.error Other, "keyword `let` cannot contain unicode escape(s)"

    return parser.parseDeclaration("let")
  of TokenKind.Const:
    if token.containsUnicodeEsc:
      parser.error Other, "keyword `const` cannot contain unicode escape(s)"

    return parser.parseDeclaration("const")
  of TokenKind.Var:
    if token.containsUnicodeEsc:
      parser.error Other, "keyword `var` cannot contain unicode escape(s)"

    return parser.parseDeclaration("var")
  of TokenKind.Function:
    if token.containsUnicodeEsc:
      parser.error Other, "keyword `function` cannot contain unicode escape(s)"

    let fnOpt = parser.parseFunction()

    if !fnOpt:
      parser.error Other, "unexpected end of input"

    var fn = &fnOpt

    var scope = parser.ast.scopes[parser.ast.currentScope]

    fn.prev = some(scope)
    scope.children &= Scope(fn)

    parser.ast.scopes[parser.ast.currentScope] = ensureMove(scope)
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
      of TokenKind.Mul, TokenKind.Add, TokenKind.Sub, TokenKind.Div:
        return parser.parseCompoundAssignment(token.ident, &next)
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
      let copied = deepCopy(parser.tokenizer)
      if (let expr = parser.parseExpression(); *expr):
        return some returnFunc(&expr)
      else:
        parser.tokenizer = copied

      case next.kind
      of TokenKind.Identifier:
        return some returnFunc(next.ident)
      of TokenKind.Number, TokenKind.String, TokenKind.True, TokenKind.False:
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

    return parser.parseThrow()
  of TokenKind.If:
    if token.containsUnicodeEsc:
      parser.error Other, "keyword `if` cannot contain unicode escape(s)"

    let expr = parser.parseExprInParenWrap(TokenKind.If)
    if !expr:
      return

    # body parsing
    let body = parser.parseScope()
    var elseBody: seq[Statement]

    if not parser.tokenizer.eof and (
      let nextToken = parser.tokenizer.nextExceptWhitespace()
      *nextToken and (&nextToken).kind == TokenKind.Else
    ): # FIXME: untangle this shitshow
      elseBody = parser.parseScope()

    var lastScope = parser.ast.scopes[parser.ast.currentScope]
    var exprScope =
      Scope(stmts: parser.ast.scopes[parser.ast.currentScope + 1].stmts & body)
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
    var bodyScope =
      Scope(stmts: parser.ast.scopes[parser.ast.currentScope + 1].stmts & body)

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
    if token.containsUnicodeEsc:
      parser.error Other, "keyword `break` cannot contain unicode escape(s)."

    return some breakStmt()
  of TokenKind.String, TokenKind.Number, TokenKind.Null, TokenKind.LBracket,
      TokenKind.LCurly:
    let atom = parser.parseAtom(token)

    return atom
  of TokenKind.Comment:
    if token.multiline:
      parser.precededByMultilineComment = true

    if parser.opts.test262:
      try:
        # TODO: Verify that nim-yaml is actually gcsafe.
        {.cast(gcsafe).}:
          yaml.load(token.comment, parser.ast.test262)
      except CatchableError as exc:
        discard
  of TokenKind.Typeof:
    return
      some(call("BALI_TYPEOF".callFunction, &parser.parseTypeofCall(), mangle = false))
  of TokenKind.For:
    return parser.parseForLoop()
  of TokenKind.Try:
    return parser.parseTryClause()
  else:
    parser.error UnexpectedToken, $token.kind

proc parse*(parser: Parser): AST {.inline.} =
  ## This routine parses the entire source file provided to the
  ## `parser` object and outputs an abstract syntax tree representation
  ## of the JavaScript code, as well as syntax errors if there are any.
  parser.ast = newAST()
  parser.lines = parser.tokenizer.source.split('\n').mapIt(it.strip(trailing = false))

  while not parser.tokenizer.eof():
    let stmt = parser.parseStatement()

    if *stmt:
      var statement = &stmt
      statement.line = parser.tokenizer.location.line
      statement.col = parser.tokenizer.location.col

      if parser.lines.len.uint > statement.line:
        # FIXME: how is this even possible?
        # fix the darned tokenizer...
        statement.source = parser.lines[statement.line]

      case statement.kind
      of WhileStmt, IfStmt, ForLoop:
        parser.ast.scopes.delete(parser.ast.currentScope + 1)
      else:
        discard

      parser.ast.appendToCurrentScope(statement)

  parser.ast.errors = deepCopy(parser.errors)
  parser.ast

{.pop.}

func newParser*(
    input: string, opts: ParserOpts = default(ParserOpts)
): Parser {.inline.} =
  ## This routine creates a new `Parser` object and returns it based
  ## off of the `input` string buffer, and optionally the `opts` struct
  ## that can be used to guide the parser in certain ways.
  Parser(tokenizer: newTokenizer(input), opts: opts)

{.pop.}
