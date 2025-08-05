import std/[tables, posix, logging]
import pkg/catnip/x64assembler
import
  pkg/bali/runtime/compiler/base,
  pkg/bali/runtime/compiler/amd64/native_forwarding,
  pkg/bali/platform/libc

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

    dumpIrForFuncs*: seq[string]

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
    raise newException(Defect, "Cannot allocate assembler's code buffer!")

  debug "jit/amd64: allocated buffer successfully; making it executable"
  if (
    let code = mprotect(cgen.s.data, 0x10000, PROT_READ or PROT_WRITE or PROT_EXEC)
    code != 0
  ):
    warn "jit/amd64: failed to mark buffer as executable: mprotect() returned: " & $code
    raise newException(Defect, "Cannot mark assembler's code buffer as executable!")

proc prepareGCAlloc*(cgen: var AMD64Codegen, size: uint) =
  cgen.s.mov(regRdi, size.int64)
  cgen.s.sub(regRsp.reg, 8)
  cgen.s.call(allocRaw)
  cgen.s.add(regRsp.reg, 8)

proc prepareLoadString*(cgen: var AMD64Codegen, str: cstring) =
  prepareGCAlloc(cgen, str.len.uint)

  # the GC allocated memory's pointer is in rax.
  # we're going to copy stuff from our const pool into it

  var cstr = cast[cstring](alloc(str.len + 1))
  for i, c in str:
    cstr[i] = c

  cgen.cpool.add(cstr)
  cgen.s.push(regRax.reg) # save the pointer in rax
  cgen.s.mov(regRdi.reg, regRax)
  cgen.s.mov(regRsi, cast[int64](cast[pointer](cstr[0].addr)))
  cgen.s.mov(regRdx, int64(str.len))

  cgen.s.sub(regRsp.reg, 16)
  cgen.s.call(copyRaw)
  cgen.s.add(regRsp.reg, 16)

  cgen.s.pop(regR8.reg) # get the pointer that was in rax which is likely gone now

export x64assembler, libc
