## Function type implementation
##
## Copyright (C) 2025 Trayambak Rai (xtrayambak@disroot.org)
import
  pkg/bali/runtime/vm/atom,
  pkg/bali/internal/sugar,
  pkg/bali/stdlib/errors,
  pkg/bali/runtime/[atom_helpers, types, bridge, construction]

type JSFunction* = object
  `@ inner`: JSValue

func toJSFunction*(value: JSValue): JSFunction =
  JSFunction(`@ inner`: value)

proc generateBindings*(runtime: Runtime) =
  runtime.registerType("Function", JSFunction)
  runtime.defineConstructor(
    "Function",
    proc() =
      runtime.typeError("The Function constructor is not implemented yet.")
        # TODO: Implement this. I think we'll need to do a lot of internal plumbing to make this possible.
    ,
  )

  runtime.definePrototypeFn(
    JSFunction,
    "toString",
    proc(this: JSValue) =
      let inner = &this.tagged("inner")

      case inner.kind
      of BytecodeCallable:
        ret "function " & inner.clauseName & "() { }"
          # TODO: These atoms should carry the source code info with them.
      of NativeCallable:
        ret "function () {\n      [native code]\n}"
      else:
        unreachable,
  )
