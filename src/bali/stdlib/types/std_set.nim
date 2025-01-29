## Set type implementation
## Author: Trayambak Rai (xtrayambak at disroot dot org)
import std/[options]
import bali/runtime/[arguments, atom_helpers, types, bridge]
import bali/runtime/abstract/[coercion, equating]
import mirage/atom

type JSSet* = object
  `@ internal`*: MAtom ## Sequence MAtom

proc generateInternalIR*(runtime: Runtime) =
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
    "add",
    proc(setAtom: MAtom) =
      # 24.2.3.1 Set.prototype.add ( value )

      var value = &runtime.argument(1)

      # 1. Let S be the this value.
      var setVal = setAtom.tagged("internal").getSequence()

      # 3. For each element e of S.[[SetData]], do
      for elem in setVal:
        # a. If e is not EMPTY and SameValueZero(e, value) is true, then
        if runtime.isStrictlyEqual(elem, value):
          # i. Return S.
          ret setAtom

      # 4. If value is -0𝔽, set value to +0𝔽.
      if value.isNumber and runtime.ToNumber(value) == -0f:
        value = floating(0f)

      # 5. Append value to S.[[SetData]].
      setVal.sequence.add(move(value))

      var setAtom = setAtom
      setAtom.tag("internal", move(setVal))
        # FIXME: We aren't changing the original set right now due to a limitation in Mirage. Fix this!

      # 6. Return S.
      ret move(setAtom)
    ,
  )
