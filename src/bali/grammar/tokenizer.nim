## JavaScript tokenizer
##
## Copyright (C) 2024 Trayambak Rai and Ferus Authors

import std/[math, options, logging, strutils, tables]
import ./token
import bali/internal/sugar
import pretty

type
  TokenizerOpts* = object
    ignoreWhitespace*: bool = false

  SourceLocation* = object
    line*, col*: uint

  Tokenizer* = ref object
    pos*: uint = 0
    location*: SourceLocation
    source: string

{.push inline, gcsafe.}

func eof*(tokenizer: Tokenizer): bool =
  let len =
    if tokenizer.source.len.uint < 1:
      0'u
    else:
      tokenizer.source.len.uint - 1

  tokenizer.pos > len

proc consume*(tokenizer: Tokenizer): char =
  inc tokenizer.pos
  inc tokenizer.location.col
  let c = tokenizer.source[tokenizer.pos]

  if c == '\n':
    inc tokenizer.location.line
    tokenizer.location.col = 0

  c

func hasAtleast*(tokenizer: Tokenizer, num: uint): bool =
  (tokenizer.pos + num) > tokenizer.source.len.uint - 1

func charAt*(tokenizer: Tokenizer, offset: uint = 0): Option[char] =
  if (tokenizer.pos + offset) > tokenizer.source.len.uint - 1:
    return

  tokenizer.source[tokenizer.pos + offset].some()

proc advance*(tokenizer: Tokenizer, offset: uint = 1) =
  if tokenizer.charAt() == some('\n'):
    inc tokenizer.location.line
    tokenizer.location.col = 0

  tokenizer.pos += offset
  tokenizer.location.col += offset

func newTokenizer*(source: string): Tokenizer =
  Tokenizer(pos: 0, source: source)

proc next*(tokenizer: Tokenizer): Token

proc tokenize*(
    tokenizer: Tokenizer, opts: TokenizerOpts = default(TokenizerOpts)
): seq[Token] =
  var tokens: seq[Token]

  while not tokenizer.eof():
    let token = tokenizer.next()
    if opts.ignoreWhitespace and token.kind == TokenKind.Whitespace:
      continue

    tokens &= token

  tokens

proc consumeInvalid*(tokenizer: Tokenizer): Token =
  warn "tokenizer: consume invalid token for character: " & (&tokenizer.charAt()).repr()
  tokenizer.advance()

  Token(kind: TokenKind.Invalid)

{.pop.}

proc consumeIdentifier*(tokenizer: Tokenizer): Token =
  debug "tokenizer: consume identifier"
  var ident: string

  while not tokenizer.eof():
    let c = &tokenizer.charAt()

    case c
    of {'a' .. 'z'}, {'A' .. 'Z'}, '_', '.', '$':
      ident &= c
      tokenizer.advance()
    else:
      break

  if not Keywords.contains(ident):
    debug "tokenizer: consumed identifier \"" & ident & "\""
    Token(kind: TokenKind.Identifier, ident: ident)
  else:
    let keyword = Keywords[ident]
    debug "tokenizer: consumed keyword: " & $keyword

    Token(kind: keyword)

proc consumeWhitespace*(tokenizer: Tokenizer): Token =
  debug "tokenizer: consume whitespace"
  var ws: string

  while not tokenizer.eof():
    let c = &tokenizer.charAt()

    case c
    of strutils.Whitespace:
      ws &= c
      tokenizer.advance()
    else:
      break

  debug "tokenizer: consumed " & $ws.len & " whitespace character(s)"

  Token(kind: TokenKind.Whitespace, whitespace: ws)

proc consumeEquality*(tokenizer: Tokenizer): Token =
  tokenizer.advance()
  let next = tokenizer.charAt()

  if not *next:
    debug "tokenizer: consume equal-to sign"
    return Token(kind: TokenKind.EqualSign)

  case &next
  of '=':
    if tokenizer.charAt(1) != some('='):
      debug "tokenizer: consume equality sign"
      tokenizer.advance()
      return Token(kind: TokenKind.Equal)
    else:
      debug "tokenizer: consume true equality sign"
      tokenizer.advance()
      return Token(kind: TokenKind.TrueEqual)
  else:
    debug "tokenizer: consume equal-to sign because next char isn't another equal sign"
    return Token(kind: TokenKind.EqualSign)

