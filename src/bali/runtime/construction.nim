## Helpers for constructing JSValue(s) without breaking your fingers
## 
## Copyright (C) 2025 Trayambak Rai (xtrayambak at disroot dot org)

#!fmt: off
import pkg/bali/runtime/vm/atom,
       pkg/bali/runtime/types
#!fmt: on

{.push inline, sideEffect.}

proc integer*(runtime: Runtime, value: SomeInteger): JSValue =
  integer(runtime.heapManager, value)

proc floating*(runtime: Runtime, value: SomeFloat | SomeInteger): JSValue =
  floating(runtime.heapManager, value)

proc str*(runtime: Runtime, value: string): JSValue =
  str(runtime.heapManager, value)

proc sequence*(runtime: Runtime, value: seq[MAtom]): JSValue =
  sequence(runtime.heapManager, value)

proc undefined*(runtime: Runtime): JSValue =
  undefined(runtime.heapManager)

proc null*(runtime: Runtime): JSValue =
  null(runtime.heapManager)

proc bigint*(runtime: Runtime, value: SomeInteger | string): JSValue =
  bigint(runtime.heapManager, value)

proc boolean*(runtime: Runtime, value: bool): JSValue =
  boolean(runtime.heapManager, value)

proc obj*(runtime: Runtime): JSValue =
  obj(runtime.heapManager)

{.pop.}
