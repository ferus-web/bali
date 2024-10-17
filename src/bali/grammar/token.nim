import std/[options, strutils, tables]

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

  Token* = object
    case kind*: TokenKind
    of TokenKind.String:
      str*: string
      malformed*: bool
    of TokenKind.Identifier:
      ident*: string
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
}.toTable
