## x86-64 assembler
##
## Taken from https://github.com/RSDuck/catnip/blob/main/catnip/x64assembler.nim.
## I have plans to add more CPU-specific instructions soon, so that's why I moved this into the source tree.
##
## Copyright (c) 2021 RSDuck
##
## Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
## 
## The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
## 
## THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
import std/[macros, options]
import pkg/bali/internal/assembler/buffer_alloc

type
  CannotAllocateJITBuffer* = object of Defect

  Register8* = enum
    regAl
    regCl
    regDl
    regBl
    regSpl
    regBpl
    regSil
    regDil
    regR8b
    reg98b
    regR10b
    regR11b
    regR12b
    regR13b
    regR14b
    regR15b

  Register16* = enum
    regAx
    regCx
    regDx
    regBx
    regSp
    regBp
    regSi
    regDi
    regR8w
    regR9w
    regR10w
    regR11w
    regR12w
    regR13w
    regR14w
    regR15w

  Register32* = enum
    regEax
    regEcx
    regEdx
    regEbx
    regEsp
    regEbp
    regEsi
    regEdi
    regR8d
    regR9d
    regR10d
    regR11d
    regR12d
    regR13d
    regR14d
    regR15d

  Register64* = enum
    regRax
    regRcx
    regRdx
    regRbx
    regRsp
    regRbp
    regRsi
    regRdi
    regR8
    regR9
    regR10
    regR11
    regR12
    regR13
    regR14
    regR15

  RegisterXmm* = enum
    regXmm0
    regXmm1
    regXmm2
    regXmm3
    regXmm4
    regXmm5
    regXmm6
    regXmm7
    regXmm8
    regXmm9
    regXmm10
    regXmm11
    regXmm12
    regXmm13
    regXmm14
    regXmm15

  Condition* = enum
    condOverflow
    condNotOverflow
    condBelow
    condNotBelow
    condZero
    condNotZero
    condBequal
    condNbequal
    condSign
    condNotSign
    condParityEven
    condParityOdd
    condLess
    condNotLess
    condLequal
    condNotLequal

  RmScale* = enum
    rmScale1
    rmScale2
    rmScale4
    rmScale8

  RmKind = enum
    rmDirect
    rmIndirectScaled
    rmIndirectScaledAndBase
    rmIndirectGlobal

  Rm*[T] = object
    case kind: RmKind
    of rmDirect:
      when T isnot void:
        directReg: T
    of rmIndirectScaled:
      simpleIndex: Register64
      simpleScale: RmScale
      simpleDisp: int32
    of rmIndirectScaledAndBase:
      base, baseIndex: Register64
      baseScale: RmScale
      baseDisp: int32
    of rmIndirectGlobal:
      globalPtr: pointer

  Rm8* = Rm[Register8]
  Rm16* = Rm[Register16]
  Rm32* = Rm[Register32]
  Rm64* = Rm[Register64]
  RmXmm* = Rm[RegisterXmm]
  RmMemOnly* = Rm[void]

  BackwardsLabel* = distinct int
  ForwardsLabel* = object
    isLongJmp: bool
    offset: int32

  AssemblerX64* = object
    data*: ptr UncheckedArray[byte]
    capacity*: int
    offset*: int

proc `==`*(a, b: BackwardsLabel): bool {.borrow.}
proc `$`*(a: BackwardsLabel): string {.borrow.}

when defined(windows):
  const
    param1* = regRcx
    param2* = regRdx
    param3* = regR8
    param4* = regR9

    stackShadow* = 0x20
else:
  const
    param1* = regRdi
    param2* = regRsi
    param3* = regRdx
    param4* = regRcx

    stackShadow* = 0

const BaseAssemblerSize* {.intdefine: "BaliBaseAssemblerSize".} = 0x10000

proc curAdr*(assembler: AssemblerX64): int64 =
  cast[int64](assembler.data) + assembler.offset

proc dump*(s: AssemblerX64, file: string) =
  assert(s.offset < s.capacity)

  var data = newSeqOfCap[uint8](s.offset)
  var i = 0

  while i < s.offset:
    data &= s.data[i]
    inc i

  writeFile(file, ensureMove(data))

proc initAssemblerX64*(data: ptr UncheckedArray[byte], capacity: int): AssemblerX64 =
  result.data = data
  result.capacity = capacity

proc initAssemblerX64*(): AssemblerX64 =
  var s: AssemblerX64
  s.data = cast[ptr UncheckedArray[byte]](allocateExecutableBuffer(
    uint64(BaseAssemblerSize), readable = true, writable = true
  ))
  s.capacity = BaseAssemblerSize

  ensureMove(s)

proc getFuncStart*[T](assembler: AssemblerX64): T =
  cast[T](assembler.curAdr)

proc label*(assembler: AssemblerX64): BackwardsLabel =
  BackwardsLabel(assembler.offset)

proc fitsInt8(imm: int32): bool =
  int32(cast[int8](imm)) == imm

proc label*(assembler: AssemblerX64, label: ForwardsLabel) =
  let offset = int32(assembler.offset) - label.offset
  if label.isLongJmp:
    copyMem(addr assembler.data[label.offset - 4], unsafeAddr offset, 4)
  else:
    assert offset.fitsInt8()
    copyMem(addr assembler.data[label.offset - 1], unsafeAddr offset, 1)

proc reg*[T](reg: T): Rm[T] =
  Rm[T](kind: rmDirect, directReg: reg)

