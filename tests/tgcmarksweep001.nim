import bali/runtime/vm/heap/mark_and_sweep

proc getsp(): pointer =
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

initializeGC(getsp(), 32)
var str = cast[ptr UncheckedArray[char]](baliMSAlloc(8 * sizeof(char)))
assert str != nil

collect()
