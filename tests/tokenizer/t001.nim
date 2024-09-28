import std/[os, options, unittest]
import bali/grammar/prelude
import ../common
enableLogging()

var tokenizer = newTokenizer(readFile paramStr 1)
let tokens = tokenizer.tokenize(TokenizerOpts(ignoreWhitespace: true))

print tokens
