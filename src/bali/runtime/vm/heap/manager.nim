## ===============
## The Heap Manager
## ===============
## 
## This type exists to merge all the (horrible) global-based
## allocator states Bali manages.
##
## Copyright (C) 2025 Trayambak Rai
import std/[logging]
import pkg/bali/runtime/vm/heap/[boehm, bump_allocator]

type
  AllocationFailed* = object of Defect
    ## Raised when the heap manager can no longer safely
    ## allocate any more memory.

  AllocationMetrics* = object
    #!fmt: off
    allocatedBytesTotal*: uint64   ## Number of bytes allocated overall
    allocatedBytesBump*: uint64    ## Number of bytes caught by the bump allocator
    allocatedBytesGc*: uint64       ## Number of bytes allocated via the GC after the bump allocator is exhausted
    #!fmt: on

  HeapManager* = ref object
    bump*: BumpAllocator
    metrics*: AllocationMetrics

proc release*(manager: HeapManager) =
  debug "vm/heap: releasing all* held memory; freeing bump allocator buffer"
  manager.bump.release()

  debug "vm/heap: performing full GC collection"
  GC_fullCollect()

proc allocate*(manager: HeapManager, size: SomeUnsignedInt): pointer =
  manager.metrics.allocatedBytesTotal += size

  if manager.bump.remaining >= size:
    # If the bump allocator has some memory remaining, use it.
    manager.metrics.allocatedBytesBump += size
    return manager.bump.allocate(size)

  # Otherwise, try allocating memory with the garbage collector.
  let pntr = boehmAlloc(size)
  if pntr == nil:
    raise newException(
      AllocationFailed,
      "Cannot allocate buffer of size `" & $size &
        "` (Bump allocator buffer is full and GC returned NULL; is this an OOM?)",
    )

  manager.metrics.allocatedBytesGc += size
  pntr

proc initHeapManager*(): HeapManager =
  debug "vm/heap: initializing heap manager"
  var manager = HeapManager()

  debug "vm/heap: initializing bump allocator"
  manager.bump = initBumpAllocator()

  debug "vm/heap: initializing garbage collector state"
  boehmGCinit()
  boehmGC_enable()

  ensureMove(manager)
