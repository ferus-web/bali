## Nim bindings for certain libc functions on certain platforms
##
## Copyright (C) 2025 Trayambak Rai

when defined(posix):
  import std/posix

  proc free*(p: pointer): void {.importc, header: "<stdlib.h>".}
  proc malloc*(size: uint64): pointer {.importc, header: "<stdlib.h>".}

  export posix

when defined(windows):
  import std/winlean

  var
    MEM_COMMIT* {.importc, header: "<windows.h>".}: int32
    MEM_RESERVE* {.importc, header: "<windows.h>".}: int32

  proc VirtualProtect*(
    lpAddress: pointer, dwSize: WinSizeT, flNewProtect: DWORD, lpflOldProtect: PDWORD
  ): WINBOOL {.stdcall, dynlib: "kernel32", importc: "VirtualProtect", sideEffect.}

  proc VirtualAlloc*(
    lpAddress: pointer, dwSize: WinSizeT, flAllocationType: DWORD, flProtect: DWORD
  ): pointer {.stdcall, dynlib: "kernel32", importc: "VirtualAlloc", sideEffect.}

  export winlean
