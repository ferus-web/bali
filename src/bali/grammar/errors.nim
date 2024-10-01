import bali/grammar/tokenizer

type
  ParseErrorKind* = enum
    UnexpectedToken
    Other

  ParseError* = object
    location*: SourceLocation
    kind*: ParseErrorKind = Other
    message*: string

