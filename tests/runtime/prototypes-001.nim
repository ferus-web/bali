import std/[options]
import bali/grammar/prelude
import bali/runtime/prelude
import bali/runtime/abstract/coercion
import mirage/atom
import pretty

let parser = newParser(
  """
console.log(EpicClas)
EpicClass.die()
"""
) # I've grown tired of manually writing the AST :(

let program = parser.parse()

type EpicClass* = object
  myName*: string

var runtime = newRuntime("t001.js", program)
runtime.registerType(prototype = EpicClass, name = "EpicClass")
runtime.defineFn(
  EpicClass,
  "die",
  proc() =
    echo "Oooops! You killed the engine by invoking that!"
    quit(0),
)
runtime.run()
