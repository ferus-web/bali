## Object/value prototypes

import std/[logging]
import mirage/ir/generator
import mirage/atom
import bali/runtime/types
import bali/grammar/prelude
import bali/runtime/atom_obj_variant

type
  NativeFunction* = proc(args: seq[MAtom]): MAtom
  Field* = AtomOrFunction[NativeFunction]

  FieldManager* = object
    fields*: seq[seq[Field]]

proc resolveFieldAndStore*(
    resolver: var PrototypeResolver, runtime: Runtime, stmt: Statement, dest: string
) =
  runtime.ir.passArgument(runtime.index("ident", internalIndex(stmt)))
  runtime.ir.passArgument(runtime.index("field", internalIndex(stmt)))
  runtime.ir.passArgument(runtime.index("dest", internalIndex(stmt)))
  runtime.ir.call("BALI_RESOLVE_FIELD_AND_STORE")

proc resolveFieldAndStore*(
    resolver: var PrototypeResolver, runtime: Runtime, stmt: Statement
) =
  runtime.ir.passArgument(runtime.index("ident", internalIndex(stmt)))
  runtime.ir.passArgument(runtime.index("field", internalIndex(stmt)))
  runtime.ir.call("BALI_RESOLVE_FIELD_AND_CALL")

proc newPrototypeResolver*(): PrototypeResolver {.inline.} =
  PrototypeResolver()