proc consumeString*(tokenizer: Tokenizer): Token =
  let closesWith = &tokenizer.charAt()
  debug "tokenizer: consume string with closing character: " & closesWith
  tokenizer.advance()

  var
    str: string
    ignoreNextQuote = false

  while not tokenizer.eof():
    let c = &tokenizer.charAt()

    if c == closesWith and not ignoreNextQuote:
      break

    if c == '\\':
      ignoreNextQuote = true
      tokenizer.advance()
      continue

    str &= c
    tokenizer.advance()

  let malformed = str.endsWith(closesWith)

  tokenizer.advance() # consume ending quote
  if not malformed:
    debug "tokenizer: consumed string \"" & str & '\"'
  else:
    warn "tokenizer: consumed malformed string: " & str
    warn "tokenizer: this string does not end with the ending character: " & closesWith

  Token(kind: TokenKind.String, malformed: malformed, str: str)

proc consumeComment*(tokenizer: Tokenizer, multiline: bool = false): Token =
  debug "tokenizer: consuming comment"
  tokenizer.advance()
  var comment: string

  while (not tokenizer.eof()):
    let c = &tokenizer.charAt()

    if not multiline and c in strutils.Newlines:
      break

    if multiline and c == '*' and tokenizer.charAt(1) == some('/'):
      tokenizer.pos += 2 # consume "*/"
      break

    comment &= c
    tokenizer.advance()

  debug "tokenizer: consumed comment: " & comment

  Token(kind: TokenKind.Comment, multiline: multiline, comment: comment)

proc consumeSlash*(tokenizer: Tokenizer): Token =
  tokenizer.advance()

  let next = tokenizer.charAt()

  if not *next:
    info "tokenizer: consumed divide sign"
    return Token(kind: TokenKind.Div)

  case &next
  of '*':
    return tokenizer.consumeComment(multiline = true)
  of '/':
    return tokenizer.consumeComment(multiline = false)
  else:
    info "tokenizer: consumed divide sign"
    return Token(kind: TokenKind.Div)

proc consumeExclaimation*(tokenizer: Tokenizer): Token =
  tokenizer.advance()

  let next = tokenizer.charAt()
  if not *next:
    return Token(kind: TokenKind.Invalid)

  case &next
  of '=':
    if tokenizer.charAt(1) != some('='):
      tokenizer.pos += 1
      return Token(kind: TokenKind.NotEqual)
    else:
      tokenizer.pos += 2
      return Token(kind: TokenKind.NotTrueEqual)
  else:
    return Token(kind: TokenKind.Invalid)

proc charToDecimalDigit*(c: char): Option[uint32] {.inline.} =
  ## Convert characters to decimal digits
  if c >= '0' and c <= '9':
    return some((c.ord - '0'.ord).uint32)

