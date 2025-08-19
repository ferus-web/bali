## Baseline JIT for AMD64 SystemV systems

import std/[logging, hashes, posix, tables, options, streams]
import pkg/bali/runtime/compiler/base, pkg/bali/runtime/vm/heap/boehm
import pkg/[shakar]
import
  pkg/bali/runtime/vm/[atom, shared],
  pkg/bali/runtime/vm/interpreter/resolver,
  pkg/bali/runtime/compiler/amd64/[common, native_forwarding],
  pkg/bali/internal/assembler/amd64

type BaselineJIT* = object of AMD64Codegen

proc prepareAtomAddCall(cgen: var BaselineJIT, index: int64) =
  # Signature for addAtom is:
  # proc(vm: var PulsarInterpreter, atom: JSValue, index: uint): void
  cgen.s.sub(regRsp.reg, 8)
  cgen.s.mov(regRdi, cast[int64](cgen.vm)) # pass the pointer to the vm
  cgen.s.mov(reg(regRsi), regRax) # The JSValue
  cgen.s.mov(regRdx, index) # The index
  cgen.s.call(cgen.callbacks.addAtom)
  cgen.s.add(regRsp.reg, 8)

proc prepareAtomGetCall(cgen: var BaselineJIT, index: int64) =
  # proc rawGet(vm: PulsarInterpreter, index: uint): JSValue
  cgen.s.sub(regRsp.reg, 8)
  cgen.s.mov(regRdi, cast[int64](cgen.vm))
  cgen.s.mov(regRsi, index)
  cgen.s.call(cgen.callbacks.getAtom)
  cgen.s.add(regRsp.reg, 8)

  # The output will be in rax

proc dump*(cgen: var BaselineJIT, file: string) =
  var stream = newFileStream(file, fmWrite)
  stream.writeData(cgen.s.data[0].addr, 0x10000)
  stream.close()

proc patchJumpPoints*(cgen: var BaselineJIT) =
  warn "TODO: Implement jump-point patching"
  unreachable

  for index, offset in cgen.patchJmpOffsets:
    cgen.s.offset = offset
    cgen.s.jmp(cgen.bcToNativeOffsetMap[index])

