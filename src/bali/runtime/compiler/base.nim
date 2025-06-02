import pkg/bali/runtime/vm/runtime/pulsar/types

const
  hasJITSupport* = defined(amd64) and defined(unix)

type
  VMCallbacks* = object
    addAtom*: pointer

  JITSegment* = proc(): void {.cdecl.}

export Clause
