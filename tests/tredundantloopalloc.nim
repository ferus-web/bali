import bali/runtime/optimize/redundant_loop_allocations
import bali/runtime/prelude
import bali/grammar/prelude
import pkg/pretty

let x = eliminateRedundantLoopAllocations(
  runtime = nil,
  body = Scope(
    stmts: @[
      Statement(
        kind: CreateImmutVal,
        imIdentifier: "meow",
        imAtom: str "hi :3"
      ),
      callFunction("deine_mutter").call(@[CallArg(kind: cakIdent, ident: "meow")])
    ]
  )
)
print x
