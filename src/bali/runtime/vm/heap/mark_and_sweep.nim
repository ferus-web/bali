## Simple mark-and-sweep GC.
import bali/runtime/vm/runtime/pulsar/registers,
       bali/runtime/atom_type
import pkg/shakar

type
  AllocationCallbacks* = object
    alloc*: proc(size: uint): pointer {.cdecl.}
    free*: proc(p: pointer) {.cdecl.}

proc malloc(size: uint): pointer {.importc, cdecl, header: "<stdlib.h>".}
proc free(p: pointer) {.importc, cdecl, header: "<stdlib.h>".}

var
  BaseAllocator = AllocationCallbacks(
    alloc: malloc,
    free: free
  )

proc mark(state: bool, value: JSValue) =
  value.marked = state

  case value.kind
  of { Null, String, Integer, Ident, Boolean,
      Float, BigInteger, BytecodeCallable,
      NativeCallable, Undefined }: discard
  of Sequence:
    for i, _ in value.sequence:
      mark(state, value.sequence[i].addr)
  of Object:
    for i, _ in value.objValues:
      mark(state, value.objValues[i])

proc mark(state: bool, space: seq[JSValue], regs: Registers) =
  for value in space:
    mark(state, value)

  if *regs.retVal:
    mark(state, &regs.retVal)

  for arg in regs.callArgs:
    mark(state, arg)

  if *regs.error:
    mark(state, &regs.error)

proc mark*(space: seq[JSValue], regs: Registers) =
  mark(true, space, regs)

proc unmark*(space: seq[JSValue], regs: Registers) =
  mark(false, space, regs)

# Methods exposed to the engine.
# (Marked as cdecl because the JIT can call them)
proc baliAlloc*(size: int): pointer {.cdecl.} =
  BaseAllocator.alloc(uint(size))

proc baliDealloc*(p: pointer) {.cdecl.} =
  BaseAllocator.free(p)
