## JavaScript parser
##
## Copyright (C) 2024 Trayambak Rai

import std/[options, logging, strutils, tables]
import bali/grammar/[token, tokenizer, ast, statement]
import bali/internal/sugar
import mirage/atom
import pretty

type
  ParseErrorKind* = enum
    UnexpectedToken
    Other

  ParseError* = object
    location*: SourceLocation
    kind*: ParseErrorKind = Other
    message*: string

  SyntaxError* = object of CatchableError

  Parser* = ref object
    tokenizer*: Tokenizer
    ast: AST
    errors*: seq[ParseError]

template error(parser: Parser, kind: ParseErrorKind, msg: string) =
  parser.errors &=
    ParseError(location: parser.tokenizer.location, message: msg)
  
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
    arguments = if *args: &args else: newSeq[CallArg](0)
  
  return some call(name, arguments)

proc parseDeclaration*(parser: Parser, initialIdent: string): Option[Statement] =
  var ident = initialIdent

  while not parser.tokenizer.eof:
    let tok = parser.tokenizer.next()

    case tok.kind
    of TokenKind.Identifier:
      ident = tok.ident
    of TokenKind.EqualSign:
      break # weird quirky javascript feature :3 (I hate brendan eich)
    of TokenKind.Whitespace: continue
    else:
      parser.error UnexpectedToken, "numeric literal"
  
  var
    atom: Option[MAtom]
    vIdent: Option[string]
    toCall: Option[Statement]

  while not parser.tokenizer.eof:
    let tok = parser.tokenizer.next()
    
    case tok.kind
    of TokenKind.String:
      if tok.malformed:
        error Other, "string literal contains an unescaped line break"

      atom = some(
        str tok.str
      )
      break
    of TokenKind.Identifier:
      let prevPos = parser.tokenizer.pos
      if not parser.tokenizer.eof() and parser.tokenizer.next().kind == TokenKind.LParen:
        # this is a function call!
        toCall = parser.parseFunctionCall(tok.ident)
        break
      else:
        # just an ident copy
        vIdent = some(
          tok.ident
        )
        break
    of TokenKind.Number:
      if *tok.intVal:
        atom = some(
          uinteger uint32(&tok.intVal)
        )
    of TokenKind.Whitespace: discard
    else: unreachable
  
  assert not (*atom and *vIdent and *toCall)

  if *vIdent: parser.error Other, "assignment from another address is not supported yet"

  case initialIdent
  of "let", "const":
    if *atom:
      return some(createImmutVal(ident, &atom))
    elif *toCall:
      return some(callAndStoreImmut(ident, &toCall))
  of "var":
    if *atom:
      return some(createMutVal(ident, &atom))
    elif *toCall:
      return some(callAndStoreMut(ident, &toCall))
  else: unreachable

proc parseStatement*(parser: Parser): Option[Statement]

proc parseFunction*(parser: Parser): Option[Function] =
  var name: Option[string]

  while not parser.tokenizer.eof:
    let tok = parser.tokenizer.next()
    case tok.kind
    of TokenKind.Identifier:
      name = some(tok.ident)
      break
    else: discard

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
    of TokenKind.Whitespace: discard
    of TokenKind.Identifier:
      info "parser: appending identifier to expected function argument signature: " & tok.ident
      if metRParen:
        parser.error Other, "unexpected identifier after end of function signature"

      arguments &=
        tok.ident
    else: 
      warn "parser (unimplemented): whilst parsing parameters: "
      print tok
      discard # parameter parser goes here :3

  var body: seq[Statement]
  info "parser: parse function body: " & &name
  while not parser.tokenizer.eof:
    let 
      prevPos = parser.tokenizer.pos
      c = parser.tokenizer.nextExceptWhitespace()

    if *c and (&c).kind == TokenKind.RCurly:
      info "parser: met end of curly bracket block"
      break
    else:
      parser.tokenizer.pos = prevPos
    
    let 
      peCount = parser.errors.len
      stmt = parser.parseStatement()

    if not *stmt:
      info "parser: can't find any more statements for function body: " & &name & "; body parsing complete"
      break

    body &= &stmt
  
  info "parser: parsed function: " & &name
  some function(&name, body, arguments)

proc parseAtom*(parser: Parser, token: Token): Option[MAtom] =
  info "parser: trying to parse an atom out of " & $token.kind
  
  case token.kind
  of TokenKind.Number:
    if *token.intVal:
      return some integer(
        &token.intVal
      )
    else:
      return some floating(token.floatVal)
  of TokenKind.String:
    return some str(
      token.str
    )
  else: unreachable

proc parseArguments*(parser: Parser): Option[PositionedArguments] =
  info "parser: parse arguments for function call"
  var
    metEnd = false
    args: PositionedArguments
    idx = -1

  while not parser.tokenizer.eof():
    inc idx
    let token = parser.tokenizer.next()

    case token.kind
    of TokenKind.Whitespace, TokenKind.Comma: discard
    of TokenKind.Identifier:
      let prevPos = parser.tokenizer.pos

      if parser.tokenizer.next().kind == TokenKind.LParen:
        # function!
        let 
          call = parser.parseFunctionCall(token.ident)
          resIdent = "@0_" & $idx

        parser.ast.appendToCurrentScope(
          callAndStoreMut(
            resIdent, 
            &call
          )
        )
        args.pushIdent(resIdent)
      else:
        parser.tokenizer.pos = prevPos
        args.pushIdent(token.ident)
    of TokenKind.Number, TokenKind.String:
      let atom = parser.parseAtom(token)

      if !atom:
        parser.error Other, "expected atom, got malformed data instead." # FIXME: make this less vague!

      args.pushAtom(&atom)
    of TokenKind.RParen:
      metEnd = true
      break
    else: unreachable

  if not metEnd:
    parser.error Other, "missing ) after argument list."

  some args

proc parseStatement*(parser: Parser): Option[Statement] =
  if parser.tokenizer.eof:
    parser.error Other, "expected statement, got EOF instead."

  let tok = parser.tokenizer.nextExceptWhitespace()

  if !tok:
    return #parser.error Other, "expected statement, got whitespace/EOF instead."
  
  let token = &tok

  case token.kind
  of TokenKind.Let:
    info "parser: parse let-expr"
    return parser.parseDeclaration("let")
  of TokenKind.Const:
    info "parser: parse const-expr"
    return parser.parseDeclaration("const")
  of TokenKind.Var:
    info "parser: parse var-expr"
    return parser.parseDeclaration("var")
  of TokenKind.Function:
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
    let prevPos = parser.tokenizer.pos
    
    if not parser.tokenizer.eof() and parser.tokenizer.next().kind == TokenKind.LParen:
      return parser.parseFunctionCall(token.ident) #some call(token.ident, arguments)

    parser.tokenizer.pos = prevPos
  of TokenKind.Return:
    let prevPos = parser.tokenizer.pos

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
      else: unreachable
    
    parser.tokenizer.pos = prevPos
    return some returnFunc()
  else: unreachable

proc parse*(parser: Parser): AST {.inline.} =
  parser.ast = newAST()

  while not parser.tokenizer.eof():
    let stmt = parser.parseStatement()
    
    if *stmt:
      parser.ast.appendToCurrentScope(&stmt)

  parser.ast

proc newParser*(input: string): Parser {.inline.} =
  Parser(
    tokenizer: newTokenizer(input)
  )
