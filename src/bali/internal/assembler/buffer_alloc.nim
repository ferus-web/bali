## This file contains routines to allocate memory buffers with the executable bit.
## **NOTE**: This should ONLY be used in tandem with a JIT's assembler and no other place!
##
## Copyright (C) 2025 Trayambak Rai (xtrayambak at disroot dot org)
#!fmt: off
import std/[logging]
import pkg/bali/platform/libc
#!fmt: on

proc allocateExecutableBuffer*(size: uint64, readable, writable: bool): pointer =
  debug "assembler/buffer_alloc: allocating executable buffer of size " & $size &
    " bytes (readable=" & $readable & "; writable=" & $writable & ')'
  when defined(windows):
    assert(
      (readable or writable) and not (not readable and writable),
      "Win32 does not support:\n* Non readable, writable buffers\n* Untouchable buffers (no read or write bits)",
    )
    var oldProt: DWORD
    let perms =
      if readable and writable:
        PAGE_EXECUTE_READWRITE
      elif readable and not writable:
        PAGE_READONLY
      else:
        unreachable

    return VirtualAlloc(NULL, size, MEM_COMMIT or MEM_RESERVE, perms)
  else:
    var perms = PROT_EXEC
    if readable:
      perms = perms or PROT_READ

    if writable:
      perms = perms or PROT_WRITE

    var address: pointer
    discard posix_memalign(address.addr, sysconf(SC_PAGESIZE).csize_t, size)
    discard mprotect(address, size.int32, ensureMove(perms))

    return address
