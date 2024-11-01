import std/[options]
import bali/grammar/prelude
import bali/runtime/prelude
import bali/runtime/abstract/coercion
import mirage/atom
import pretty

let parser = newParser("""
EpicClass.die()
""") # I've grown tired of manually writing the AST :(

let program = parser.parse()

type
  EpicClass* = object
    myName*: string = "Deine Mutter"

var runtime = newRuntime("t001.js", program)
runtime.registerType(
  prototype = EpicClass,
  name = "EpicClass"
)
runtime.defineFn(
  EpicClass,
  "die",
  proc =
    quit "Oooops! You killed the engine by invoking that!"
)
runtime.run()
