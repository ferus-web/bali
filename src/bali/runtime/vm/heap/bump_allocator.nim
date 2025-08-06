## Bump allocator implementation
##
## Copyright (C) 2025 Trayambak Rai (xtrayambak at disroot dot org)
import std/posix
import pkg/bali/platform/libc

const DefaultAllocatorBufferSize* =
  when defined(amd64) or defined(aarch64) or defined(riscv64):
    8_388_608'u64 # 8MB
  else:
    2_097_152'u64 # 2MB

type BumpAllocator* {.acyclic.} = object
  pool: pointer

  offset, cap: uint64

func remaining*(allocator: BumpAllocator): uint64 {.cdecl.} =
  allocator.cap - allocator.offset

func outOfMemory*(allocator: BumpAllocator): bool {.cdecl.} =
  allocator.remaining < 1

func allocate*(allocator: var BumpAllocator, size: uint64): pointer {.cdecl.} =
  when not defined(release):
    assert(not allocator.outOfMemory, "Out of memory")

  let pntr = cast[pointer](cast[uint64](allocator.pool) + allocator.offset)
  allocator.offset += size

  pntr

proc release*(allocator: var BumpAllocator) =
  free(allocator.pool)

proc initBumpAllocator*(
    size: uint64 = DefaultAllocatorBufferSize
): BumpAllocator {.sideEffect.} =
  BumpAllocator(pool: malloc(size), cap: size)