proc emitNativeCode*(cgen: var BaselineJIT, clause: Clause): bool =
  for i, op in clause.operations:
    var op = op # FIXME: stupid ugly hack

    if not op.resolved:
      clause.resolve(op)

    cgen.bcToNativeOffsetMap &= cgen.s.label()

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
      cgen.s.call(allocInt)
      cgen.s.add(regRsp.reg, 8)

      cgen.prepareAtomAddCall(int64(&op.arguments[0].getInt()))
    of LoadUint:
      cgen.s.mov(regRdi, int64(&op.arguments[1].getInt()))
      cgen.s.sub(regRsp.reg, 8)
      cgen.s.call(allocUInt)
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
    of WriteField:
      prepareLoadString(cgen, &op.arguments[1].getStr())

      cgen.s.sub(regRsp.reg, 8)
      cgen.s.mov(regRdi, cast[int64](cgen.vm))
      cgen.s.mov(regRsi, &op.arguments[0].getInt())
      cgen.s.mov(regRdx, &op.arguments[2].getInt())
      cgen.s.mov(regRcx.reg, regR8)
      cgen.s.call(cgen.callbacks.writeField)
      cgen.s.add(regRsp.reg, 8)
    of Mult:
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

      # Multiply [1] and [2], then box [1]
      cgen.s.mulsd(regXmm0, regXmm1.reg)
      cgen.s.sub(regRsp.reg, 8)
      cgen.s.call(allocFloat)
      cgen.s.add(regRsp.reg, 8)

      prepareAtomAddCall(cgen, &op.arguments[0].getInt())
    of Div:
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
      cgen.s.movsd(regXmm1, regXmm0.reg)
      cgen.s.movq(regXmm0, regR9.reg)

      # Divide [1] and [2], then box [1]
      cgen.s.ddivsd(regXmm0, regXmm1.reg)
      cgen.s.sub(regRsp.reg, 8)
      cgen.s.call(allocFloat)
      cgen.s.add(regRsp.reg, 8)

      prepareAtomAddCall(cgen, &op.arguments[0].getInt())
    of Sub:
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

      # Subtract [1] and [2], then box [1]
      cgen.s.subsd(regXmm0, regXmm1.reg)
      cgen.s.sub(regRsp.reg, 8)
      cgen.s.call(allocFloat)
      cgen.s.add(regRsp.reg, 8)

      prepareAtomAddCall(cgen, &op.arguments[0].getInt())
    #[ of GreaterThanInt:
      # Now this one's a bit complex.
      # This is the VM's behaviour:
      # If a > b, jump 1 op ahead.
      # Else, jump 2 ops ahead.
      #
      # Now, we need to keep track of what offsets we need to jump to,
      # since 1 VM op can generate multiple ops in x86-64 asm.
      # One wrong mistake, and it all blows up.
      prepareAtomGetCall(cgen, &op.arguments[0].getInt())
      cgen.s.mov(regRdi.reg, regRax)

      cgen.s.sub(regRsp.reg, 8)
      cgen.s.call(getRawFloat)
      cgen.s.add(regRsp.reg, 8)

      cgen.s.movq(regR9.reg, regXmm0)
      cgen.s.push(regR9.reg)

      prepareAtomGetCall(cgen, &op.arguments[1].getInt())
      cgen.s.mov(regRdi.reg, regRax)

      cgen.s.sub(regRsp.reg, 16)
      cgen.s.call(getRawFloat)
      cgen.s.add(regRsp.reg, 16)
      
      cgen.s.movsd(regXmm1.reg, regXmm0)
      cgen.s.pop(regR9.reg)
      cgen.s.movq(regXmm0, regR9.reg)

      # We need to patch this later
      cgen.s.ucomisd(regXmm0, regXmm1.reg)
      cgen.patchJmpOffsets[i] = cgen.s.offset
      cgen.s.jmp(cast[BackwardsLabel](0x0))
    of Jump:
      cgen.patchJmpOffsets[&op.arguments[0].getInt()] = cgen.s.offset
      cgen.s.jmp(cast[BackwardsLabel](0x0)) ]#
    of Increment:
      prepareAtomGetCall(cgen, &op.arguments[0].getInt())
      cgen.s.mov(regRdi.reg, regRax)

      cgen.s.sub(regRsp.reg, 8)
      cgen.s.call(getRawFloat)
      cgen.s.add(regRsp.reg, 8)

      cgen.s.mov(regR9, 0x3FF0000000000000)
        # FIXME: This is wasteful. Surely there's a less awful way to do this.
      cgen.s.movq(regXmm1, regR9.reg)

      cgen.s.addsd(regXmm0, regXmm1.reg)
      cgen.s.sub(regRsp.reg, 8)
      cgen.s.call(allocFloat)
      cgen.s.add(regRsp.reg, 8)

      prepareAtomAddCall(cgen, &op.arguments[0].getInt())
    of Decrement:
      prepareAtomGetCall(cgen, &op.arguments[0].getInt())
      cgen.s.mov(regRdi.reg, regRax)

      cgen.s.sub(regRsp.reg, 8)
      cgen.s.call(getRawFloat)
      cgen.s.add(regRsp.reg, 8)

      cgen.s.mov(regR9, 0x3FF0000000000000)
        # FIXME: This is wasteful. Surely there's a less awful way to do this.
      cgen.s.movq(regXmm1, regR9.reg)

      cgen.s.subsd(regXmm0, regXmm1.reg)
      cgen.s.sub(regRsp.reg, 8)
      cgen.s.call(allocFloat)
      cgen.s.add(regRsp.reg, 8)

      prepareAtomAddCall(cgen, &op.arguments[0].getInt())
    else:
      debug "jit/amd64: cannot compile op: " & $op.opcode
      debug "jit/amd64: bailing out, this clause will be interpreted"
      return false

  cgen.s.ret()
  # patchJumpPoints(cgen)

  true

proc compile*(cgen: var BaselineJIT, clause: Clause): Option[JITSegment] =
  if cgen.cached.contains(clause.name):
    debug "jit/amd64: found cached version of JIT'd clause"
    return some(cgen.cached[clause.name])

  cgen.bcToNativeOffsetMap = newSeqOfCap[BackwardsLabel](128)

  if emitNativeCode(cgen, clause):
    info "jit/amd64: compilation successful for clause " & $clause.name
    let fn = cast[JITSegment](cgen.s.data)
    cgen.cached[clause.name] = fn

    some(fn)
  else:
    debug "jit/amd64: failed to emit native code for clause."

    none(JITSegment)

proc initAMD64BaselineCodegen*(vm: pointer, callbacks: VMCallbacks): BaselineJIT =
  info "jit/amd64: initializing baseline jit"

  var cgen = BaselineJIT(vm: vm, callbacks: callbacks, s: initAssemblerX64())
  cgen.pageSize = sysconf(SC_PAGESIZE)
  debug "jit/amd64: page size is " & $cgen.pageSize

  move(cgen)
