import std/[tables, posix, logging]
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

proc allocateNativeSegment*(cgen: var AMD64Codegen) =
  debug "jit/amd64: allocating buffer for assembler"

  # TODO: Unhardcode this. Perhaps we can have something that takes in a clause and runs an upper bound estimate of how much memory its native repr will be in?
  cgen.s = initAssemblerX64(nil)

  if (
    let code = posix_memalign(cgen.s.data.addr, cgen.pageSize.csize_t, 0x10000)
    code != 0
  ):
    warn "jit/amd64: failed to allocate buffer for assembler: posix_memalign() returned " &
      $code
    return

  debug "jit/amd64: allocated buffer successfully; making it executable"
  if (
    let code = mprotect(cgen.s.data, 0x10000, PROT_READ or PROT_WRITE or PROT_EXEC)
    code != 0
  ):
    warn "jit/amd64: failed to mark buffer as executable: mprotect() returned: " & $code

export x64assembler
