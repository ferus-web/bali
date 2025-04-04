import std/[options, strutils, tables]

{.experimental: "strictDefs".}

type
  TokenKind* {.pure.} = enum
    Identifier
    Break
    Case
    Catch
    Continue
    Debugger
    Default
    Delete
    Do
    Else
    Finally
    For
    Function
    If
    In
    Instanceof
    New
    Return
    Switch
    This
    Throw
    Try
    Typeof
    Var
    Const
    Void
    While
    With
    Class
    Enum
    Export
    Extends
    Import
    Super
    Null
    True
    False
    Implements
    Interface
    Let
    Package
    Private
    Protected
    Public
    Static
    Yield
    Get
    Set
    LCurly
    RCurly
    LBracket
    RBracket
    And
    Or
    LParen
    RParen
    Period
    Semicolon
    Comma
    LessThan
    GreaterThan
    Dot
    LessEqual
    GreaterEqual
    NotEqual
    TrueEqual
    NotTrueEqual
    Equal
    Add
    Sub
    Div
    Mul
    Mod
    Exp
    Increment
    Decrement
    AlShift
    ArShift
    Band
    Bora
    Bxor
    LNot
    BNot
    LAnd
    LOr
    Question
    Colon
    EqualSign
    AddEq
    SubEq
    MulEq
    DivEq
    ModEq
    ExpEq
    AlShiftEq
    ArShiftEq
    RshiftEq
    BandEq
    BorEq
    BxorEq
    LAndEq
    LOrEq
    Number
    String
    Regexp
    Whitespace
    Comment
    Invalid
    Shebang
    InvalidShebang

  MalformedStringReason* {.pure.} = enum
    None
    UnclosedString
    BadUnicodeEscape
    UnicodeEscapeIntTooBig
    UnicodeEscapeIntTooSmall

  Token* = object
    containsUnicodeEsc*: bool

    case kind*: TokenKind
    of TokenKind.String:
      str*: string
      malformed*: bool
      strMalformedReason*: MalformedStringReason
    of TokenKind.Identifier:
      ident*: string
      identHasMalformedUnicodeSeq*: bool
    of TokenKind.Number:
      floatVal*: float
      hasSign*: bool
      intVal*: Option[int32]
    of TokenKind.Whitespace:
      whitespace*: string
    of TokenKind.Comment:
      comment*: string
      multiline*: bool
    of TokenKind.Shebang:
      shebang*: string
    else:
      discard

func isNewline*(token: Token): bool {.inline.} =
  token.kind == TokenKind.Whitespace and token.whitespace.contains(strutils.Newlines)

func getError*(token: Token): Option[string] =
  case token.kind
  of TokenKind.String:
    if not token.malformed:
      return

    case token.strMalformedReason
    of MalformedStringReason.UnclosedString:
      return some("string literal contains an unescaped line break")
    of MalformedStringReason.BadUnicodeEscape:
      return some("malformed Unicode character escape sequence")
    of MalformedStringReason.UnicodeEscapeIntTooBig:
      return
        some("Unicode codepoint must not be greater than 0x10FFFF in escape sequence")
    of MalformedStringReason.UnicodeEscapeIntTooSmall:
      return some("Unicode codepoint cannot be less than zero")
    of MalformedStringReason.None:
      return none(string)
  else:
    return none(string)

const Keywords* = {
  "const": TokenKind.Const,
  "let": TokenKind.Let,
  "var": TokenKind.Var,
  "if": TokenKind.If,
  "else": TokenKind.Else,
  "true": TokenKind.True,
  "false": TokenKind.False,
  "new": TokenKind.New,
  "debugger": TokenKind.Debugger,
  "throw": TokenKind.Throw,
  "function": TokenKind.Function,
  "return": TokenKind.Return,
  "while": TokenKind.While,
  "break": TokenKind.Break,
  "typeof": TokenKind.Typeof,
  "for": TokenKind.For,
  "try": TokenKind.Try,
  "catch": TokenKind.Catch,
}.toTable
