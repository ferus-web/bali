import std/[strutils, tables]
import bali/internals/[sugar, strconv]

const
  lineSeparatorChars* = [(char)0xe2, (char)0x80, (char)0xa8]
  LINE_SEPARATOR_STRING* = static:
    var x = newStringOfCap(
      (sizeof lineSeparatorChars) - 1
    )
    for i, c in lineSeparatorChars:
      x[i] = c

    x
  LINE_SEPARATOR* = 0x2028'u32 ## U+2028 LINE SEPARATOR

type
  TokenCategory* = enum
    Invalid
    Number
    String
    Punctuation
    Operator
    Keyword
    ControlKeyword
    Identifier

  TokenKind* = enum
    Ampersand
    AmpersandEquals
    Arrow
    Asterisk
    AsteriskEquals
    Async
    Await
    BigIntLiteral
    BoolLiteral
    BracketOpen, BracketClose
    Break
    Caret
    CaretEquals
    Case
    Catch
    Class
    Colon
    Comma
    Const
    Continue
    CurlyOpen, CurlyClose
    Debugger
    Default
    Delete
    Do
    DoubleAmpersand
    DoubleAmpersandEquals
    DoubleAsterisk
    DoubleAsteriskEquals
    DoublePipe
    DoublePipeEquals
    DoubleQuestionMark
    DoubleQuestionMarkEquals
    Else
    Enum
    Eof
    Equals                     # <------|
    EqualsEquals               #        | The Holy Trinity of Tech Bros
    EqualsEqualsEquals         # <------|
    EscapedKeyword
    ExclamationMark
    ExclamationMarkEquals
    ExclamationMarkEqualsEquals
    Export
    Extends
    Finally
    For
    Function
    GreaterThan
    GreaterThanEquals
    Identifier
    If
    Implements
    Import
    In
    Instanceof
    Interface
    LessThan
    LessThanEquals
    Let
    Minus
    MinusEquals
    MinusMinus
    New
    NullLiteral
    NumericLiteral
    Package
    ParenClose
    ParenOpen
    Percent
    PercentEquals
    Period
    Pipe
    Plus
    PipeEquals
    PlusEquals
    PlusPlus
    Private
    PrivateIdentifier
    Protected
    Public
    QuestionMark
    QuestionMarkPeriod
    RegexFlags
    RegexLiteral
    Return
    Semicolon
    ShiftLeft
    ShiftLeftEquals
    ShiftRight
    ShiftRightEquals
    Slash
    SlashEquals
    Static
    StringLiteral
    Super
    Switch
    TemplateLiteralEnd
    TemplateLiteralExprEnd
    TemplateLiteralExprStart
    TemplateLiteralStart
    TemplateLiteralString
    This
    Throw
    Tilde
    TripleDot
    Try
    Typeof
    UnsignedShiftRight
    UnsignedShiftRightEquals
    UnterminatedRegexLiteral
    UnterminatedStringLiteral
    UnterminatedTemplateLiteral
    Var
    Void
    While
    With
    Yield

const
  Category* = {
    Ampersand: Operator,
    AmpersandEquals: Operator,
    Arrow: Operator,
    Asterisk: Operator,
    AsteriskEquals: Operator,
    Async: Keyword,
    Await: Keyword,
    BigIntLiteral: Number,
    BoolLiteral: Keyword,
    BracketClose: Punctuation,
    BracketOpen: Punctuation,
    Break: Keyword,
    Caret: Operator,
    CaretEquals: Operator,
    Case: ControlKeyword,
    Catch: ControlKeyword,
    Class: Keyword,
    Colon: Punctuation,
    Comma: Punctuation,
    Const: Keyword,
    Continue: ControlKeyword,
    CurlyClose: Punctuation,
    CurlyOpen: Punctuation,
    Debugger: Keyword,
    Default: ControlKeyword,
    Delete: Keyword,
    Do: Keyword,
    DoubleAmpersand: Operator,
    DoubleAmpersandEquals: Operator,
    DoubleAsterisk: Operator,
    DoubleAsteriskEquals: Operator,
    DoublePipe: Operator,
    DoublePipeEquals: Operator,
    DoubleQuestionMark: Operator,
    DoubleQuestionMarkEquals: Operator,
    Else: ControlKeyword,
    Enum: Keyword,
    Eof: Invalid,
    Equals: Operator,
    EqualsEquals: Operator,
    EqualsEqualsEquals: Operator,
    EscapedKeyword: Identifier,
    ExclamationMark: Operator,
    ExclamationMarkEquals: Operator,
    ExclamationMarkEqualsEquals: Operator,
    Export: Keyword,
    Extends: Keyword,
    Finally: Keyword,
    For: ControlKeyword,
    Function: Keyword,
    GreaterThan: Keyword,
    GreaterThanEquals: Keyword,
    Import: Keyword,
    In: Keyword,
    Instanceof: Keyword,
    Interface: Keyword,
    LessThan: Operator,
    LessThanEquals: Operator,
    Let: Keyword,
    Minus: Operator,
    MinusEquals: Operator,
    MinusMinus: Operator,
    New: Keyword,
    NullLiteral: Keyword,
    NumericLiteral: Number,
    Package: Keyword,
    ParenClose: Punctuation,
    ParenOpen: Punctuation,
    Percent: Operator,
    PercentEquals: Operator,
    Period: Operator,
    Pipe: Operator,
    PipeEquals: Operator,
    Plus: Operator,
    PlusEquals: Operator,
    PlusPlus: Operator,
    Private: Keyword,
    PrivateIdentifier: Identifier,
    Protected: Keyword,
    Public: Keyword,
    QuestionMark: Operator,
    QuestionMarkPeriod: Operator,
    RegexFlags: String,
    RegexLiteral: String,
    Return: ControlKeyword,
    Semicolon: Punctuation,
    ShiftLeft: Operator,
    ShiftLeftEquals: Operator,
    ShiftRight: Operator,
    ShiftRightEquals: Operator,
    Slash: Operator,
    SlashEquals: Operator,
    Static: Keyword,
    StringLiteral: String,
    Super: Keyword,
    Switch: ControlKeyword,
    TemplateLiteralEnd: String,
    TemplateLiteralExprEnd: Punctuation,
    TemplateLiteralExprStart: Punctuation,
    TemplateLiteralStart: String,
    TemplateLiteralString: String,
    This: Keyword,
    Throw: ControlKeyword,
    Tilde: Operator,
    Identifier: Identifier,
    TripleDot: Operator,
    Try: ControlKeyword,
    Typeof: Keyword,
    UnsignedShiftRight: Operator,
    UnsignedShiftRightEquals: Operator,
    UnterminatedRegexLiteral: String,
    UnterminatedStringLiteral: String,
    UnterminatedTemplateLiteral: String,
    Var: Keyword,
    Void: Keyword,
    While: ControlKeyword,
    With: ControlKeyword,
    Yield: ControlKeyword
  }.toTable

