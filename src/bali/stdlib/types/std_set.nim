## Set type implementation
## Author: Trayambak Rai (xtrayambak at disroot dot org)
import std/[options]
import bali/runtime/[arguments, atom_helpers, types, wrapping, bridge]
import bali/runtime/abstract/[coercion, equating, slots]
import bali/internal/sugar
import bali/runtime/vm/atom

type JSSet* = object
  `@ internal`*: JSValue ## Sequence MAtom

proc generateStdIR*(runtime: Runtime) =
  runtime.registerType("Set", JSSet)
  runtime.defineConstructor(
    "Set",
    proc() =
      # 24.2.1.1 Set ( [ iterable ] )
      # FIXME: Non-compliant.

      var set = runtime.createObjFromType(JSSet)
      set.tag("internal", sequence(@[]))
      ret set
    ,
  )

  runtime.definePrototypeFn(
    JSSet,
    "toString",
    proc(setAtom: JSValue) =
      # FIXME: non-compliant.
      # this just exists to make primitive coercion happy

      ret "[object Set]"
    ,
  )

  runtime.definePrototypeFn(
    JSSet,
    "add",
    proc(setAtom: JSValue) =
      # 24.2.3.1 Set.prototype.add ( value )

      var value = &runtime.argument(1)

      # 1. Let S be the this value.
      var setVal = &(&setAtom.tagged("internal")).getSequence()

      # 2. Perform ? RequireInternalSlot(S, [[SetData]]).
      runtime.RequireInternalSlot(setAtom, JSSet)

      # 3. For each element e of S.[[SetData]], do
      for i, _ in setVal:
        # a. If e is not EMPTY and SameValueZero(e, value) is true, then
        if runtime.isStrictlyEqual(setVal[i].addr, value):
          # i. Return S.
          ret setAtom

      # 4. If value is -0𝔽, set value to +0𝔽.
      if value.isNumber and runtime.ToNumber(value) == -0f:
        value = floating(0f)

      # 5. Append value to S.[[SetData]].
      setVal.add(value[])
      setAtom.tag("internal", sequence(setVal))

      # 6. Return S.
      ret setAtom
    ,
  )

  runtime.definePrototypeFn(
    JSSet,
    "size",
    proc(setAtom: JSValue) =
      # 24.2.3.9 Set.prototype.size
      # Set.prototype.size is an accessor property whose set accessor function is undefined. Its get accessor
      # function performs the following steps when called:

      # 1. Let S be this value.
      # 2. Perform ? RequireInternalSlot(S, [[SetData]])
      runtime.RequireInternalSlot(setAtom, JSSet)

      var setVal = &(&setAtom.tagged("internal")).getSequence()

      # 3. Let count be 0.
      # 4. For each element e of S.[[SetData]], do
      # a. If e is not empty, set count to count + 1.
      let count = setVal.len

      # 5. Return 𝔽(count).
      ret count
    ,
  )

  runtime.definePrototypeFn(
    JSSet,
    "delete",
    proc(setAtom: JSValue) =
      ## 24.2.4.4 Set.prototype.delete ( value )

      # 1. Let S be the this value.
      # 2. Perform ? RequireInternalSlot(S, [[SetData]]).
      runtime.RequireInternalSlot(setAtom, JSSet)

      # 3. Set value to CanonicalizeKeyedCollectionKey(value).
      let value = &runtime.argument(1)

      # 4. For each element e of S.[[SetData]], do
      var data = &(&setAtom.tagged("internal")).getSequence()

      var index = -1
      for i, elem in data:
        # a. If e is not empty and SameValue(e, value) is true, then
        # FIXME: Non-compliant.

        if isStrictlyEqual(runtime, data[i].addr, value):
          index = i
          break

      let found = index != -1
      if found:
        # i. Replace the element of S.[[SetData]] whose value is e with an element whose value is empty.
        data.delete(index)
        setAtom.tag("internal", sequence(move(data)))

        # ii. Return true.
        ret true

      ret false
    ,
  )

  runtime.definePrototypeFn(
    JSSet,
    "has",
    proc(setAtom: JSValue) =
      ## 24.2.4.8 Set.prototype.has ( value )

      # 1. Let S be the this value.
      # 2. Perform ? RequireInternalSlot(S, [[SetData]]).
      runtime.RequireInternalSlot(setAtom, JSSet)

      # 3. Set value to CanonicalizeKeyedCollectionKey(value).
      let value = &runtime.argument(1)

      # 4. For each element e of S.[[SetData]], do
      let data = &(&setAtom.tagged("internal")).getSequence()

      for i, _ in data:
        # i. If e is not empty and SameValue(e, value) is true, return true.
        # FIXME: Non-compliant.
        if isStrictlyEqual(runtime, data[i].addr, value):
          ret true

      # 5. Return false.
      ret false
    ,
  )

  runtime.definePrototypeFn(
    JSSet,
    "clear",
    proc(setAtom: JSValue) =
      ## 24.2.4.1 Set.prototype.add ( value )

      # 1. Let S be the this value.
      # 2. Perform ? RequireInternalSlot(S, [[SetData]]).
      runtime.RequireInternalSlot(setAtom, JSSet)

      # 3. For each element e of S.[[SetData]], do
      # a. Replace the element of S.[[SetData]] whose value is e with an element whose value is empty.
      setAtom.tag("internal", sequence(newSeq[MAtom](0)))

      # 4. Return undefined.
      ret undefined()
    ,
  )
