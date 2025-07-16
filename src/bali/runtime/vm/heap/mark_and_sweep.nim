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

  allValues {.global.} = newSeqOfCap[JSValue](64)

proc resetGCState*() {.sideEffect.} =
  allValues.reset()

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
    if value == nil:
      continue

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

proc baliCollect*(space: seq[JSValue], regs: Registers) =
  # Mark all reachable objects
  mark(space, regs)
  
  # Now, go over every single pointer we have.
  # If it isn't reachable, then we can free it up.
  for i, pntr in allValues:
    let value = cast[JSValue](pntr)
    if not value.marked:
      free(value)
      allValues[i] = nil

# Methods exposed to the engine.
# (Marked as cdecl because the JIT can call them)
proc baliAlloc*(size: int): pointer {.cdecl.} =
  let mem = BaseAllocator.alloc(uint(size))
  allValues &= cast[JSValue](mem)

  mem

proc baliDealloc*(p: pointer) {.cdecl.} =
  var found = true
  for pntr in allValues:
    if pntr == p: found = true; break

  assert(found, "BUG: baliDealloc() called on memory chunk likely not allocated by the GC.")
  BaseAllocator.free(p)
