import std/[options, tables, logging]
import pkg/bali/grammar/prelude
import pkg/bali/runtime/prelude
import pkg/bali/runtime/abstract/coercion
import pkg/bali/runtime/vm/atom
import pretty, colored_logger

let parser = newParser(
  """
console.log(EpicClass.myName)
"""
) # I've grown tired of manually writing the AST :(

let program = parser.parse()
print program

addHandler newColoredLogger()
setLogFilter(lvlAll)

type EpicClass* = object
  myName*: string = "Deine Mutter"

var runtime = newRuntime("t001.js", program)
runtime.registerType(prototype = EpicClass, name = "EpicClass")
runtime.setProperty(EpicClass, "myName", str "Deine Mutter")
runtime.defineFn(
  EpicClass,
  "die",
  proc() =
    quit "Oooops! You killed the engine by invoking that!"
  ,
)
runtime.run()
