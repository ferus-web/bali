proc free*(p: pointer): void {.importc, header: "<stdlib.h>".}
proc malloc*(size: uint64): pointer {.importc, header: "<stdlib.h>".}
