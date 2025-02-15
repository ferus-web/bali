## Mark-and-sweep garbage collector implementation
## Author: Trayambak Rai (xtrayambak at disroot dot org)
##
## Roughly based off of OGC (https://github.com/jserv/ogc)
import std/[logging]
import pkg/ptr_math

proc malloc(size: csize_t): pointer {.importc.}
proc free(p: pointer, size: csize_t) {.importc.}

const BaliGCPointerMapSize* {.intdefine.} = 64

func hash(p: pointer): uint {.inline.} =
  cast[uint](p) shr 3'u32

type
  AllocationError* = object of Defect

  GCPointer* = object
    start*: uint
    size*: uint
    marked*: bool

  GCList* = object
    next*: ptr GCList
    data*: GCPointer

  Cell* = object
    stackStart*: pointer
    ptrMap*: array[BaliGCPointerMapSize, ptr GCList]
    ptrNum*, size*, refCount*: uint
    min*, max*: uint
    globals*: seq[GCList]

func exists*(list: var GCList, ptrVal: uint): bool =
  var curr = addr(list)
  while curr != nil:
    if curr[].data.start == ptrVal:
      return true

    curr = curr.next

  return false

proc add*(beginList: var ptr GCList, data: GCPointer) =
  if beginList == nil:
    return

  var elem = cast[ptr GCList](alloc(sizeof(GCList)))
  elem[] = GCList(data: data, next: beginList)
  beginList = elem

proc del*(beginList: var ptr GCList, idx: uint) =
  var node, prev: ptr GCList
  if (node = beginList; node == nil):
    return

  var i: uint
  while node != nil:
    if i == idx:
      if prev != nil:
        prev.next = node.next
      else:
        beginList = node.next

      dealloc(node)
      return

    prev = node
    node = node.next
    inc i

var gcObject {.global.} = Cell(refCount: 0)

proc initializeGC*(ptrVal: pointer, size: uint) =
  if gcObject.refCount != 0:
    inc gcObject.refCount
    return

  gcObject = Cell(
    stackStart: ptrVal,
    ptrNum: 0,
    refCount: 1,
    size: size,
    min: uint.high,
    max: 0,
    globals: @[],
  )

func swap[T](a, b: var ptr T) =
  var tmp = a
  a = b
  b = tmp

proc search*(ptrVal: uint, elem: ptr GCList): ptr GCList =
  var elem = elem

  while elem != nil:
    if ptrVal >= elem.data.start and elem.data.start + elem.data.size >= ptrVal:
      return elem

    elem = elem.next

proc index*(ptrVal: uint): ptr GCList =
  if ptrVal > gcObject.max or ptrVal < gcObject.min:
    return

  let hash = uint(hash(cast[pointer](ptrVal)) mod BaliGCPointerMapSize)
  var elem: ptr GCList

  if (elem = search(ptrVal, gcObject.ptrMap[hash]); elem != nil):
    return elem

  var i: uint
  while (inc i; i + hash < BaliGCPointerMapSize) or hash > i:
    if (hash > i and (elem = search(ptrVal, gcObject.ptrMap[hash - i]); elem != nil)):
      return elem

    if (hash + i) < BaliGCPointerMapSize and
        (elem = search(ptrVal, gcObject.ptrMap[hash + i]); elem != nil):
      return elem

proc mark*(start: ptr uint8, stop: ptr uint8)

proc markStack*() =
  var tmp: uint8
  mark(cast[ptr uint8](gcObject.stackStart), tmp.addr)
  for elem in gcObject.globals:
    mark(
      cast[ptr uint8](elem.data.start),
      cast[ptr uint8](elem.data.start + elem.data.size),
    )

proc mark*(start, stop: ptr uint8) =
  var start = cast[uint](start)
  var stop = cast[uint](stop)

  if start > stop:
    swap(start, stop)

  var marked: uint

  while start < stop:
    var idx = index(start)
    if idx != nil and not idx.data.marked:
      idx.data.marked = true
      inc marked
      mark(
        cast[ptr uint8](idx.data.start), cast[ptr uint8](idx.data.start + idx.data.size)
      )

    start += 1

  debug "heap: marked " & $marked & " cells as reachable"

proc freeElement*(elem: ptr GCList) {.inline.} =
  ## Free up the memory held by a GC node
  free(cast[pointer](elem.data.start), elem.data.size)
  dec gcObject.ptrNum

proc gcFree*(ptrVal: pointer) =
  var list = gcObject.ptrMap[hash(ptrVal) mod BaliGCPointerMapSize]
  if list != nil and list[].exists(cast[uint](list)):
    list.del(cast[uint](list))
    freeElement(list)

proc sweep*() =
  for i in 0 ..< BaliGCPointerMapSize:
    var elem = gcObject.ptrMap[i]
    var k: uint

    while elem != nil:
      if not elem.data.marked:
        freeElement(elem)
        elem = elem.next
        gcObject.ptrMap[i].del(k)
      else:
        elem.data.marked = true
        elem = elem.next

      inc k

proc collect*() {.inline.}

proc baliMSAlloc*(size: SomeUnsignedInt): pointer =
  ## Allocate a pointer of the specified size and track it using
  ## Bali's internal mark-and-sweep garbage collector.
  debug "heap: allocating chunk of size " & $size & " bytes"

  var ptrVal: uint
  if (ptrVal = cast[uint](alloc(size)); ptrVal == cast[uint](nil)):
    when defined(baliGCThrowDefectOnAllocFailure):
      raise newException(
        AllocationError, "Failed to allocate memory chunk of size " & $size & " bytes!"
      )
    else:
      warn "heap: failed to allocate memory chunk of size " & $size &
        " bytes! (Use -d:baliGCThrowDefectOnAllocFailure to make this a fatal error)"
      return

  zeroMem(cast[pointer](ptrVal), size)

  debug "heap: allocated chunk successfully"

  var gcPtr = GCPointer(start: ptrVal, size: size.uint(), marked: true)

  if gcObject.min > ptrVal:
    debug "heap: current minimum address is greater than the new allocated chunk, setting the minimum address to the new allocated chunk"
    gcObject.min = ptrVal

  if cast[pointer](gcObject.max) < cast[pointer](ptrVal + size):
    debug "heap: current maximum address is smaller than the new allocated chunk"
    gcObject.max = cast[uint](ptrVal + size)

  debug "heap: appending chunk to pointer map"
  gcObject.ptrMap[cast[uint](hash(cast[pointer](ptrVal)) mod BaliGCPointerMapSize)].add(
    gcPtr
  )
  inc gcObject.ptrNum

  debug "heap: current number of pointers: " & $gcObject.ptrNum

  if gcObject.ptrNum >= gcObject.size:
    debug "heap: number of pointers is greater than the GC size, performing collection"
    # collect()

  cast[pointer](ptrVal)

proc collect*() {.inline.} =
  ## Perform a garbage collection.
  markStack()
  sweep()
