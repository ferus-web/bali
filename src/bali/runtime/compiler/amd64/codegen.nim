## Baseline JIT for AMD64 SystemV systems

import std/[logging, posix, hashes, tables, options, streams]
import pkg/bali/runtime/compiler/base, pkg/bali/runtime/vm/heap/boehm
import pkg/catnip/[x64assembler], pkg/[shakar]
import
  pkg/bali/runtime/vm/atom,
  pkg/bali/runtime/vm/runtime/shared,
  pkg/bali/runtime/vm/runtime/pulsar/resolver,
  pkg/bali/runtime/atom_helpers

type
  ConstantPool* = seq[cstring]

  AMD64Codegen* = object
    cached*: Table[Hash, JITSegment]
    s*: AssemblerX64
    callbacks*: VMCallbacks
    vm*: pointer
    cpool*: ConstantPool

    pageSize: int64

proc allocateNativeSegment(cgen: var AMD64Codegen) =
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

proc prepareAtomAddCall(cgen: var AMD64Codegen, index: int64) =
  # Signature for addAtom is:
  # proc(vm: var PulsarInterpreter, atom: JSValue, index: uint): void
  cgen.s.sub(regRsp.reg, 8)
  cgen.s.mov(regRdi, cast[int64](cgen.vm)) # pass the pointer to the vm
  cgen.s.mov(reg(regRsi), regRax) # The JSValue
  cgen.s.mov(regRdx, index) # The index
  cgen.s.call(cgen.callbacks.addAtom)
  cgen.s.add(regRsp.reg, 8)

proc prepareAtomGetCall(cgen: var AMD64Codegen, index: int64) =
  # proc rawGet(vm: PulsarInterpreter, index: uint): JSValue
  cgen.s.sub(regRsp.reg, 8)
  cgen.s.mov(regRdi, cast[int64](cgen.vm))
  cgen.s.mov(regRsi, index)
  cgen.s.call(cgen.callbacks.getAtom)
  cgen.s.add(regRsp.reg, 8)

  # The output will be in rax

proc createFieldRaw*(atom: JSValue, field: cstring) {.cdecl.} =
  atom[$field] = undefined()

proc getRawFloat(atom: JSValue): float64 {.cdecl.} =
  &atom.getNumeric()

proc allocFloat(v: float64): JSValue {.cdecl.} =
  floating v

proc allocFloatEncoded(v: int64): JSValue {.cdecl.} =
  allocFloat(cast[float64](v))

proc dump*(cgen: var AMD64Codegen, file: string) =
  var stream = newFileStream(file, fmWrite)
  stream.writeData(cgen.s.data[0].addr, 0x10000)
  stream.close()

proc allocRaw(size: int64): pointer {.cdecl.} =
  baliAlloc(size)

proc copyRaw(dest, source: pointer, size: uint) {.cdecl.} =
  copyMem(dest, source, size)

proc allocBytecodeCallable(str: cstring): JSValue {.cdecl.} =
  bytecodeCallable($str)

proc strRaw(value: cstring): JSValue {.cdecl.} =
  str($value)

proc prepareGCAlloc(cgen: var AMD64Codegen, size: uint) =
  cgen.s.mov(regRdi, size.int64)
  cgen.s.sub(regRsp.reg, 8)
  cgen.s.call(allocRaw)
  cgen.s.add(regRsp.reg, 8)

proc prepareLoadString(cgen: var AMD64Codegen, str: cstring) =
  prepareGCAlloc(cgen, str.len.uint)

  # the GC allocated memory's pointer is in rax.
  # we're going to copy stuff from our const pool into it

  var cstr = cast[cstring](baliAlloc(str.len + 1))
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

