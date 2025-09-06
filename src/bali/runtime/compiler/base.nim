import pkg/bali/runtime/vm/interpreter/types

const hasJITSupport* = defined(amd64) and defined(unix)

type
  Tier* {.pure, size: sizeof(uint8).} = enum
    Baseline
    Midtier

  VMCallbacks* = object
    addAtom*: pointer
    getAtom*: pointer
    copyAtom*: pointer # proc(vm: var PulsarInterpreter, source, dest: uint)
    resetArgs*: pointer
    passArgument*: pointer
    callBytecodeClause*: pointer
    invoke*: pointer
    invokeStr*: pointer
    readVectorRegister*: pointer
    zeroRetval*: pointer
    readScalarRegister*: pointer
    writeField*: pointer
    addRetval*: pointer
    createField*: pointer
    allocEncodedFloat*: pointer
    allocFloat*: pointer
    alloc*: pointer
    allocBytecodeCallable*: pointer
    allocStr*: pointer
    allocInt*: pointer
    getProperty*: pointer

  JITSegment* = proc(): void {.cdecl.}

export Clause
