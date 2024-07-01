## JavaScript parser
##
## Copyright (C) 2024 Trayambak Rai

import std/[options, logging, tables]
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
      vIdent = some(
        tok.ident
      )
    of TokenKind.Number:
      if *tok.intVal:
        atom = some(
          uinteger uint32(&tok.intVal)
        )
    of TokenKind.Whitespace: discard
    else: unreachable
  
  assert not (*atom and *vIdent)

  if *vIdent: error Other, "assignment from another address is not supported yet"

  case initialIdent
  of "let", "const":
    discard parser.tokenizer.next()
    return some(createImmutVal(ident, &atom))
  of "var":
    return some(createMutVal(ident, &atom))
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
    else: discard # parameter parser goes here :3

  while not parser.tokenizer.eof:
    let prevPos = parser.tokenizer.pos
    let c = parser.tokenizer.nextExceptWhitespace()
    if c.kind == TokenKind.RCurly:
      info "parser: met end of curly bracket block"
      break
    
    parser.tokenizer.pos = prevPos # if we didn't get a right curly bracket, backtrack to the previous position and parse statements

    let stmt = parser.parseStatement()
    if not *stmt:
      warn "parser: no statement generated, checking for errors to throw"
      assert parser.errors.len > 0, "No statement returned without any errors"
      raise newException(
        SyntaxError,
        $parser.errors[0]
      )
  
  some function(&name, @[])

proc parseStatement*(parser: Parser): Option[Statement] =
  let token = parser.tokenizer.next()
    
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
    print parser.parseFunction()
    return Statement().some()
  of TokenKind.Whitespace: discard
  else: unreachable

proc parse*(parser: Parser): AST {.inline.} =
  parser.ast = newAST()

  while not parser.tokenizer.eof():
    let stmt = parser.parseStatement()
    if not *stmt:
      warn "parser: no statement generated, checking for errors to throw"
      assert parser.errors.len > 0, "No statement returned without any errors"
      raise newException(
        SyntaxError,
        $parser.errors[0]
      )
    
    parser.ast.appendToCurrentScope(&stmt)

proc newParser*(input: string): Parser {.inline.} =
  Parser(
    tokenizer: newTokenizer(input)
  )
