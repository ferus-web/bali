## Generic lexer implemented with `std/lexbase` and mostly designed to mimic
## Ladybird's LibJS generic lexer.

import std/[lexbase, options, strutils]

type GenericLexer* {.final.} = object of BaseLexer

func remaining*(lexer: GenericLexer): uint {.inline.} =
  uint(lexer.buf.len - lexer.bufpos)

func eof*(lexer: var GenericLexer): bool {.inline.} =
  lexer.remaining() < 1'u

func consume*(lexer: var GenericLexer): char =
  if lexer.eof:
    return '\0'

  inc lexer.bufpos
  result = lexer.buf[lexer.bufpos - 1]

func consumeSpecific*(lexer: var GenericLexer, c: char): bool {.inline.} =
  if lexer.consume() == c:
    return true

  dec lexer.bufpos

func peek*(lexer: GenericLexer): char =
  lexer.buf[lexer.bufpos + 1]

func lexNDigits*(lexer: var GenericLexer, n: uint): Option[int] =
  if lexer.remaining < n:
    return

  var r: int
  for i in 0 ..< n:
    let ch = lexer.consume()
    if ch notin strutils.Digits:
      return

    r = 10 * r + int(((uint8) ch) - (uint8) '0')

  result = some(r)

func newGenericLexer*(src: string): GenericLexer {.inline.} =
  GenericLexer(buf: src)
