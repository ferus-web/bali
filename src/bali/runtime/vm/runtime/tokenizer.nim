## A tokenizer for MIR.
## This works very similarly to Stylus' tokenizer.
##

import std/[options, strutils, tables, math]
import ./shared

type
  TokenizerDefect* = object of Defect
  Tokenizer* = ref object
    input*: string
    pos*: uint

proc newTokenizer*(input: string): Tokenizer {.inline.} =
  Tokenizer(input: input, pos: 0'u)

proc forwards*(tokenizer: Tokenizer, n: uint) {.inline, gcsafe.} =
  ## Go forwards by `n` characters
  tokenizer.pos += n

proc charAt*(tokenizer: Tokenizer, offset: uint = 0'u): char {.inline, noSideEffect.} =
  ## Get the character at our current position + `offset`.
  tokenizer.input[tokenizer.pos + offset]

proc nextChar*(tokenizer: Tokenizer): char {.inline, noSideEffect.} =
  ## Get the next character
  result = charAt(tokenizer, 0)

proc hasAtLeast*(tokenizer: Tokenizer, n: uint): bool {.inline, gcsafe, noSideEffect.} =
  ## Are there `n` number of characters ahead of us?
  tokenizer.pos + n < tokenizer.input.len.uint

proc isEof*(tokenizer: Tokenizer): bool {.inline, gcsafe, noSideEffect.} =
  ## Have we hit the end of the input?
  not tokenizer.hasAtLeast(0)

proc consumeComment*(tokenizer: Tokenizer): Token =
  var comment = Token(kind: tkComment, comment: "")

  while not tokenizer.isEof:
    let c = tokenizer.nextChar()
    tokenizer.forwards(1)

    case c
    of '\n', '\r':
      break
    else:
      comment.comment &= c

  comment

proc consumeWhitespace*(tokenizer: Tokenizer): Token =
  var ws = Token(kind: tkWhitespace)

  while not tokenizer.isEof():
    let c = tokenizer.nextChar()

    case c
    of '\r', ' ', '\0', '\\', '\n':
      tokenizer.forwards(1)
      ws.whitespace &= c
    else:
      break

  ws

proc consumeNewline*(tokenizer: Tokenizer): Token {.inline.} =
  let c = tokenizer.nextChar()
  assert c == '\r' or c == '\n' or c == '\x0C'

  inc tokenizer.pos
  if c == '\r' and tokenizer.nextChar() == '\n':
    inc tokenizer.pos

proc consumeQuotedString*(tokenizer: Tokenizer, singleQuote: bool): Token =
  tokenizer.forwards(1)
  var qstr = Token(kind: tkQuotedString)

  while not tokenizer.isEof():
    let c = tokenizer.nextChar()
    case c
    of '"':
      tokenizer.forwards(1)
      if not singleQuote:
        break
    of '\'':
      tokenizer.forwards(1)
      if singleQuote:
        break
    of '\\':
      tokenizer.forwards(1)
      if not tokenizer.isEof():
        case tokenizer.nextChar()
        of '\n', '\x0C', '\r':
          discard tokenizer.consumeNewline()
        else:
          discard
    else:
      tokenizer.forwards(1)

    qstr.str &= c

  qstr

proc charToDecimalDigit*(c: char): Option[uint32] {.inline.} =
  ## Convert characters to decimal digits
  if c >= '0' and c <= '9':
    return some((c.ord - '0'.ord).uint32)

proc consumeNumeric*(tokenizer: Tokenizer): Token =
  proc unpack[T](o: Option[T], v: var T): bool {.inline.} =
    if o.isSome:
      v = unsafeGet o
      true
    else:
      v = default T
      false

  let (hasSign, sign) =
    case tokenizer.nextChar()
    of '-':
      (true, -1f)
    of '+':
      (true, 1f)
    else:
      (false, 1f)

  if hasSign:
    tokenizer.forwards(1)

  var
    integralPart: float64
    digit: uint32

  while not tokenizer.isEof() and unpack(
    charToDecimalDigit(tokenizer.nextChar()), digit
  )
  :
    integralPart = integralPart * 10'f64 + digit.float64
    tokenizer.forwards(1)

  var
    isInteger = true
    fractionalPart: float64 = 0'f64

  if tokenizer.hasAtleast(1) and tokenizer.nextChar() == '.' and
      tokenizer.charAt(1) in {'0' .. '9'}:
    isInteger = false
    tokenizer.forwards(1)

    var factor = 0.1'f64

    while unpack(charToDecimalDigit(tokenizer.nextChar()), digit):
      fractionalPart += digit.float64 * factor
      factor *= 0.1'f64
      tokenizer.forwards(1)
      if tokenizer.isEof():
        break

  var value = sign * (integralPart + fractionalPart)
  #[if tokenizer.hasAtleast(1) and tokenizer.nextChar() in ['e', 'E']:
    if tokenizer.charAt(1) in {'0' .. '9'} or
        tokenizer.hasAtleast(2) and tokenizer.charAt(1) in ['+', '-'] and
        tokenizer.charAt(2) in {'0' .. '9'}:
      isInteger = false
      tokenizer.forwards(1)

      let (hasSign, sign) =
        case tokenizer.nextChar()
        of '-':
          (true, -1f)
        of '+':
          (true, 1f)
        else:
          (false, 1f)

      if hasSign:
        tokenizer.forwards(1)

      var exponent: float64 = 0'f64

      while unpack(charToDecimalDigit(tokenizer.nextChar()), digit):
        exponent = exponent * 10'f64 + digit.float64
        tokenizer.forwards(1)
        if tokenizer.isEof():
          break

      value *= pow(10'f64, sign * exponent)]#

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

  if intValue.isSome:
    Token(kind: tkInteger, iHasSign: hasSign, integer: intValue.unsafeGet())
  else:
    Token(kind: tkDouble, dHasSign: hasSign, double: value)

proc consumeCharacterBasedToken*(tokenizer: Tokenizer): Token =
  var
    ident = Token(kind: tkIdent)
    operation = Token(kind: tkOperation)
    content: string

  while not tokenizer.isEof:
    let c = tokenizer.nextChar()
    tokenizer.forwards(1)

    case c
    of {'a' .. 'z'}, {'A' .. 'Z'}, '_':
      content &= c
    of Whitespace, '\0':
      break
    else:
      discard

  if content in OpCodeToTable:
    operation.op = content
    operation
  else:
    if content.startsWith("CLAUSE"):
      return Token(kind: tkClause, clause: tokenizer.consumeCharacterBasedToken().ident)
    elif content.startsWith("END"):
      return Token(kind: tkEnd, endClause: tokenizer.consumeCharacterBasedToken().ident)

    ident.ident = content
    ident

proc next*(tokenizer: Tokenizer, includeWhitespace: bool = false): Token =
  if tokenizer.isEof:
    raise newException(
      TokenizerDefect, "Attempt to tokenize more tokens despite hitting EOF."
    )

  let c = tokenizer.nextChar()

  case c
  of '#':
    tokenizer.forwards(2)
    return tokenizer.consumeComment()
  of {'A' .. 'Z'}, {'a' .. 'z'}, '_':
    return tokenizer.consumeCharacterBasedToken()
  of '\r', ' ', '\0', '\\':
    tokenizer.forwards(1)
    if not includeWhitespace:
      return tokenizer.next()
    else:
      return tokenizer.consumeWhitespace()
  of '"':
    return tokenizer.consumeQuotedString(false)
  of '\'':
    return tokenizer.consumeQuotedString(true)
  of {'0' .. '9'}:
    return tokenizer.consumeNumeric()
  #[
  of '.':
    if tokenizer.hasAtleast(1) and tokenizer.charAt(1) in {'0'..'9'}:
      return tokenizer.consumeDouble()
  ]#
  else:
    tokenizer.forwards(1)

  Token(kind: tkWhitespace)

proc nextExcludingWhitespace*(tokenizer: Tokenizer): Token {.inline.} =
  var next = next tokenizer

  while not tokenizer.isEof() and next.kind == tkWhitespace:
    next = next tokenizer

  next

proc maybeNext*(tokenizer: Tokenizer): Option[Token] {.inline.} =
  if not tokenizer.isEof():
    return some tokenizer.next()

proc maybeNextExcludingWhitespace*(tokenizer: Tokenizer): Option[Token] {.inline.} =
  var next = next tokenizer

  while not tokenizer.isEof() and next.kind == tkWhitespace:
    next = next tokenizer

  if next.kind != tkWhitespace:
    return some next

iterator flow*(
    tokenizer: Tokenizer, includeWhitespace: bool = false
): Token {.inline.} =
  while not tokenizer.isEof():
    yield tokenizer.next(includeWhitespace)
