import std/[tables, posix]
import
  pkg/bali/runtime/compiler/base,
  pkg/bali/runtime/compiler/amd64/native_forwarding,
  pkg/bali/platform/libc,
  pkg/bali/internal/assembler/amd64

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

    dumpIrForFuncs*: seq[string]

proc `=destroy`*(cgen: AMD64Codegen) =
  for cnst in cgen.cpool:
    dealloc(cast[pointer](cnst))

  free(cgen.s.data)

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

export libc
