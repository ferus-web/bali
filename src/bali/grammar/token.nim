import std/[options, tables]

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

    Get, Set

    LCurly
    RCurly
    LBracket
    RBracket
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

  Token* = object
    case kind*: TokenKind
    of String:
      str*: string
      malformed*: bool
    of Identifier:
      ident*: string
    of Number:
      floatVal*: float
      hasSign*: bool
      intVal*: Option[int32]
    of Whitespace:
      whitespace*: string
    of Comment:
      comment*: string
      multiline*: bool
    else: discard

const
  Keywords* = {
    "const": TokenKind.Const,
    "let": TokenKind.Let,
    "var": TokenKind.Var,
    "if": TokenKind.If,
    "else": TokenKind.Else,
    "true": TokenKind.True,
    "false": TokenKind.False,
    "new": TokenKind.New,
    "debugger": TokenKind.Debugger,
    "function": TokenKind.Function,
    "return": TokenKind.Return
  }.toTable
