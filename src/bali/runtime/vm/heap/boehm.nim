## Taken from the Nim compiler source code
import std/strutils

{.passC: gorge("pkg-config --cflags bdw-gc").strip().}
{.passL: gorge("pkg-config --libs bdw-gc").strip().}

{.pragma: boehmGC, header: "<gc.h>".}

proc boehmGCinit* {.importc: "GC_init", boehmGC.}
proc boehmGC_disable* {.importc: "GC_disable", boehmGC.}
proc boehmGC_enable* {.importc: "GC_enable", boehmGC.}
proc boehmGCincremental* {.
  importc: "GC_enable_incremental", boehmGC.}
proc boehmGCfullCollect* {.importc: "GC_gcollect", boehmGC.}
proc boehmGC_set_all_interior_pointers*(flag: cint) {.
  importc: "GC_set_all_interior_pointers", boehmGC.}
proc boehmAlloc*(size: int): pointer {.importc: "GC_malloc", boehmGC.}
proc boehmAllocAtomic*(size: int): pointer {.
  importc: "GC_malloc_atomic", boehmGC.}
proc boehmRealloc*(p: pointer, size: int): pointer {.
  importc: "GC_realloc", boehmGC.}
proc boehmDealloc*(p: pointer) {.importc: "GC_free", boehmGC.}

proc boehmGetHeapSize*: int {.importc: "GC_get_heap_size", boehmGC.}
  ## Return the number of bytes in the heap.  Excludes collector private
  ## data structures. Includes empty blocks and fragmentation loss.
  ## Includes some pages that were allocated but never written.

proc boehmGetFreeBytes*: int {.importc: "GC_get_free_bytes", boehmGC.}
  ## Return a lower bound on the number of free bytes in the heap.

proc boehmGetBytesSinceGC*: int {.importc: "GC_get_bytes_since_gc", boehmGC.}
  ## Return the number of bytes allocated since the last collection.

proc boehmGetTotalBytes*: int {.importc: "GC_get_total_bytes", boehmGC.}
  ## Return the total number of bytes allocated in this process.
  ## Never decreases.

proc baliAlloc*(size: SomeInteger): pointer {.inline.} =
  boehmAlloc(size)
