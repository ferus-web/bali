import std/[logging, posix, hashes, tables, options]
import pkg/bali/runtime/compiler/base
import pkg/catnip/[x64assembler],
       pkg/pretty
import pkg/bali/runtime/vm/atom,
       pkg/bali/runtime/vm/runtime/shared

type
  AMD64Codegen* = object
    cached*: Table[Hash, JITSegment]
    s*: AssemblerX64
    callbacks*: VMCallbacks
    vm*: pointer

    pageSize: int64

proc allocateNativeSegment(cgen: var AMD64Codegen) =
  debug "jit/amd64: allocating buffer for assembler"

  # TODO: Unhardcode this. Perhaps we can have something that takes in a clause and runs an upper bound estimate of how much memory its native repr will be in?
  if (let code = posix_memalign(cgen.s.data.addr, cgen.pageSize.csize_t, 0x10000); code != 0):
    warn "jit/amd64: failed to allocate buffer for assembler: posix_memalign() returned " & $code
    return

  debug "jit/amd64: allocated buffer successfully; making it executable"
  if (let code = mprotect(cgen.s.data, 0x10000, PROT_READ or PROT_WRITE or PROT_EXEC); code != 0):
    warn "jit/amd64: failed to mark buffer as executable: mprotect() returned: " & $code

proc emitNativeCode*(cgen: var AMD64Codegen, clause: Clause): bool =
  for op in clause.operations:
    print op.opcode
    case op.opcode
    of LoadUndefined:
      cgen.s.sub(reg(regRsp), 8)
      cgen.s.call(undefined) # we have the output in rax now
      cgen.s.add(reg(regRsp), 8)
      
      cgen.s.mov(reg(regRdi), cast[uint64](cgen.vm)) # pass the pointer to the vm
      cgen.s.mov(reg(regRdi), regRax)
      cgen.s.call(cgen.callbacks.addAtom)
    else:
      error "jit/amd64: cannot compile op: " & $op.opcode
      error "jit/amd64: bailing out, this clause will be interpreted"
      return false

  true

proc compile*(cgen: var AMD64Codegen, clause: Clause): Option[JITSegment] =
  let hashed = clause.hash()
  if cgen.cached.contains(hashed):
    debug "jit/amd64: found cached version of JIT'd clause"
    return some(cgen.cached[hashed])

  allocateNativeSegment(cgen)
  if emitNativeCode(cgen, clause):
    some(cast[JITSegment](cgen.s.data))
  else:
    none(JITSegment)

proc initAMD64Codegen*(callbacks: VMCallbacks): AMD64Codegen =
  info "jit/amd64: initializing"

  var cgen = AMD64Codegen(
    s: initAssemblerX64(nil),
    callbacks: callbacks
  )
  cgen.pageSize = sysconf(SC_PAGESIZE)
  debug "jit/amd64: page size is " & $cgen.pageSize

  move(cgen)
