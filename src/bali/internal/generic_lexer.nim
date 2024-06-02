## This module roughly implements a generic lexer from SerenityOS's AK library.
## Copyright (C) 2024 Trayambak Rai and Ferus Authors
import std/[options, sugar, strutils]
import bali/internal/sugar

type
  GenericLexer* = ref object
    input: string
    index: uint

when defined(speed):
  {.push checks: off, gcsafe, inline.}

when defined(release):
  {.push gcsafe, inline.}

proc tell*(lexer: GenericLexer): uint =
  lexer.index

proc tellRemaining*(lexer: GenericLexer): uint =
  lexer.input.len.uint - lexer.index

proc isEof*(lexer: GenericLexer): bool =
  lexer.index >= lexer.input.len.uint

proc peek*(lexer: GenericLexer, offset: uint = 0'u): Option[char] =
  if (lexer.index + offset < lexer.input.len.uint):
    some(lexer.input[lexer.index.uint + offset])
  else:
    none(char)

proc expect*(lexer: GenericLexer, expects: char | string): bool =
  let n = lexer.peek()
  if !n: return false

  &n == expects

proc expect*(lexer: GenericLexer, expects: string): bool =
  for i in 0 ..< expects.len:
    let n = lexer.peek()
    if !n: return false

    if &n != expects[i]:
      return false

  true

proc input*(lexer: GenericLexer): string =
  lexer.input

proc back*(lexer: GenericLexer, count: uint): string =
  if (lexer.index - count) < 0:
    raise newException(ValueError, "Attempt to go back below zero! (" & $count & " steps)")
  
  lexer.index -= count

proc consume*(lexer: GenericLexer): Option[char] =
  if not lexer.isEof():
    inc lexer.index
    some(lexer.input[lexer.index])
  else:
    none(char)

proc ignore*(lexer: GenericLexer, count: uint = 1'u) =
  let count = min(count, lexer.input.len.uint - lexer.index)
  lexer.index += count

proc consume*(lexer: GenericLexer, segment: string | char): bool =
  if not lexer.expect(segment):
    return false
  
  when segment is string:
    lexer.ignore(segment.len.uint)
  else:
    lexer.ignore(sizeof(segment).uint)

proc consumeEscapedChar*(
  lexer: GenericLexer,
  escape: char = '\\',
  escapeMap: string = "n\nr\rt\tb\bf\f"
): char =
  if not lexer.consume(escape):
    return &lexer.consume()

  let c = lexer.consume()

  for i in countup(0, escapeMap.len - 1, 2):
    if &c == escapeMap[i]:
      return escapeMap[i]

  &c

proc consume*(lexer: GenericLexer, count: uint): string =
  if count == 0:
    return

  let
    start = lexer.index
    length = min(count, lexer.input.len.uint - lexer.index)

  lexer.index += length

  lexer.input[start ..< length]

proc consumeWhile*(
  lexer: GenericLexer, 
  fn: proc(c: char): bool
): string =
  let start = lexer.index

  while not lexer.isEof and fn(lexer.peek()):
    inc lexer.index

  let length = lexer.index - start

  if length == 0:
    return

  lexer.input[start ..< length]

proc consumeAll*(lexer: GenericLexer): string =
  if lexer.isEof():
    return

  let rest = lexer.input[lexer.index ..< lexer.input.len.uint - lexer.index]
  lexer.index = lexer.input.len.uint

  rest

when defined(release) or defined(speed): {.pop.}

proc consumeLine*(lexer: GenericLexer): string =
  let start = lexer.index

  while not lexer.isEof() and lexer.peek() != '\r' and lexer.peek() != '\n':
    inc lexer.index

  let length = lexer.index - start

  lexer.consume('\r')
  lexer.consume('\n')

  if length == 0:
    return

  lexer.input[start ..< length]

proc consumeUntil*(lexer: GenericLexer, stop: string | char): string =
  let start = lexer.index
  
  when stop is char:
    while not lexer.isEof and lexer.peek() != stop:
      inc lexer.index
  else:
    while not lexer.isEof and not lexer.expect(stop):
      inc lexer.index

  let length = lexer.index - start

  if length == 0:
    return

  lexer.input[start ..< length]

proc consumeQuotedString*(lexer: GenericLexer, escape: char): string =
  if not lexer.expect('\'') and not lexer.expect('"'):
    return

  let
    quote = lexer.consume()
    start = lexer.index

  while not lexer.isEof:
    if lexer.expect(escape):
      inc lexer.index
    elif lexer.expect(quote):
      break

    inc lexer.index
  
  let length = lexer.index - start

  if lexer.peek() != quote:
    lexer.index = start - 1
    return

  lexer.ignore()
  lexer.input[start ..< length]

proc consumeDecimalInteger*[T: SomeInteger](
  lexer: Lexer,
  kind: typedesc[T]
): T =
  let unsignedT = case kind
  of int: uint
  of int8: uint8
  of int16: uint16
  of int32: uint32
  of int64: uint64
  of uint: uint
  of uint8: uint8
  of uint16: uint16
  of uint32: uint32
  of uint64: uint64
  else:
    {.error: "Cannot find unsigned equivalent to " & $kind.}

  proc rollback(lexer: Lexer, position: uint = uint.high) {.inline, gcsafe.} =
    lexer.index = if position == uint.high:
      lexer.index
    else:
      position

  var hasMinusSign = false

  if lexer.expect('+') or lexer.expect('-'):
    if lexer.consume('-'):
      hasMinusSign = true

  var numberStr = lexer.consumeWhile(
    (c) => c.isAlphaAscii()
  )

  if numberStr.len < 1:
    raise newException(ValueError, "Empty value consumed whilst consuming integral")
  
  let number = parseUint(numberStr)

  if not hasMinusSign:
    if unsignedT.high < number:
      raise newException(ValueError, "Unsigned integer out of range: " & $number)
    
    return number
  else:
    if 

proc remaining*(lexer: GenericLexer): string {.inline.} =
  lexer.input[lexer.index ..< lexer.input.len]