proc emitNativeCode*(cgen: var AMD64Codegen, clause: Clause): bool =
  for op in clause.operations:
    var op = op # FIXME: stupid ugly hack

    if not op.resolved:
      clause.resolve(op)

    case op.opcode
    of LoadUndefined:
      cgen.s.sub(reg(regRsp), 8)
      cgen.s.call(undefined) # we have the output in rax now
      cgen.s.add(reg(regRsp), 8)

      cgen.prepareAtomAddCall(int64(&op.arguments[0].getInt()))
    of LoadNull:
      cgen.s.sub(reg(regRsp), 8)
      cgen.s.call(null) # we have the output in rax now
      cgen.s.add(reg(regRsp), 8)

      cgen.prepareAtomAddCall(int64(&op.arguments[0].getInt()))
    of LoadFloat:
      case op.arguments[1].kind
      of String:
        # it's NaN
        cgen.s.mov(regRdi, 0x7FF0000000000001'i64)
      of Float:
        cgen.s.mov(regRdi, cast[int64](&op.arguments[1].getFloat()))
      else:
        unreachable

      cgen.s.sub(regRsp.reg, 8)
      cgen.s.call(allocFloatEncoded)
      cgen.s.add(reg(regRsp), 8)

      cgen.prepareAtomAddCall(int64(&op.arguments[0].getInt()))
    of LoadBool:
      cgen.s.mov(regRdi, int32(&op.arguments[1].getBool()))
      cgen.s.sub(regRsp.reg, 8)
      cgen.s.call(boolean)
      cgen.s.add(reg(regRsp), 8)

      cgen.prepareAtomAddCall(int64(&op.arguments[0].getInt()))
    of CreateField:
      prepareLoadString(cgen, &op.arguments[2].getStr()) # puts the string in r8

      prepareAtomGetCall(cgen, &op.arguments[0].getInt()) # put the JSValue in rax
      cgen.s.mov(regRdi.reg, regRax) # put the JSValue as the first arg
      cgen.s.mov(regRsi.reg, regR8)

      cgen.s.sub(regRsp.reg, 8)
      cgen.s.call(createFieldRaw)
        # it gets the JSValue just fine, but rsi is an empty cstring (it points to a totally different location???)
      cgen.s.add(regRsp.reg, 8)
    of LoadInt:
      cgen.s.mov(regRdi, int64(&op.arguments[1].getInt()))
      cgen.s.sub(regRsp.reg, 8)
      cgen.s.call(integer)
      cgen.s.add(regRsp.reg, 8)

      cgen.prepareAtomAddCall(int64(&op.arguments[0].getInt()))
    of LoadUint:
      cgen.s.mov(regRdi, int64(&op.arguments[1].getInt()))
      cgen.s.sub(regRsp.reg, 8)
      cgen.s.call(integer)
      cgen.s.add(regRsp.reg, 8)

      cgen.prepareAtomAddCall(int64(&op.arguments[0].getInt()))
    of Add:
      prepareAtomGetCall(cgen, &op.arguments[0].getInt())
      cgen.s.mov(regRdi.reg, regRax)

      cgen.s.sub(regRsp.reg, 8)
      cgen.s.call(getRawFloat)
      cgen.s.add(regRsp.reg, 8)

      # Move the first float to the stack, making way for the second one
      cgen.s.movq(regR9.reg, regXmm0)
      cgen.s.push(regR9.reg)

      prepareAtomGetCall(cgen, &op.arguments[1].getInt())
      cgen.s.mov(regRdi.reg, regRax)

      cgen.s.sub(regRsp.reg, 16)
      cgen.s.call(getRawFloat)
      cgen.s.add(regRsp.reg, 16)

      cgen.s.pop(regR9.reg)
      cgen.s.movq(regXmm1, regR9.reg)

      # Add [1] and [2], then box [1]
      cgen.s.addsd(regXmm0, regXmm1.reg)
      cgen.s.sub(regRsp.reg, 8)
      cgen.s.call(allocFloat)
      cgen.s.add(regRsp.reg, 8)

      prepareAtomAddCall(cgen, &op.arguments[0].getInt())
    of CopyAtom:
      # TODO: implement this in pure asm
      # it's a very simple op and we can probably gain a lot of performance by not unnecessarily calling this function
      cgen.s.sub(regRsp.reg, 8)
      cgen.s.mov(regRdi, cast[int64](cgen.vm))
      cgen.s.mov(regRsi, int64(&op.arguments[0].getInt()))
      cgen.s.mov(regRdx, int64(&op.arguments[1].getInt()))
      cgen.s.call(cgen.callbacks.copyAtom)
      cgen.s.add(regRsp.reg, 8)
    of ResetArgs:
      # TODO: same as above
      cgen.s.sub(regRsp.reg, 8)
      cgen.s.mov(regRdi, cast[int64](cgen.vm))
      cgen.s.call(cgen.callbacks.resetArgs)
      cgen.s.add(regRsp.reg, 8)
    of PassArgument:
      # TODO: sigh.. same as above
      cgen.s.sub(regRsp.reg, 8)
      cgen.s.mov(regRdi, cast[int64](cgen.vm))
      cgen.s.mov(regRsi, int64(&op.arguments[0].getInt()))
      cgen.s.call(cgen.callbacks.passArgument)
      cgen.s.add(regRsp.reg, 8)
    of LoadStr:
      prepareLoadString(cgen, &op.arguments[1].getStr()) # puts the string in r8

      # Allocate the string on GC'd memory
      # FIXME: Can't we just reuse the same heap memory used in the prep-load-string call?
      cgen.s.sub(regRsp.reg, 8)
      cgen.s.mov(regRdi.reg, regR8)
      cgen.s.call(strRaw)
      cgen.s.add(regRsp.reg, 8)

      prepareAtomAddCall(cgen, &op.arguments[0].getInt())
    of Call:
      # TODO: check if the clause has been JIT'd too. If so,
      # use the compiled version

      prepareLoadString(cgen, &op.arguments[0].getStr())

      cgen.s.sub(regRsp.reg, 8)
      cgen.s.mov(regRdi, cast[int64](cgen.vm))
      cgen.s.mov(regRsi.reg, regR8)
      cgen.s.call(cgen.callbacks.callBytecodeClause)
      cgen.s.add(regRsp.reg, 8)
    of Invoke:
      let target = op.arguments[0]

      var fun = cgen.callbacks.invoke

      case target.kind
      of String:
        prepareLoadString(cgen, cstring(&target.getStr()))
        cgen.s.mov(regRsi.reg, regR8)
        fun = cgen.callbacks.invokeStr
      else:
        cgen.s.mov(regRsi, &target.getInt())

      cgen.s.sub(regRsp.reg, 8)
      cgen.s.mov(regRdi, cast[int64](cgen.vm))
      cgen.s.call(move(fun))
      cgen.s.add(regRsp.reg, 8)
    of LoadBytecodeCallable:
      prepareLoadString(cgen, &op.arguments[1].getStr())

      cgen.s.sub(regRsp.reg, 8)
      cgen.s.mov(regRdi.reg, regR8)
      cgen.s.call(allocBytecodeCallable)
      cgen.s.add(regRsp.reg, 8)

      cgen.prepareAtomAddCall(int64(&op.arguments[0].getInt()))
    of ReadRegister:
      cgen.s.sub(regRsp.reg, 8)
      cgen.s.mov(regRdi, cast[int64](cgen.vm))
      cgen.s.mov(regRsi, cast[int64](&op.arguments[0].getInt()))
      cgen.s.mov(regRdx, cast[int64](&op.arguments[1].getInt()))

      if op.arguments.len > 2:
        # We're reading a vector register (a register that dynamically grows)
        cgen.s.mov(regRcx, cast[int64](&op.arguments[2].getInt()))
        cgen.s.call(cgen.callbacks.readVectorRegister)
      else:
        # We're reading a scalar register.
        cgen.s.call(cgen.callbacks.readScalarRegister)
      cgen.s.add(regRsp.reg, 8)
    of ZeroRetval:
      cgen.s.sub(regRsp.reg, 8)
      cgen.s.mov(regRdi, cast[int64](cgen.vm))
      cgen.s.add(regRsp.reg, 8)
    else:
      error "jit/amd64: cannot compile op: " & $op.opcode
      error "jit/amd64: bailing out, this clause will be interpreted"
      return false

  cgen.s.ret()
  true

proc compile*(cgen: var AMD64Codegen, clause: Clause): Option[JITSegment] =
  let hashed = clause.hash()
  if cgen.cached.contains(hashed):
    debug "jit/amd64: found cached version of JIT'd clause"
    return some(cgen.cached[hashed])

  allocateNativeSegment(cgen)

  if emitNativeCode(cgen, clause):
    cgen.dump("bali-jit-result.bin")
    info "jit/amd64: compilation successful for clause " & $clause.name
    some(cast[JITSegment](cgen.s.data))
  else:
    warn "jit/amd64: failed to emit native code for clause."
    warn "jit/amd64: the partially emitted code will be dumped to `bali-jit-fail.bin`"

    cgen.dump("bali-jit-fail.bin")
    none(JITSegment)

proc initAMD64Codegen*(vm: pointer, callbacks: VMCallbacks): AMD64Codegen =
  info "jit/amd64: initializing"

  var cgen = AMD64Codegen(vm: vm, callbacks: callbacks)
  cgen.pageSize = sysconf(SC_PAGESIZE)
  debug "jit/amd64: page size is " & $cgen.pageSize

  move(cgen)
