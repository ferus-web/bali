## Taken from the Nim compiler source code
import std/[logging, strutils]

{.passC: gorge("pkg-config --cflags bdw-gc").strip().}
{.passL: gorge("pkg-config --libs bdw-gc").strip().}

{.pragma: boehmGC, header: "<gc.h>".}

proc boehmGCinit*() {.importc: "GC_init", boehmGC.}
proc boehmGC_disable*() {.importc: "GC_disable", boehmGC.}
proc boehmGC_enable*() {.importc: "GC_enable", boehmGC.}
proc boehmGCincremental*() {.importc: "GC_enable_incremental", boehmGC.}
proc boehmGCfullCollect*() {.importc: "GC_gcollect", boehmGC.}
proc boehmGC_set_all_interior_pointers*(
  flag: cint
) {.importc: "GC_set_all_interior_pointers", boehmGC.}

proc boehmAlloc*(size: int): pointer {.importc: "GC_malloc", boehmGC.}
proc boehmAllocAtomic*(size: int): pointer {.importc: "GC_malloc_atomic", boehmGC.}
proc boehmRealloc*(p: pointer, size: int): pointer {.importc: "GC_realloc", boehmGC.}
var
  GC_VERSION_MAJOR* {.importc, boehmGC.}: cint
  GC_VERSION_MINOR* {.importc, boehmGC.}: cint
  GC_VERSION_MICRO* {.importc, boehmGC.}: cint
proc boehmDealloc*(p: pointer) {.importc: "GC_free", boehmGC.}

proc boehmGetHeapSize*(): int {.importc: "GC_get_heap_size", boehmGC.}
  ## Return the number of bytes in the heap.  Excludes collector private
  ## data structures. Includes empty blocks and fragmentation loss.
  ## Includes some pages that were allocated but never written.

proc boehmGetFreeBytes*(): int {.importc: "GC_get_free_bytes", boehmGC.}
  ## Return a lower bound on the number of free bytes in the heap.

proc boehmGetBytesSinceGC*(): int {.importc: "GC_get_bytes_since_gc", boehmGC.}
  ## Return the number of bytes allocated since the last collection.

proc boehmGetTotalBytes*(): int {.importc: "GC_get_total_bytes", boehmGC.}
  ## Return the total number of bytes allocated in this process.
  ## Never decreases.

proc boehmVersion*(): string {.inline.} =
  $GC_VERSION_MAJOR & '.' & $GC_VERSION_MINOR & '.' & $GC_VERSION_MICRO

const BaliGCStatsTrackingPerFrame* {.intdefine.} = 32

type BaliGCStatistics* = object
  ## This structure captures the GC statistics for a particular "frame".
  ## A frame refers to any GC event (allocation, deallocation, collection)
  peakAllocatedBytes*: int ## Maximum number of bytes allocated in the execution time
  allocationRate*: int ## At what rate are bytes allocated per collection?
  liberationRate*: int ## At what rate are bytes "liberated" per collection?
  liveMemory*: int ## How much memory in bytes is still reachable
  totalMemory*: int ## Size of the total heap in bytes

  currFrame*: int

var gcStats* {.global.}: BaliGCStatistics

proc update(stats: var BaliGCStatistics) =
  stats.peakAllocatedBytes = boehmGetTotalBytes()
  stats.allocationRate = boehmGetBytesSinceGC()
  stats.liberationRate = stats.peakAllocatedBytes - stats.allocationRate
  stats.totalMemory = boehmGetHeapSize()
  stats.liveMemory = stats.totalMemory - boehmGetFreeBytes()

func pressure*(
    stats: BaliGCStatistics, generalBias: float = 1f, spaceBias: float = 1f
): float64 =
  ## Calculate the GC pressure by accounting for a bunch of stuff, depending
  ## on what we're focusing on.
  ##
  ## Increasing a bias results in it playing a larger role in the overall pressure.

  (
    generalBias * (stats.liveMemory / stats.totalMemory) +
    spaceBias * (stats.liberationRate / stats.allocationRate)
  ) #/ (generalBias + spaceBias)

proc baliDealloc*(p: pointer) {.inline.} =
  # debug "heap: performing explicit deallocation of GC'd chunk"
  boehmDealloc(p)

  inc gcStats.currFrame
  # debug "heap: event deferral frame: " & $gcStats.currFrame

  when not defined(baliPreciseGCPressureTracking):
    if gcStats.currFrame >= BaliGCStatsTrackingPerFrame:
      #[debug "heap: hit GC-stats tracking frame deferral limit: " &
        $BaliGCStatsTrackingPerFrame &
        "; performing collection and updating GC stats (set -d:BaliGCStatsTrackingPerFrame to change this threshold)" ]#
      update gcStats
      gcStats.currFrame = 0
  else:
    update gcStats

proc baliAlloc*(size: SomeInteger): pointer {.cdecl.} =
  debug "heap: allocating GC'd chunk of size: " & $size & " bytes"
  var pointr = boehmAlloc(size)

  # debug "heap: zeroing out chunk"
  zeroMem(pointr, size)

  when not defined(baliPreciseGCPressureTracking):
    inc gcStats.currFrame
    # debug "heap: event deferral frame: " & $gcStats.currFrame
    if gcStats.currFrame >= BaliGCStatsTrackingPerFrame:
      #[ debug "heap: hit GC-stats tracking frame deferral limit: " &
        $BaliGCStatsTrackingPerFrame &
        "; performing collection and updating GC stats (set -d:BaliGCStatsTrackingPerFrame to change this threshold)" ]#
      boehmGcfullCollect()
      update gcStats
      gcStats.currFrame = 0
  else:
    update gcStats

  pointr