type
  StringValueStatus* = enum
    svsOk
    svsMalformedHexEscape
    svsMalformedUnicodeEscape
    svsUnicodeEscapeOverflow
    svsLegacyOctalEscapeSequence

  Token* = ref object
    kind*: TokenKind
    message*, trivia*, value*, filename*: string
    lineNumber*, lineColumn*, offset*: uint
    strvStatus*: StringValueStatus

proc category*(token: Token): TokenCategory {.inline.} =
  Category[token.kind]

proc category*(kind: TokenKind): TokenCategory {.inline.} =
  Category[kind]

proc isIdentifierName*(token: Token): bool {.inline.} =
  token.kind == Identifier or
  token.kind == EscapedKeyword or
  token.kind == Await or
  token.kind == Async or
  token.kind == BoolLiteral or
  token.kind == Break or
  token.kind == Case or
  token.kind == Catch or
  token.kind == Class or
  token.kind == Const or
  token.kind == Continue or
  token.kind == Debugger or
  token.kind == Default or
  token.kind == Delete or
  token.kind == Do or
  token.kind == Else or
  token.kind == Enum or
  token.kind == Export or
  token.kind == Extends or
  token.kind == Finally or
  token.kind == For or
  token.kind == Function or
  token.kind == If or
  token.kind == Import or
  token.kind == In or
  token.kind == Instanceof or
  token.kind == Let or
  token.kind == New or
  token.kind == NullLiteral or
  token.kind == Return or
  token.kind == Super or
  token.kind == Switch or
  token.kind == This or
  token.kind == Throw or
  token.kind == Try or
  token.kind == Typeof or
  token.kind == Var or
  token.kind == Void or
  token.kind == While or
  token.kind == With or
  token.kind == Yield

proc triviaContainsLineTerminator*(token: Token): bool {.inline.} =
  token.trivia.contains('\n') or
  token.trivia.contains('\r') or
  token.trivia.contains(LINE_SEPARATOR_STRING) or
  token.trivia.contains(PARAGRAPH_SEPARATOR_STRING)

proc boolValue*(token: Token): bool {.inline.} =
  if token.kind != BoolLiteral:
    raise newException(ValueError, "Cannot get boolean value out of non-boolean literal.")

  parseBool(token.value)

proc floatValue*(token: Token): float {.inline.} =
  if token.kind != NumericLiteral:
    raise newException(ValueError, "Cannot get float value out of non-numeric literal.")

  var buffer = newString(32)

  for c in token.value:
    if c == '_':
      continue

    buffer &= c

  if buffer[0] == '0' and buffer.len >= 2:
    let converted = &strToUint(
      buffer,
      case buffer[1].toLowerAscii():
        of 'x':
          16
        of 'o':
          8
        of 'b':
          2
        else:
          if isAlphaAscii(buffer[1]) and not value.contains('8') and not value.contains('9'):
            8
          else:
            unreachable
            return 0 
    )
    return cast[float](converted)

  cast[float](parseInt(buffer))

proc hex2int*(x: char): uint32 {.inline.} =
  if x.ord >= '0' and x.ord <= '9'.ord:
    return x.ord - '0'.ord

  10'u32 + (toLowerAscii(x).ord - 'a'.ord).uint32

proc stringValue*(token: Token, status: StringValueStatus): string =
  if token.kind != StringLiteral and token.kind != TemplateLiteralString:
    raise newException(ValueError, "Cannot get float value out of numeric literal.")

  let 
    isTemplate =
      token.kind == TemplateLiteralString
