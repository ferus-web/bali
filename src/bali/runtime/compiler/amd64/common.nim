import std/[tables]
import pkg/catnip/x64assembler
import pkg/bali/runtime/compiler/base

type
  ConstantPool* = seq[cstring]

  AMD64Codegen* = object of RootObj
    cached*: Table[string, JITSegment]
    s*: AssemblerX64
    callbacks*: VMCallbacks
    vm*: pointer
    cpool*: ConstantPool

    ## This vector maps bytecode indices
    ## to native offsets in executable memory.
    bcToNativeOffsetMap*: seq[BackwardsLabel]
    patchJmpOffsets*: Table[int, int]

    pageSize*: int64

proc free(p: pointer): void {.importc, header: "<stdlib.h>".}

proc `=destroy`*(cgen: AMD64Codegen) =
  for cnst in cgen.cpool:
    dealloc(cast[pointer](cnst))

  free(cgen.s.data)

export x64assembler
