import std/[options, tables, logging]
import bali/grammar/prelude
import bali/runtime/prelude
import bali/runtime/abstract/coercion
import mirage/atom
import pretty, colored_logger

let parser = newParser(
  """
console.log(EpicClass.myName)
console.log(EpicClass.stats.accessible)
"""
) # I've grown tired of manually writing the AST :(

let program = parser.parse()
print program

addHandler newColoredLogger()
setLogFilter(lvlAll)

type
  Stats* = object
    accessible*: string = "Yes, perhaps."

  EpicClass* = object
    myName*: string = "Deine Mutter"
    stats*: Stats

var runtime = newRuntime("t001.js", program)
runtime.registerType(prototype = EpicClass, name = "EpicClass")
runtime.defineFn(
  EpicClass,
  "die",
  proc() =
    quit "Oooops! You killed the engine by invoking that!"
  ,
)
runtime.run()