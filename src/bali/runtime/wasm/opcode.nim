## WASM opcodes
## Based off of Ladybird's LibWASM list

type Opcode* {.size: sizeof(uint64).} = enum
  opUnreachable = 0x00

func toInt*(opcode: Opcode): uint64 {.inline.} =
  cast[uint64](opcode)

template enumerateSingleByteWasmOpcodes(M: untyped) =
  M(opNop, 0x01)
  M(opBlock, 0x02)
  M(opLoop, 0x03)
  M(opIf, 0x04)
  M(opStructuredElse, 0x05)
  M(opStructuredEnd, 0x0b)
  M(opBr, 0x0c)
  M(opBrIf, 0x0e)
  M()

template enumerateWasmOpcodes(M: untyped) =
  enumerateSingleByteWasmOpcodes(M)

template M(name: untyped, value: uint8 | uint64) =
  const `name`*: Opcode = cast[Opcode](uint64(value))

enumerateWasmOpcodes(M)
