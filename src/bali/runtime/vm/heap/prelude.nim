import std/[logging]
import bali/runtime/vm/heap/[mark_and_sweep, boehm]

type GCKind* {.pure.} = enum
  Boehm = 0 ## The Boehm-Demers-Weiser conservative garbage collector. The default.
  MarkAndSweep = 1 ## Bali's internal mark-and-sweep implementation. Highly unstable.

proc getStackPtr*(): pointer =
  ## Cross-architecture function that returns the stack pointer.
  ## Used for initializing Bali's internal GC.
  when defined(amd64):
    asm """
      mov %%rsp, %0
      :"=r"(`result`)
    """
  elif defined(arm):
    asm """
      mov %0, sp
      :"=r"(`result`)
    """
  elif defined(riscv):
    asm """
      mv %0, sp
      :"=r"(`result`)
    """
  else:
    {.
      error: "Unsupported platform - the Bali GC does not work on your CPU architecture"
    .}

proc initializeGC*(kind: GCKind = Boehm, incremental: bool = false) =
  debug "heap: initializing garbage collector: " & $kind
  case kind
  of GCKind.Boehm:
    boehmGCinit()
    boehmGC_enable()

    if incremental:
      boehmGCincremental()
  of GCKind.MarkAndSweep:
    warn "heap: garbage collector was forced to mark-and-sweep: this is highly unstable and is not recommended!"
    warn "heap: if this was a mistake, please revert it!"
    mark_and_sweep.initializeGC(getStackPtr(), 32)
