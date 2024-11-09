import bali/grammar/statement
import pretty

print createFieldAccess(@[
  "myUrl",
  "hostname",
  "length"
]) # `myUrl.hostname.length`
