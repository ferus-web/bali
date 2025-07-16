## Converts a stream of MIR tokens into an operation, if possible.
##

import std/[options]
import ../[shared, tokenizer], operation

proc nextOperation*(dtok: var Tokenizer): Option[Operation] {.inline.} =
  discard dtok.consumeWhitespace()

  var op = Operation()
  let opIdx = dtok.nextExcludingWhitespace()

  if opIdx.kind != tkInteger:
    return

  op.index = opIdx.integer.uint64

  let opCode = dtok.nextExcludingWhitespace()
  op.opcode = toOp(opCode.op)

  while not dtok.isEof():
    let arg = dtok.next()

    if arg.kind in [tkQuotedString, tkInteger, tkDouble, tkIdent]:
      op.rawArgs.add(arg)
      continue

    break

  discard dtok.consumeWhitespace()
  some op
