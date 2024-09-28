import std/[os, tables]
import bali/grammar/prelude
import bali/runtime/prelude
import pretty
import ../common

enableLogging()
var ast = newAST()
var args: PositionedArguments
args.pushAtom(str "https://github.com")

ast.appendToCurrentScope(callAndStoreMut("url", call("URL.parse", args)))
var args2: PositionedArguments
args2.pushIdent("url")

ast.appendToCurrentScope(call("console.log", args2))

let runtime = newRuntime("t003.js", ast)
runtime.run()
