import std/[options, unittest]
import bali/grammar/prelude
import ../common
enableLogging()

var tokenizer = newTokenizer("""
/* Hello there!
 * This is a multiline comment
*/

# This is a single line comment

const x = "hello world"
console.log(x)

assert(x !== "hyello wlord")
""")
let tokens = tokenizer.tokenize(
  TokenizerOpts(
    ignoreWhitespace: true
  )
)

print tokens