template declareMemCtors(size: untyped): untyped =
  proc `mem size`*(index: Register64, disp = 0'i32, scale = rmScale1): `Rm size` =
    `Rm size`(
      kind: rmIndirectScaled, simpleIndex: index, simpleScale: scale, simpleDisp: disp
    )

  proc `mem size`*(base, index: Register64, disp = 0'i32, scale = rmScale1): `Rm size` =
    `Rm size`(
      kind: rmIndirectScaledAndBase,
      base: base,
      baseIndex: index,
      baseScale: scale,
      baseDisp: disp,
    )

  proc `mem size`*[T](data: ptr T): `Rm size` =
    `Rm size`(kind: rmIndirectGlobal, globalPtr: data)

declareMemCtors(8)
declareMemCtors(16)
declareMemCtors(32)
declareMemCtors(64)
declareMemCtors(Xmm)
declareMemCtors(MemOnly)

proc isDirectReg[T](rm: Rm[T], reg: T): bool =
  rm.kind == rmDirect and rm.directReg == reg

proc write[T](assembler: var AssemblerX64, data: T) =
  assert assembler.offset + sizeof(T) < assembler.capacity,
    "Assembler has run out of buffer memory"
  copyMem(addr assembler.data[assembler.offset], unsafeAddr data, sizeof(T))
  assembler.offset += sizeof(T)

proc writeField(assembler: var AssemblerX64, top, middle, bottom: byte) =
  assembler.write ((top and 0x3'u8) shl 6) or ((middle and 0x7'u8) shl 3) or
    (bottom and 0x7'u8)

proc writeRex(assembler: var AssemblerX64, w, r, x, b: bool) =
  assembler.write 0x40'u8 or (uint8(w) shl 3) or (uint8(r) shl 2) or (uint8(x) shl 1) or
    uint8(b)

proc writeVex2(assembler: var AssemblerX64, r: bool, vvvv: byte, L: bool, pp: uint8) =
  assembler.write 0xC5'u8
  assembler.write (uint8(not r) shl 7) or ((not (vvvv) and 0xF) shl 3) or
    (uint8(L) shl 2) or pp

proc writeVex3(
    assembler: var AssemblerX64, r, x, b, w, L: bool, m_mmmm, vvvv, pp: uint8
) =
  assembler.write 0xC4'u8
  assembler.write (uint8(not r) shl 7) or (uint8(not x) shl 6) or (uint8(not b) shl 5) or
    m_mmmm
  assembler.write (uint8(w) shl 7) or ((not (vvvv) and 0xF) shl 3) or (uint8(L) shl 2) or
    pp

proc needsRex8[T](reg: T): bool =
  when T is Register8:
    reg in {regSpl, regBpl, regSil, regDil}
  else:
    false

proc getRexInfo[T, U](
    is64bit: bool, rm: Rm[T], reg: U
): Option[tuple[w, r, x, b: bool]] =
  let precond = is64Bit or reg.needsRex8() or ord(reg) >= 8

  case rm.kind
  of rmDirect:
    when T isnot void:
      if precond or ord(rm.directReg) >= 8 or rm.directReg.needsRex8():
        return some((is64Bit, ord(reg) >= 8, false, ord(rm.directReg) >= 8))
    else:
      raiseAssert(
        "memory only operand. Direct register not allowed (how was this constructed?)"
      )
  of rmIndirectScaled:
    if precond or ord(rm.simpleIndex) >= 8 or rm.simpleIndex.needsRex8():
      return (
        if rm.simpleScale == rmScale1:
          some((is64Bit, ord(reg) >= 8, false, ord(rm.simpleIndex) >= 8))
        else:
          some((is64Bit, ord(reg) >= 8, ord(rm.simpleIndex) >= 8, false))
      )
  of rmIndirectScaledAndBase:
    if precond or ord(rm.base) >= 8 or ord(rm.baseIndex) >= 8:
      return some((is64Bit, ord(reg) >= 8, ord(rm.baseIndex) >= 8, ord(rm.base) >= 8))
  of rmIndirectGlobal:
    if precond:
      return some((is64Bit, ord(reg) >= 8, false, false))

  none((bool, bool, bool, bool))

proc writeRex[T, U](assembler: var AssemblerX64, rm: Rm[T], reg: U, is64Bit: bool) =
  let bits = getRexInfo(is64Bit, rm, reg)
  if bits.isSome:
    let (w, r, x, b) = bits.get
    assembler.writeRex w, r, x, b

proc writeVex[T, U](
    assembler: var AssemblerX64,
    rm: Rm[T],
    is64bit, L: bool,
    reg: U,
    reg2: Option[U],
    pp, m_mmmm: int,
) =
  let
    rexbits = getRexInfo(is64Bit, rm, reg).get(default((bool, bool, bool, bool)))
    reg2Bits =
      if reg2.isSome:
        int(reg2.get)
      else:
        0
  if m_mmmm == 1 and not (rexbits.w or rexbits.x or rexbits.b):
    assembler.writeVex2 rexbits.r, byte(reg2Bits), L, byte(pp)
  else:
    assembler.writeVex3 rexbits.r,
      rexbits.x, rexbits.b, rexbits.w, L, byte(m_mmmm), byte(reg2Bits), byte(pp)

proc writeModrm[T, U](assembler: var AssemblerX64, rm: Rm[T], reg: U): int =
  case rm.kind
  of rmDirect:
    when T isnot void:
      assembler.writeField 0b11, byte(reg), byte(rm.directReg)
      -1
    else:
      raiseAssert(
        "memory only operand. Direct register not allowed (how was this constructed?)"
      )
  of rmIndirectScaled:
    if rm.simpleScale == rmScale1:
      if rm.simpleIndex != regRsp and rm.simpleIndex != regR12:
        # most simple form
        # no SIB byte necessary
        if rm.simpleDisp == 0 and rm.simpleIndex != regRbp and rm.simpleIndex != regR13:
          assembler.writeField 0b00, byte(reg), byte(rm.simpleIndex)
        elif rm.simpleDisp.fitsInt8():
          assembler.writeField 0b01, byte(reg), byte(rm.simpleIndex)
          assembler.write cast[int8](rm.simpleDisp)
        else:
          assembler.writeField 0b10, byte(reg), byte(rm.simpleIndex)
          assembler.write rm.simpleDisp
      else:
        if rm.simpleDisp == 0:
          assembler.writeField 0b00, byte(reg), 0b100
          assembler.writeField 0b00, 0b100, byte(rm.simpleIndex)
        elif rm.simpleDisp.fitsInt8():
          assembler.writeField 0b01, byte(reg), 0b100
          assembler.writeField 0b00, 0b100, byte(rm.simpleIndex)
          assembler.write cast[int8](rm.simpleDisp)
        else:
          assembler.writeField 0b10, byte(reg), 0b100
          assembler.writeField 0b00, 0b100, byte(rm.simpleIndex)
          assembler.write rm.simpleDisp
    else:
      assert rm.simpleIndex != regRsp, "rsp cannot be scaled"
      assembler.writeField 0b00, byte(reg), 0b100
      assembler.writeField byte(rm.simpleScale), byte(rm.simpleIndex), 0b101
      assembler.write rm.simpleDisp
    -1
  of rmIndirectScaledAndBase:
    assert rm.baseIndex != regRsp, "rsp cannot be scaled"
    if rm.baseDisp == 0 and rm.base != regRbp and rm.base != regR13:
      assembler.writeField 0b00, byte(reg), 0b100
      assembler.writeField byte(rm.baseScale), byte(rm.baseIndex), byte(rm.base)
    elif rm.baseDisp.fitsInt8():
      assembler.writeField 0b01, byte(reg), 0b100
      assembler.writeField byte(rm.baseScale), byte(rm.baseIndex), byte(rm.base)
      assembler.write cast[int8](rm.baseDisp)
    else:
      assembler.writeField 0b10, byte(reg), 0b100
      assembler.writeField byte(rm.baseScale), byte(rm.baseIndex), byte(rm.base)
      assembler.write rm.baseDisp
    -1
  of rmIndirectGlobal:
    assembler.writeField 0b00, byte(reg), 0b101
    let offset = assembler.offset
    assembler.write 0'i32
    offset

proc fixupRip[T](assembler: var AssemblerX64, modrm: Rm[T], location: int) =
  if location != -1:
    let offset = int32(cast[int64](modrm.globalPtr) - assembler.curAdr)
    copyMem(addr assembler.data[location], unsafeAddr offset, 4)

proc genEmit(desc, assembler: NimNode, hasReg2: bool): NimNode =
  if desc.kind notin {nnkTupleConstr, nnkPar}:
    return desc

  result = newStmtList()

  var fixupRipOffset = nskLet.genSym("fixupRipOffset")

  # first pass find modrms

  var
    hasModrm = false
    modrmReg, modrmRm: NimNode

  for child in desc:
    if child.kind == nnkCall and $child[0] == "modrm":
      child.expectLen 3
      hasModrm = true
      modrmRm = child[1]
      modrmReg = child[2]
      break

  for child in desc:
    child.expectKind {nnkIntLit, nnkInfix, nnkIdent, nnkCall}
    if child.kind == nnkIntLit or child.kind == nnkInfix:
      result.add(
        quote do:
          write(`assembler`, cast[uint8](`child`))
      )
    elif child.kind == nnkIdent:
      case $child
      of "op16":
        result.add(
          quote do:
            write(`assembler`, 0x66'u8)
        )
      of "rex":
        if not hasModrm:
          error("rex without modrm", child)
        result.add(
          quote do:
            writeRex(`assembler`, `modrmRm`, `modrmReg`, false)
        )
      of "op64":
        if hasModrm:
          result.add(
            quote do:
              writeRex(`assembler`, `modrmRm`, `modrmReg`, true)
          )
        else:
          result.add(
            quote do:
              writeRex(`assembler`, true, false, false, false)
          )
      of "imm":
        let imm = ident"imm"
        result.add(
          quote do:
            write(`assembler`, `imm`)
        )
      of "imm8":
        let imm = ident"imm"
        result.add(
          quote do:
            write(`assembler`, cast[int8](`imm`))
        )
      else:
        error("unknown param", child)
    elif child.kind == nnkCall:
      case $child[0]
      of "modrm":
        result.add(
          quote do:
            let `fixupRipOffset` = writeModrm(`assembler`, `modrmRm`, `modrmReg`)
        )
      of "vex", "vex64":
        for i in 1 ..< child.len:
          child[i].expectKind nnkIntLit
        var
          pp = 0
          m_mmmm = -1
        if child.len >= 2:
          pp =
            case child[1].intVal
            of 0x66: 1
            of 0xF3: 2
            of 0xF2: 3
            else: 0
        let
          prefixOffset = ord(pp != 0)
          numOpPrefixes = child.len - 1 - prefixOffset
        if numOpPrefixes >= 1 and child[1 + prefixOffset].intVal == 0x0F:
          if numOpPrefixes == 1:
            m_mmmm = 1
          elif numOpPrefixes == 2:
            case child[1 + prefixOffset + 1].intVal
            of 0x38:
              m_mmmm = 2
            of 0x3A:
              m_mmmm = 3
            else:
              discard
        if m_mmmm == -1:
          error("Unknown vex prefix sequence", child)

        let
          is64Bit = $child[0] == "vex64"
          reg2 =
            if hasReg2:
              let reg2 = ident"reg2"
              quote:
                some(`reg2`)
            else:
              quote:
                none(typeof `modrmReg`)

        result.add(
          quote do:
            writeVex(
              `assembler`,
              `modrmRm`,
              bool(`is64Bit`),
              false,
              `modrmReg`,
              `reg2`,
              `pp`,
              `m_mmmm`,
            )
        )
      of "rex":
        let base = child[1]
        if hasModrm:
          error("modrm with explicit param?", child)
        result.add(
          quote do:
            if `base`:
              writeRex(`assembler`, false, false, false, true)
        )
      of "op64":
        if hasModrm:
          error("modrm with explicit param?", child)
        let base = child[1]
        result.add(
          quote do:
            writeRex(`assembler`, true, false, false, `base`)
        )
      else:
        error("unknown param", child)

  if hasModrm:
    result.add(
      quote do:
        `assembler`.fixupRip(`modrmRm`, `fixupRipOffset`)
    )

macro genAssembler(name, instr: untyped): untyped =
  result = newStmtList()

  var hasReg2 = false

  for variant in instr:
    variant.expectKind nnkCall

    let
      params = variant[0]
      emit = block:
        variant[1].expectKind nnkStmtList
        variant[1].expectLen 1
        variant[1]

      finalProc = nnkProcDef.newTree(
        nnkPostfix.newTree(ident"*", name),
        newEmptyNode(),
        newEmptyNode(),
        nnkFormalParams.newTree(newEmptyNode()),
        newEmptyNode(),
        newEmptyNode(),
        nil,
      )

      assembler = nskParam.genSym("assembler")
    result.add finalProc

    params.expectKind {nnkTupleConstr, nnkPar}

    finalProc[3].add(newIdentDefs(assembler, nnkVarTy.newTree(bindSym"AssemblerX64")))

    for param in params:
      let (name, typ) =
        case $param
        of "reg8":
          (ident"reg", bindSym"Register8")
        of "reg16":
          (ident"reg", bindSym"Register16")
        of "reg32":
          (ident"reg", bindSym"Register32")
        of "reg32_2":
          hasReg2 = true
          (ident"reg2", bindSym"Register32")
        of "reg64":
          (ident"reg", bindSym"Register64")
        of "reg64_2":
          hasReg2 = true
          (ident"reg2", bindSym"Register64")
        of "regXmm":
          (ident"reg", bindSym"RegisterXmm")
        of "regXmm2":
          hasReg2 = true
          (ident"reg2", bindSym"RegisterXmm")
        of "rm8":
          (ident"rm", bindSym"Rm8")
        of "rm16":
          (ident"rm", bindSym"Rm16")
        of "rm32":
          (ident"rm", bindSym"Rm32")
        of "rm64":
          (ident"rm", bindSym"Rm64")
        of "rmXmm":
          (ident"rm", bindSym"RmXmm")
        of "rmMemOnly":
          (ident"rm", bindSym"RmMemOnly")
        of "imm8":
          (ident"imm", bindSym"int8")
        of "imm16":
          (ident"imm", bindSym"int16")
        of "imm32":
          (ident"imm", bindSym"int32")
        of "imm64":
          (ident"imm", bindSym"int64")
        of "cond":
          (ident"cond", bindSym"Condition")
        else:
          error("invalid param", param)
          (nil, nil) # shouldn't be necessary, but error is not noreturn
      finalProc[3].add(newIdentDefs(name, typ))
    if emit.len == 1 and emit[0].kind == nnkIfStmt:
      for branch in emit[0]:
        branch[^1][^1] = genEmit(branch[^1][^1], assembler, hasReg2)
    else:
      emit[^1] = genEmit(emit[^1], assembler, hasReg2)

    finalProc[^1] = emit

template normalOp(
    name, opRmLeft8, opRmLeft, opRmRight8, opRmRight, opAl, opAx, opImm
): untyped {.dirty.} =
  genAssembler name:
    # rm to the left
    (rm8, reg8):
      (rex, opRmLeft8, modrm(rm, reg))
    (rm16, reg16):
      (op16, rex, opRmLeft, modrm(rm, reg))
    (rm32, reg32):
      (rex, opRmLeft, modrm(rm, reg))
    (rm64, reg64):
      (op64, opRmLeft, modrm(rm, reg))

    # rm to the right
    (reg8, rm8):
      (rex, opRmRight8, modrm(rm, reg))
    (reg16, rm16):
      (op16, rex, opRmRight, modrm(rm, reg))
    (reg32, rm32):
      (rex, opRmRight, modrm(rm, reg))
    (reg64, rm64):
      (op64, opRmRight, modrm(rm, reg))

    # immediate forms
    (rm8, imm8):
      if rm.isDirectReg regAl:
        (opAl, imm)
      else:
        (rex, 0x80, modrm(rm, opImm))
    (rm16, imm16):
      # for 16-bit both the specialised ax variant and the 8-bit imm variant
      # produce a four byte sequence, so we prioritise the ax variant as it can hold a
      # larger imm
      if rm.isDirectReg regAx:
        (op16, opAx, imm)
      elif imm.fitsInt8():
        (op16, rex, 0x83, modrm(rm, opImm), imm8)
      else:
        (op16, rex, 0x81, modrm(rm, opImm), imm)
    (rm32, imm32):
      # for 32-bit the 8-bit variant (3 bytes) will always be shorter than the ax variant (5 bytes)
      # if the immediate fits
      if imm.fitsInt8():
        (rex, 0x83, modrm(rm, opImm), imm8)
      elif rm.isDirectReg regEax:
        (opAx, imm)
      else:
        (rex, 0x81, modrm(rm, opImm), imm)
    (rm64, imm32):
      if imm.fitsInt8():
        (op64, 0x83, modrm(rm, opImm), imm8)
      elif rm.isDirectReg regRax:
        (op64, opAx, imm)
      else:
        (op64, 0x81, modrm(rm, opImm), imm)

normalOp(
  add,
  opRmLeft8 = 0x00,
  opRmLeft = 0x01,
  opRmRight8 = 0x2,
  opRmRight = 0x03,
  opAl = 0x04,
  opAx = 0x05,
  opImm = 0x0,
)
normalOp(
  adc,
  opRmLeft8 = 0x10,
  opRmLeft = 0x11,
  opRmRight8 = 0x12,
  opRmRight = 0x13,
  opAl = 0x14,
  opAx = 0x15,
  opImm = 0x2,
)
normalOp(
  sub,
  opRmLeft8 = 0x28,
  opRmLeft = 0x29,
  opRmRight8 = 0x2A,
  opRmRight = 0x2B,
  opAl = 0x2C,
  opAx = 0x2D,
  opImm = 0x5,
)
normalOp(
  sbb,
  opRmLeft8 = 0x18,
  opRmLeft = 0x19,
  opRmRight8 = 0x1A,
  opRmRight = 0x1B,
  opAl = 0x1C,
  opAx = 0x1D,
  opImm = 0x3,
)
normalOp(
  aand,
  opRmLeft8 = 0x20,
  opRmLeft = 0x21,
  opRmRight8 = 0x22,
  opRmRight = 0x23,
  opAl = 0x24,
  opAx = 0x25,
  opImm = 0x4,
)
normalOp(
  oor,
  opRmLeft8 = 0x08,
  opRmLeft = 0x09,
  opRmRight8 = 0x0A,
  opRmRight = 0x0B,
  opAl = 0x0C,
  opAx = 0x0D,
  opImm = 0x1,
)
normalOp(
  xxor,
  opRmLeft8 = 0x30,
  opRmLeft = 0x31,
  opRmRight8 = 0x32,
  opRmRight = 0x33,
  opAl = 0x34,
  opAx = 0x35,
  opImm = 0x6,
)
normalOp(
  cmp,
  opRmLeft8 = 0x38,
  opRmLeft = 0x39,
  opRmRight8 = 0x3A,
  opRmRight = 0x3B,
  opAl = 0x3C,
  opAx = 0x3D,
  opImm = 0x7,
)

genAssembler andn:
  (reg32, reg32_2, rm32):
    (vex(0x0F, 0x38), 0xF2, modrm(rm, reg))
  (reg64, reg64_2, rm64):
    (vex64(0x0F, 0x38), 0xF2, modrm(rm, reg))

genAssembler mov:
  (rm8, reg8):
    (rex, 0x88, modrm(rm, reg))
  (rm16, reg16):
    (op16, rex, 0x89, modrm(rm, reg))
  (rm32, reg32):
    (rex, 0x89, modrm(rm, reg))
  (rm64, reg64):
    (op64, 0x89, modrm(rm, reg))

  (reg8, rm8):
    (rex, 0x8A, modrm(rm, reg))
  (reg16, rm16):
    (op16, rex, 0x8B, modrm(rm, reg))
  (reg32, rm32):
    (rex, 0x8B, modrm(rm, reg))
  (reg64, rm64):
    (op64, 0x8B, modrm(rm, reg))

  (rm8, imm8):
    if rm.kind == rmDirect:
      (rex(ord(rm.directReg) >= 8), 0xB0 + (ord(rm.directReg) and 0x7), imm)
    else:
      (rex, 0xC6, modrm(rm, 0), imm)
  (rm16, imm16):
    if rm.kind == rmDirect:
      (op16, rex(ord(rm.directReg) >= 8), 0xB8 + (ord(rm.directReg) and 0x7), imm)
    else:
      (op16, rex, 0xC7, modrm(rm, 0), imm)
  (rm32, imm32):
    if rm.kind == rmDirect:
      (rex(ord(rm.directReg) >= 8), 0xB8 + (ord(rm.directReg) and 0x7), imm)
    else:
      (rex, 0xC7, modrm(rm, 0), imm)
  (rm64, imm32):
    (op64, 0xC7, modrm(rm, 0), imm)
  (reg64, imm64):
    (op64(ord(reg) >= 8), 0xB8 + (ord(reg) and 0x7), imm)

template extendOp(name, from8, from16): untyped {.dirty.} =
  genAssembler name:
    (reg16, rm8):
      (op16, rex, 0x0F, from8, modrm(rm, reg))
    (reg32, rm8):
      (rex, 0x0F, from8, modrm(rm, reg))
    (reg64, rm8):
      (op64, 0x0F, from8, modrm(rm, reg))

    (reg32, rm16):
      (rex, 0x0F, from16, modrm(rm, reg))
    (reg64, rm16):
      (op64, 0x0F, from16, modrm(rm, reg))

extendOp(movzx, 0xB6, 0xB7)
extendOp(movsx, 0xBE, 0xBF)

genAssembler movsxd:
  (reg64, rm32):
    (op64, 0x63, modrm(rm, reg))

template shiftOp(name, op): untyped {.dirty.} =
  genAssembler name:
    (rm8, imm8):
      if imm == 1:
        (rex, 0xD0, modrm(rm, op))
      else:
        (rex, 0xC0, modrm(rm, op), imm)
    (rm16, imm8):
      if imm == 1:
        (op16, rex, 0xD1, modrm(rm, op))
      else:
        (op16, rex, 0xC1, modrm(rm, op), imm)
    (rm32, imm8):
      if imm == 1:
        (rex, 0xD1, modrm(rm, op))
      else:
        (rex, 0xC1, modrm(rm, op), imm)
    (rm64, imm8):
      if imm == 1:
        (rex, 0xD1, modrm(rm, op))
      else:
        (op64, 0xC1, modrm(rm, op), imm)

    (rm8):
      (rex, 0xD2, modrm(rm, op))
    (rm16):
      (op16, rex, 0xD3, modrm(rm, op))
    (rm32):
      (rex, 0xD3, modrm(rm, op))
    (rm64):
      (op64, 0xD3, modrm(rm, op))

shiftOp(rol, 0)
shiftOp(ror, 1)
shiftOp(rcl, 2)
shiftOp(rcr, 3)
shiftOp(sshl, 4)
shiftOp(sshr, 5)
shiftOp(sar, 7)

genAssembler test:
  (rm8, reg8):
    (rex, 0x84, modrm(rm, reg))
  (rm16, reg16):
    (op16, rex, 0x85, modrm(rm, reg))
  (rm32, reg32):
    (rex, 0x85, modrm(rm, reg))
  (rm64, reg64):
    (op64, 0x85, modrm(rm, reg))

  # immediate forms
  (rm8, imm8):
    if rm.isDirectReg regAl:
      (0xA8, imm)
    else:
      (rex, 0xF6, modrm(rm, 0))
  (rm16, imm16):
    if rm.isDirectReg regAx:
      (op16, 0xA9, imm)
    else:
      (op16, rex, 0xF7, modrm(rm, 0), imm)
  (rm32, imm32):
    if rm.isDirectReg regEax:
      (0xA9, imm)
    else:
      (rex, 0xF7, modrm(rm, 0), imm)
  (rm64, imm32):
    if rm.isDirectReg regRax:
      (op64, 0xA9, imm)
    else:
      (op64, 0xF7, modrm(rm, 0), imm)

template unop(name, op): untyped {.dirty.} =
  genAssembler name:
    (rm8):
      (rex, 0xF6, modrm(rm, op))
    (rm16):
      (op16, rex, 0xF7, modrm(rm, op))
    (rm32):
      (rex, 0xF7, modrm(rm, op))
    (rm64):
      (op64, 0xF7, modrm(rm, op))

unop(nnot, 2)
unop(neg, 3)

template pushPopOp(name, regBaseOp, modrmOp, regOp): untyped {.dirty.} =
  genAssembler name:
    (rm64):
      if rm.kind == rmDirect:
        (rex(ord(rm.directReg) >= 8), regBaseOp + (ord(rm.directReg) and 0x7))
      else:
        (rex, modrmOp, modrm(rm, regOp))

pushPopOp(push, 0x50, 0xFF, 6)
pushPopOp(pop, 0x58, 0x8F, 0)

genAssembler setcc:
  (rm8, cond):
    (rex, 0x0F, 0x90 + ord(cond), modrm(rm, 0))

genAssembler bswap:
  (reg32):
    (rex(ord(reg) >= 8), 0x0F, 0xC8 + (ord(reg) and 0x7))
  (reg64):
    (op64(ord(reg) >= 8), 0x0F, 0xC8 + (ord(reg) and 0x7))

genAssembler ret:
  ():
    (0xC3)

genAssembler int3:
  ():
    (0xCC)

template bitcountOp(name, op) {.dirty.} =
  genAssembler name:
    (reg16, rm16):
      (op16, rex, 0x0F, op, modrm(rm, reg))
    (reg32, rm32):
      (rex, 0x0F, op, modrm(rm, reg))
    (reg64, rm64):
      (op64, 0x0F, op, modrm(rm, reg))

bitcountOp(bsf, 0xBC)
bitcountOp(bsr, 0xBD)

template bitToCarryOp(name, opRm, opImm) {.dirty.} =
  genAssembler name:
    (rm16, imm8):
      (op16, rex, 0x0F, 0xBA, modrm(rm, opImm), imm)
    (rm32, imm8):
      (rex, 0x0F, 0xBA, modrm(rm, opImm), imm)
    (rm64, imm8):
      (op64, 0x0F, 0xBA, modrm(rm, opImm), imm)

    (rm16, reg16):
      (op16, rex, 0x0F, opRm, modrm(rm, reg))
    (rm32, reg32):
      (rex, 0x0F, opRm, modrm(rm, reg))
    (rm64, reg64):
      (op64, 0x0F, opRm, modrm(rm, reg))

bitToCarryOp(bt, 0xA3, 4)
bitToCarryOp(bts, 0xAB, 5)
bitToCarryOp(btr, 0xB3, 6)
bitToCarryOp(btc, 0xBB, 7)

genAssembler cmc:
  ():
    (0xF5)
genAssembler clc:
  ():
    (0xF8)
genAssembler stc:
  ():
    (0xF9)

genAssembler imul:
  (rm8):
    (rex, 0xF6, modrm(rm, 5))
  (rm16):
    (op16, rex, 0xF7, modrm(rm, 5))
  (rm32):
    (rex, 0xF7, modrm(rm, 5))
  (rm64):
    (op64, 0xF7, modrm(rm, 5))

  (reg16, rm16):
    (op16, rex, 0x0F, 0xAF, modrm(rm, reg))
  (reg32, rm32):
    (rex, 0x0F, 0xAF, modrm(rm, reg))
  (reg64, rm64):
    (op64, 0x0F, 0xAF, modrm(rm, reg))

  (reg16, rm16, imm16):
    if imm.fitsInt8():
      (op16, rex, 0x6B, modrm(rm, reg), imm8)
    else:
      (op16, rex, 0x69, modrm(rm, reg), imm)
  (reg32, rm32, imm32):
    if imm.fitsInt8():
      (rex, 0x6B, modrm(rm, reg), imm8)
    else:
      (rex, 0x69, modrm(rm, reg), imm)
  (reg64, rm64, imm32):
    if imm.fitsInt8():
      (op64, 0x6B, modrm(rm, reg), imm8)
    else:
      (op64, 0x69, modrm(rm, reg), imm)

unop(mul, 4)
unop(ddiv, 6)
unop(idiv, 7)

genAssembler lea32:
  (reg16, rmMemOnly):
    (0x67, op16, rex, 0x8D, modrm(rm, reg))
  (reg32, rmMemOnly):
    (0x67, rex, 0x8D, modrm(rm, reg))
  (reg64, rmMemOnly):
    (0x67, op64, rex, 0x8D, modrm(rm, reg))
genAssembler lea64:
  (reg16, rmMemOnly):
    (op16, rex, 0x8D, modrm(rm, reg))
  (reg32, rmMemOnly):
    (rex, 0x8D, modrm(rm, reg))
  (reg64, rmMemOnly):
    (op64, rex, 0x8D, modrm(rm, reg))

genAssembler cmov:
  (reg16, rm16, cond):
    (op16, rex, 0x0F, 0x40 + ord(cond), modrm(rm, reg))
  (reg32, rm32, cond):
    (rex, 0x0F, 0x40 + ord(cond), modrm(rm, reg))
  (reg64, rm64, cond):
    (op64, 0x0F, 0x40 + ord(cond), modrm(rm, reg))

genAssembler movbe:
  (reg16, rmMemOnly):
    (op16, rex, 0x0F, 0x38, 0xF0, modrm(rm, reg))
  (reg32, rmMemOnly):
    (rex, 0x0F, 0x38, 0xF0, modrm(rm, reg))
  (reg64, rmMemOnly):
    (op64, 0x0F, 0x38, 0xF0, modrm(rm, reg))
  (rmMemOnly, reg16):
    (op16, rex, 0x0F, 0x38, 0xF1, modrm(rm, reg))
  (rmMemOnly, reg32):
    (rex, 0x0F, 0x38, 0xF1, modrm(rm, reg))
  (rmMemOnly, reg64):
    (op64, 0x0F, 0x38, 0xF1, modrm(rm, reg))

genAssembler cwd:
  ():
    (op16, 0x99)
genAssembler cdq:
  ():
    (0x99)
genAssembler cqo:
  ():
    (op64, 0x99)

genAssembler cbw:
  ():
    (op16, 0x98)
genAssembler cwde:
  ():
    (0x98)
genAssembler cdqe:
  ():
    (op64, 0x98)

proc jmp*(assembler: var AssemblerX64, target: pointer) =
  let offset8 = int32(cast[int64](target) - (assembler.curAdr + 2))
  if offset8.fitsInt8():
    assembler.write 0xEB'u8
    assembler.write cast[int8](offset8)
  else:
    let offset = int32(cast[int64](target) - (assembler.curAdr + 5))
    assembler.write 0xE9'u8
    assembler.write offset

proc jmp*(assembler: var AssemblerX64, label: BackwardsLabel) =
  assembler.jmp(cast[pointer](cast[int](assembler.data) + int(label)))

proc jmp*(assembler: var AssemblerX64, longJmp: bool): ForwardsLabel =
  if longJmp:
    assembler.write 0xE9'u8
    assembler.write 0x00'i32
  else:
    assembler.write 0xEB'u8
    assembler.write 0x00'i8
  ForwardsLabel(isLongJmp: longJmp, offset: int32(assembler.offset))

genAssembler jmp:
  (rm64):
    (rex, 0xFF, modrm(rm, 4))

proc call*(assembler: var AssemblerX64, target: pointer) =
  let offset =
    int32(cast[int64](target) - (cast[int64](assembler.data) + assembler.offset + 5))
  assembler.write 0xE8'u8
  assembler.write offset

proc call*(assembler: var AssemblerX64, label: BackwardsLabel) =
  assembler.call(cast[pointer](cast[int](assembler.data) + int(label)))

proc call*(assembler: var AssemblerX64, longJmp: bool): ForwardsLabel =
  assembler.write 0xE8'u8
  assembler.write 0x00'i32
  ForwardsLabel(isLongJmp: longJmp, offset: int32(assembler.offset))

genAssembler call:
  (rm64):
    (rex, 0xFF, modrm(rm, 2))

proc jcc*(assembler: var AssemblerX64, cc: Condition, target: pointer) =
  let offset8 = int32(cast[int64](target) - (assembler.curAdr + 2))
  if offset8.fitsInt8():
    assembler.write 0x70'u8 + uint8(cc)
    assembler.write cast[int8](offset8)
  else:
    let offset = int32(cast[int64](target) - (assembler.curAdr + 6))
    assembler.write 0x0F'u8
    assembler.write 0x80'u8 + uint8(cc)
    assembler.write offset

proc jcc*(assembler: var AssemblerX64, cc: Condition, label: BackwardsLabel) =
  assembler.jcc(cc, cast[pointer](cast[int](assembler.data) + int(label)))

proc jcc*(assembler: var AssemblerX64, cc: Condition, longJmp: bool): ForwardsLabel =
  if longJmp:
    assembler.write 0x0F'u8
    assembler.write 0x80'u8 + uint8(cc)
    assembler.write 0'i32
  else:
    assembler.write 0x70'u8 + uint8(cc)
    assembler.write 0'i8
  ForwardsLabel(isLongJmp: longJmp, offset: int32(assembler.offset))

proc nop*(assembler: var AssemblerX64, bytes = 1) =
  var remainingBytes = bytes
  while remainingBytes > 0:
    case remainingBytes
    of 1:
      assembler.write 0x90'u8
      break
    of 2:
      assembler.write 0x66'u8
      assembler.write 0x90'u8
      break
    of 3:
      assembler.write 0x0F'u8
      assembler.write 0x1F'u8
      assembler.write 0x00'u8
      break
    of 4:
      assembler.write 0x0F'u8
      assembler.write 0x1F'u8
      assembler.write 0x40'u8
      assembler.write 0x00'u8
      break
    of 5:
      assembler.write 0x0F'u8
      assembler.write 0x1F'u8
      assembler.write 0x44'u8
      assembler.write 0x00'u16
      break
    of 6:
      assembler.write 0x66'u8
      assembler.write 0x0F'u8
      assembler.write 0x1F'u8
      assembler.write 0x44'u8
      assembler.write 0x00'u16
      break
    of 7:
      assembler.write 0x0F'u8
      assembler.write 0x1F'u8
      assembler.write 0x80'u8
      assembler.write 0x00'u32
      break
    of 8:
      assembler.write 0x0F'u8
      assembler.write 0x1F'u8
      assembler.write 0x84'u8
      assembler.write 0x00'u8
      assembler.write 0x00'u32
      break
    else:
      assembler.write 0x66'u8
      assembler.write 0x0F'u8
      assembler.write 0x1F'u8
      assembler.write 0x84'u8
      assembler.write 0x00'u8
      assembler.write 0x00'u32
      remainingBytes -= 9

template normalSseOp(name, op; triop = true): untyped {.dirty.} =
  genAssembler `name ps`:
    (regXmm, rmXmm):
      (rex, 0x0F, op, modrm(rm, reg))
  genAssembler `name ss`:
    (regXmm, rmXmm):
      (0xF3, rex, 0x0F, op, modrm(rm, reg))
  genAssembler `name pd`:
    (regXmm, rmXmm):
      (0x66, rex, 0x0F, op, modrm(rm, reg))
  genAssembler `name sd`:
    (regXmm, rmXmm):
      (0xF2, rex, 0x0F, op, modrm(rm, reg))

  genAssembler `v name ss`:
    (regXmm, regXmm2, rmXmm):
      (vex(0xF3, 0x0F), op, modrm(rm, reg))
  genAssembler `v name sd`:
    (regXmm, regXmm2, rmXmm):
      (vex(0xF2, 0x0F), op, modrm(rm, reg))
  when triop:
    genAssembler `v name ps`:
      (regXmm, regXmm2, rmXmm):
        (vex(0x0F), op, modrm(rm, reg))
    genAssembler `v name pd`:
      (regXmm, regXmm2, rmXmm):
        (vex(0x66, 0x0F), op, modrm(rm, reg))
  else:
    genAssembler `v name ps`:
      (regXmm, rmXmm):
        (vex(0x0F), op, modrm(rm, reg))
    genAssembler `v name pd`:
      (regXmm, rmXmm):
        (vex(0x66, 0x0F), op, modrm(rm, reg))

normalSseOp(sqrt, 0x51, false)
normalSseOp(add, 0x58)
normalSseOp(mul, 0x59)
normalSseOp(sub, 0x5C)
normalSseOp(ddiv, 0x5E)
normalSseOp(min, 0x5D)
normalSseOp(max, 0x5F)

template weirdSseBitOp(name, op): untyped {.dirty.} =
  genAssembler `name ps`:
    (regXmm, rmXmm):
      (rex, 0x0F, op, modrm(rm, reg))
  genAssembler `name pd`:
    (regXmm, rmXmm):
      (0x66, rex, 0x0F, op, modrm(rm, reg))

  genAssembler `v name ps`:
    (regXmm, regXmm2, rmXmm):
      (vex(0x0F), op, modrm(rm, reg))
  genAssembler `v name pd`:
    (regXmm, regXmm2, rmXmm):
      (vex(0x66, 0x0F), op, modrm(rm, reg))

weirdSseBitOp(aand, 0x54)
weirdSseBitOp(andn, 0x55)
weirdSseBitOp(oor, 0x56)
weirdSseBitOp(xxor, 0x57)

genAssembler rsqrtps:
  (regXmm, rmXmm):
    (rex, 0x0F, 0x52, modrm(rm, reg))
genAssembler rsqrtss:
  (regXmm, rmXmm):
    (0xF3, rex, 0x0F, 0x52, modrm(rm, reg))
genAssembler rcpps:
  (regXmm, rmXmm):
    (rex, 0x0F, 0x53, modrm(rm, reg))
genAssembler rcpss:
  (regXmm, rmXmm):
    (0xF3, rex, 0x0F, 0x53, modrm(rm, reg))

genAssembler movups:
  (regXmm, rmXmm):
    (rex, 0x0F, 0x10, modrm(rm, reg))
  (rmXmm, regXmm):
    (rex, 0x0F, 0x11, modrm(rm, reg))
genAssembler movss:
  (regXmm, rmXmm):
    (0xF3, rex, 0x0F, 0x10, modrm(rm, reg))
  (rmXmm, regXmm):
    (0xF3, rex, 0x0F, 0x11, modrm(rm, reg))
genAssembler movupd:
  (regXmm, rmXmm):
    (0x66, rex, 0x0F, 0x10, modrm(rm, reg))
  (rmXmm, regXmm):
    (0x66, rex, 0x0F, 0x11, modrm(rm, reg))
genAssembler movsd:
  (regXmm, rmXmm):
    (0xF2, rex, 0x0F, 0x10, modrm(rm, reg))
  (rmXmm, regXmm):
    (0xF2, rex, 0x0F, 0x11, modrm(rm, reg))

genAssembler movhlps:
  (regXmm, regXmm2):
    (rex, 0x0F, 0x12, modrm(reg(reg2), reg))
genAssembler movlhps:
  (regXmm, regXmm2):
    (rex, 0x0F, 0x16, modrm(reg(reg2), reg))

template sseMovPartMemory(partname, op): untyped {.dirty.} =
  genAssembler `mov partname ps`:
    (regXmm, rmMemOnly):
      (rex, 0x0F, op, modrm(rm, reg))
    (rmMemOnly, regXmm):
      (rex, 0x0F, op + 1, modrm(rm, reg))
  genAssembler `mov partname pd`:
    (regXmm, rmMemOnly):
      (0x66, rex, 0x0F, op, modrm(rm, reg))
    (rmMemOnly, regXmm):
      (0x66, rex, 0x0F, op + 1, modrm(rm, reg))

sseMovPartMemory(l, 0x12)
sseMovPartMemory(h, 0x16)

genAssembler movddup:
  (regXmm, rmXmm):
    (0xF2, rex, 0x0F, 0x12, modrm(rm, reg))
genAssembler movsldup:
  (regXmm, rmXmm):
    (0xF3, rex, 0x0F, 0x12, modrm(rm, reg))
genAssembler movshdup:
  (regXmm, rmXmm):
    (0xF3, rex, 0x0F, 0x16, modrm(rm, reg))

genAssembler unpcklps:
  (regXmm, rmXmm):
    (rex, 0x0F, 0x14, modrm(rm, reg))
genAssembler unpcklpd:
  (regXmm, rmXmm):
    (0x66, rex, 0x0F, 0x14, modrm(rm, reg))
genAssembler unpckhps:
  (regXmm, rmXmm):
    (rex, 0x0F, 0x15, modrm(rm, reg))
genAssembler unpckhpd:
  (regXmm, rmXmm):
    (0x66, rex, 0x0F, 0x15, modrm(rm, reg))

genAssembler movaps:
  (regXmm, rmXmm):
    (rex, 0x0F, 0x28, modrm(rm, reg))
  (rmXmm, regXmm):
    (rex, 0x0F, 0x29, modrm(rm, reg))
genAssembler movapd:
  (regXmm, rmXmm):
    (0x66, rex, 0x0F, 0x28, modrm(rm, reg))
  (rmXmm, regXmm):
    (0x66, rex, 0x0F, 0x29, modrm(rm, reg))

genAssembler movd:
  (regXmm, rm32):
    (0x66, rex, 0x0F, 0x6E, modrm(rm, reg))
  (rm32, regXmm):
    (0x66, rex, 0x0F, 0x7E, modrm(rm, reg))
genAssembler movq:
  (regXmm, rm64):
    (0x66, op64, 0x0F, 0x6E, modrm(rm, reg))
  (rm64, regXmm):
    (0x66, op64, 0x0F, 0x7E, modrm(rm, reg))

genAssembler movdqa:
  (regXmm, rmXmm):
    (0x66, rex, 0x0F, 0x6F, modrm(rm, reg))
  (rmXmm, regXmm):
    (0x66, rex, 0x0F, 0x7F, modrm(rm, reg))
genAssembler movdqu:
  (regXmm, rmXmm):
    (0xF3, rex, 0x0F, 0x6F, modrm(rm, reg))
  (rmXmm, regXmm):
    (0xF3, rex, 0x0F, 0x7F, modrm(rm, reg))

genAssembler cvtsi2ss:
  (regXmm, rm32):
    (0xF3, rex, 0x0F, 0x2A, modrm(rm, reg))
  (regXmm, rm64):
    (0xF3, op64, 0x0F, 0x2A, modrm(rm, reg))
genAssembler cvtsi2sd:
  (regXmm, rm32):
    (0xF2, rex, 0x0F, 0x2A, modrm(rm, reg))
  (regXmm, rm64):
    (0xF2, op64, 0x0F, 0x2A, modrm(rm, reg))

genAssembler cvttss2si:
  (reg32, rmXmm):
    (0xF3, rex, 0x0F, 0x2C, modrm(rm, reg))
  (reg64, rmXmm):
    (0xF3, op64, 0x0F, 0x2C, modrm(rm, reg))
genAssembler cvttsd2si:
  (reg32, rmXmm):
    (0xF2, rex, 0x0F, 0x2C, modrm(rm, reg))
  (reg64, rmXmm):
    (0xF2, op64, 0x0F, 0x2C, modrm(rm, reg))

genAssembler cvtss2si:
  (reg32, rmXmm):
    (0xF3, rex, 0x0F, 0x2D, modrm(rm, reg))
  (reg64, rmXmm):
    (0xF3, op64, 0x0F, 0x2D, modrm(rm, reg))
genAssembler cvtsd2si:
  (reg32, rmXmm):
    (0xF2, rex, 0x0F, 0x2D, modrm(rm, reg))
  (reg64, rmXmm):
    (0xF2, op64, 0x0F, 0x2D, modrm(rm, reg))

genAssembler ucomiss:
  (regXmm, rmXmm):
    (rex, 0x0F, 0x2E, modrm(rm, reg))
genAssembler ucomisd:
  (regXmm, rmXmm):
    (0x66, rex, 0x0F, 0x2E, modrm(rm, reg))

genAssembler comiss:
  (regXmm, rmXmm):
    (rex, 0x0F, 0x2F, modrm(rm, reg))
genAssembler comisd:
  (regXmm, rmXmm):
    (0x66, rex, 0x0F, 0x2F, modrm(rm, reg))

genAssembler cvtps2pd:
  (regXmm, rmXmm):
    (rex, 0x0F, 0x5A, modrm(rm, reg))
genAssembler cvtpd2ps:
  (regXmm, rmXmm):
    (0x66, rex, 0x0F, 0x5A, modrm(rm, reg))

genAssembler cvtss2sd:
  (regXmm, rmXmm):
    (0xF3, rex, 0x0F, 0x5A, modrm(rm, reg))
genAssembler cvtsd2ss:
  (regXmm, rmXmm):
    (0xF2, rex, 0x0F, 0x5A, modrm(rm, reg))

genAssembler cvtdq2ps:
  (regXmm, rmXmm):
    (rex, 0x0F, 0x5B, modrm(rm, reg))
genAssembler cvtps2dq:
  (regXmm, rmXmm):
    (0x66, rex, 0x0F, 0x5B, modrm(rm, reg))
genAssembler cvttps2dq:
  (regXmm, rmXmm):
    (0xF3, rex, 0x0F, 0x5B, modrm(rm, reg))

genAssembler cvtpd2dq:
  (regXmm, rmXmm):
    (0xF2, rex, 0x0F, 0xE6, modrm(rm, reg))
genAssembler cvttpd2dq:
  (regXmm, rmXmm):
    (0x66, rex, 0x0F, 0xE6, modrm(rm, reg))
genAssembler cvtdq2pd:
  (regXmm, rmXmm):
    (0xF3, rex, 0x0F, 0xE6, modrm(rm, reg))

genAssembler shufps:
  (regXmm, rmXmm, imm8):
    (rex, 0x0F, 0xC6, modrm(rm, reg), imm8)
genAssembler shufpd:
  (regXmm, rmXmm, imm8):
    (0x66, rex, 0x0F, 0xC6, modrm(rm, reg), imm8)

template genFma(
    name, opcode132, opcode213, opcode231, opcodeSingle132, opcodeSingle213,
      opcodeSingle231
): untyped {.dirty.} =
  genAssembler `vf name 132 pd`:
    (regXmm, regXmm2, rmXmm):
      (vex64(0x66, 0x0F, 0x38), opcode132, modrm(rm, reg))
  genAssembler `vf name 213 pd`:
    (regXmm, regXmm2, rmXmm):
      (vex64(0x66, 0x0F, 0x38), opcode213, modrm(rm, reg))
  genAssembler `vf name 231 pd`:
    (regXmm, regXmm2, rmXmm):
      (vex64(0x66, 0x0F, 0x38), opcode231, modrm(rm, reg))
  genAssembler `vf name 132 ps`:
    (regXmm, regXmm2, rmXmm):
      (vex(0x66, 0x0F, 0x38), opcode132, modrm(rm, reg))
  genAssembler `vf name 213 ps`:
    (regXmm, regXmm2, rmXmm):
      (vex(0x66, 0x0F, 0x38), opcode213, modrm(rm, reg))
  genAssembler `vf name 231 ps`:
    (regXmm, regXmm2, rmXmm):
      (vex(0x66, 0x0F, 0x38), opcode231, modrm(rm, reg))
  genAssembler `vf name 132 sd`:
    (regXmm, regXmm2, rmXmm):
      (vex64(0x66, 0x0F, 0x38), opcodeSingle132, modrm(rm, reg))
  genAssembler `vf name 213 sd`:
    (regXmm, regXmm2, rmXmm):
      (vex64(0x66, 0x0F, 0x38), opcodeSingle213, modrm(rm, reg))
  genAssembler `vf name 231 sd`:
    (regXmm, regXmm2, rmXmm):
      (vex64(0x66, 0x0F, 0x38), opcodeSingle231, modrm(rm, reg))
  genAssembler `vf name 132 ss`:
    (regXmm, regXmm2, rmXmm):
      (vex(0x66, 0x0F, 0x38), opcodeSingle132, modrm(rm, reg))
  genAssembler `vf name 213 ss`:
    (regXmm, regXmm2, rmXmm):
      (vex(0x66, 0x0F, 0x38), opcodeSingle213, modrm(rm, reg))
  genAssembler `vf name 231 ss`:
    (regXmm, regXmm2, rmXmm):
      (vex(0x66, 0x0F, 0x38), opcodeSingle231, modrm(rm, reg))

genFma(madd, 0x98, 0xA8, 0xB8, 0x99, 0xA9, 0xB9)
genFma(msub, 0x9A, 0xAA, 0xBA, 0x9B, 0xAB, 0xBB)
genFma(nmadd, 0x9C, 0xAC, 0xBC, 0x9D, 0xAD, 0xBD)
genFma(nmsub, 0x9E, 0xAE, 0xBE, 0x9F, 0xAF, 0xBF)

genAssembler pushf:
  ():
    (op16, 0x9C)

genAssembler pushfq:
  ():
    (0x9C)

genAssembler popf:
  ():
    (op16, 0x9D)

genAssembler popfq:
  ():
    (0x9D)