proc consumeNumeric*(tokenizer: Tokenizer, negative: bool = false): Token =
  var
    hasSign: bool
    sign = 1f

  if negative:
    hasSign = true
    sign = -1f
  else:
    case tokenizer.consume()
    of '-':
      hasSign = true
      sign = -1f
    of '+':
      hasSign = true
      sign = 1f
    else:
      hasSign = false
      sign = 1f
      tokenizer.pos -= 1

  if hasSign:
    tokenizer.advance(1)

  var
    integralPart: float64
    digit: uint32

  while not tokenizer.eof and unpack(charToDecimalDigit(&tokenizer.charAt()), digit):
    integralPart = integralPart * 10'f64 + digit.float64
    tokenizer.advance(1)

  var
    isInteger = true
    fractionalPart: float64 = 0'f64

  if tokenizer.charAt() == some('.') and &tokenizer.charAt(1) in {'0' .. '9'}:
    isInteger = false
    tokenizer.advance(1)

    var factor = 0.1'f64

    while not tokenizer.eof() and unpack(charToDecimalDigit(tokenizer.consume()), digit):
      fractionalPart += digit.float64 * factor
      factor *= 0.1'f64
      tokenizer.advance(1)

  var value = sign * (integralPart + fractionalPart)
  if tokenizer.charAt(1) in [some 'e', some 'E']:
    if &tokenizer.charAt(1) in {'0' .. '9'} or
        tokenizer.hasAtleast(2) and &tokenizer.charAt(1) in ['+', '-'] and
        &tokenizer.charAt(2) in {'0' .. '9'}:
      isInteger = false
      tokenizer.advance(1)

      let (hasSign, sign) =
        case tokenizer.consume()
        of '-':
          (true, -1f)
        of '+':
          (true, 1f)
        else:
          (false, 1f)

      if hasSign:
        tokenizer.advance(1)

      var exponent: float64 = 0'f64

      while unpack(charToDecimalDigit(tokenizer.consume()), digit):
        exponent = exponent * 10'f64 + digit.float64
        tokenizer.advance(1)
        if tokenizer.eof():
          break

      value *= pow(10'f64, sign * exponent)

  let intValue: Option[int32] =
    case isInteger
    of true:
      some(
        if value >= int32.high.float64:
          int32.high
        elif value <= int32.low.float64:
          int32.low
        else:
          value.int32
      )
    else:
      none(int32)

  let valF32 = value.float64
  Token(kind: TokenKind.Number, hasSign: hasSign, floatVal: valF32, intVal: intValue)

proc consumePlus*(tokenizer: Tokenizer): Token =
  tokenizer.advance()

  let next = tokenizer.charAt()
  if not *next:
    return Token(kind: TokenKind.Add)

  case &next
  of '+':
    tokenizer.advance()
    return Token(kind: TokenKind.Increment)
  of strutils.Whitespace:
    return Token(kind: TokenKind.Add)
  else:
    discard

proc consumeAmpersand*(tokenizer: Tokenizer): Token =
  tokenizer.advance()
  let next = tokenizer.charAt()
  if !next:
    return tokenizer.consumeInvalid()

  case &next
  of '&':
    debug "tokenizer: consumed And operand"
    tokenizer.advance()
    return Token(kind: TokenKind.And)
  else:
    return tokenizer.consumeInvalid()

proc consumePipe*(tokenizer: Tokenizer): Token =
  tokenizer.advance()

  let next = tokenizer.charAt()
  if !next:
    return tokenizer.consumeInvalid()

  case &next
  of '|':
    debug "tokenizer: consumed Or operand"
    tokenizer.advance()
    return Token(kind: TokenKind.Or)
  else:
    return tokenizer.consumeInvalid()

proc consumeHash*(tokenizer: Tokenizer): Token =
  tokenizer.advance()

  if tokenizer.charAt() == some('!'):
    if (tokenizer.pos - 2) >= 0 and tokenizer.source[tokenizer.pos - 2] in strutils.Whitespace:
      tokenizer.advance()
      return Token(kind: TokenKind.InvalidShebang)

    # shebang logic
    tokenizer.advance()
    var shebang: string

    while not tokenizer.eof:
      let c = tokenizer.consume()

      case c
      of strutils.Newlines:
        break
      else:
        shebang &= c

      tokenizer.advance()

    return Token(kind: TokenKind.Shebang, shebang: shebang)

  tokenizer.consumeInvalid()

proc next*(tokenizer: Tokenizer): Token =
  let c = tokenizer.charAt()

  case &c
  of {'a' .. 'z'}, {'A' .. 'Z'}, '_', '$':
    tokenizer.consumeIdentifier()
  of strutils.Whitespace:
    tokenizer.consumeWhitespace()
  of '"', '\'':
    tokenizer.consumeString()
  of '=':
    tokenizer.consumeEquality()
  of {'\0' .. '\1'}:
    tokenizer.advance()
    Token(kind: TokenKind.Whitespace)
  of '/':
    tokenizer.consumeSlash()
  of {'0' .. '9'}:
    tokenizer.consumeNumeric(false)
  of '-':
    if not tokenizer.eof and &tokenizer.charAt(1) in {'0' .. '9'}:
      tokenizer.consumeNumeric(true)
    else:
      tokenizer.advance()
      return Token(kind: TokenKind.Sub)
  of '.':
    tokenizer.advance()
    Token(kind: TokenKind.Dot)
  of '(':
    tokenizer.advance()
    Token(kind: TokenKind.LParen)
  of ')':
    tokenizer.advance()
    Token(kind: TokenKind.RParen)
  of '[':
    tokenizer.advance()
    Token(kind: TokenKind.LBracket)
  of ']':
    tokenizer.advance()
    Token(kind: TokenKind.RBracket)
  of '{':
    tokenizer.advance()
    Token(kind: TokenKind.LCurly)
  of '}':
    tokenizer.advance()
    Token(kind: TokenKind.RCurly)
  of ',':
    tokenizer.advance()
    Token(kind: TokenKind.Comma)
  of '!':
    tokenizer.consumeExclaimation()
  of '+':
    tokenizer.consumePlus()
  of '&':
    tokenizer.consumeAmpersand()
  of '|':
    tokenizer.consumePipe()
  of ';':
    tokenizer.advance()
    Token(kind: TokenKind.Semicolon)
  of '#':
    tokenizer.consumeHash()
  of '*':
    tokenizer.advance()
    return Token(kind: TokenKind.Mul)
  else:
    tokenizer.consumeInvalid()

proc nextExceptWhitespace*(tokenizer: Tokenizer): Option[Token] =
  var tok = tokenizer.next()

  while not tokenizer.eof() and tok.kind == TokenKind.Whitespace:
    tok = tokenizer.next()

  if tok.kind != TokenKind.Whitespace:
    some tok
  else:
    none Token
