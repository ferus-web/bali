import pkg/bali/runtime/vm/runtime/pulsar/types

const
  hasJITSupport* = defined(amd64) and defined(unix)

type
  VMCallbacks* = object
    addAtom*: pointer
    getAtom*: pointer
    copyAtom*: pointer # proc(vm: var PulsarInterpreter, source, dest: uint)
    resetArgs*: pointer
    passArgument*: pointer
    callBytecodeClause*: pointer
    invoke*: pointer

  JITSegment* = proc(): void {.cdecl.}

export Clause
