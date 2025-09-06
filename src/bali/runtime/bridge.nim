## A neat JavaScript <-> Nim bridge.

import std/[logging, tables, options, strutils, hashes, importutils]
import bali/runtime/vm/prelude
import bali/runtime/vm/ir/generator
import
  bali/runtime/
    [atom_obj_variant, wrapping, atom_helpers, types, normalize, construction]
import bali/stdlib/errors
import bali/internal/sugar

privateAccess(Runtime)
privateAccess(PulsarInterpreter)
privateAccess(AllocStats)

proc defineFn*[T](
    runtime: Runtime, prototype: typedesc[T], name: string, fn: NativeFunction
) =
  ## Expose a method to the JavaScript runtime for a particular type.

  let typName = (
    proc(): Option[string] =
      for typ in runtime.types:
        if typ.proto == hash($prototype):
          return typ.name.some()

      none(string)
  )()

  if not *typName:
    raise newException(
      ValueError, "Attempt to define function `" & name & "` for undefined prototype"
    )

  #[ let moduleName = normalizeIRName(&typName & '.' & name)
  runtime.ir.newModule(moduleName)
  let name =
    "BALI_" & toUpperAscii((&typName).normalizeIRName()) & '_' &
    toUpperAscii(normalizeIRName name) ]#

  for i, typ in runtime.types:
    if typ.proto != hash($prototype):
      continue

    runtime.types[i].members[name] = initAtomOrFunction[NativeFunction](fn)

proc setProperty*[T](
    runtime: Runtime, prototype: typedesc[T], name: string, value: JSValue
) =
  ## Set the property of a static object.
  ## This function accepts a JavaScript value as the property's new value.
  for i, typ in runtime.types:
    if typ.proto == hash($prototype):
      runtime.types[i].members[name] = initAtomOrFunction[NativeFunction](value)

proc setProperty*[T, V](
    runtime: Runtime, prototype: typedesc[T], name: string, value: V
) =
  ## Set the property of a static object.
  ## This function accepts any value that can be wrapped into a JavaScript value.
  for i, typ in runtime.types:
    if typ.proto == hash($prototype):
      runtime.types[i].members[name] = initAtomOrFunction[NativeFunction](wrap(value))

proc dumpStatistics*(runtime: Runtime): RuntimeStats =
  ## Get a `RuntimeStats` struct containing all the statistics about the
  ## runtime's state, including the VM's state and code generator's statistics.
  info "runtime: dumping statistics"
  var stats: RuntimeStats

  stats.atomsAllocated = uint(runtime.vm.stack.len)
  stats.bytecodeSize = uint(runtime.vm.tokenizer.input.len / 1024)
  stats.breaksGenerated = uint(runtime.irHints.breaksGeneratedAt.len)
  stats.vmHasHalted = runtime.vm.halt
  stats.fieldAccesses = runtime.statFieldAccesses
  stats.typeofCalls = runtime.statTypeofCalls
  stats.clausesGenerated = uint(runtime.ir.modules.len)

  let allocStats = getAllocStats() - runtime.allocStatsStart
  stats.numAllocations = uint(allocStats.allocCount)
  stats.numDeallocations = uint(allocStats.deallocCount)

  info "runtime: completed statistics dump"

  stats

proc setProperty*[V: not JSValue, T](
    runtime: Runtime, prototype: typedesc[T], name: string, value: V
) {.inline.} =
  runtime.setProperty(prototype = prototype, name = name, value = value.wrap())

proc defineFn*(runtime: Runtime, name: string, fn: NativeFunction) =
  ## Expose a native function to a JavaScript runtime.
  debug "runtime: exposing native function to runtime: " & name
  runtime.ir.newModule(normalizeIRName name)
  let builtinName = "BALI_" & toUpperAscii(normalizeIRName(name))
  runtime.vm[].registerBuiltin(
    builtinName,
    proc(_: Operation) =
      fn(),
  )
  runtime.ir.call(builtinName)

proc definePrototypeFn*[T](
    runtime: Runtime, prototype: typedesc[T], name: string, fn: NativePrototypeFunction
) =
  ## Add a function to a type's prototype.
  ## Each instance of this type will be able to invoke the provided function.
  for i, typ in runtime.types:
    if typ.proto == hash($prototype):
      runtime.types[i].prototypeFunctions[name] = fn

proc getReturnValue*(runtime: Runtime): Option[JSValue] =
  ## Get the value in the return-value register, if there is any.
  ## **NOTE**: You need to disable the aggressive retval scrubbing optimization if you want to get the return value of a function called in bytecode
  runtime.vm.registers.retVal

proc get*(runtime: Runtime, identifier: string): Option[JSValue] =
  for value in runtime.values:
    if value.kind != vkGlobal:
      continue
    if value.identifier != identifier:
      continue
    if value.index > runtime.vm.stack.len.uint:
      continue

    return some(runtime.vm.stack[value.index])

proc isA*[T: object](runtime: Runtime, atom: JSValue, typ: typedesc[T]): bool =
  ## This function returns a boolean based off of whether `atom` is a replica of the supplied Nim-native type `typ`.
  ## It checks the `bali_object_type` that's attached to all objects created by `createAtom` (and by extension, `createObjFromType`)
  debug "runtime: isA(" & atom.crush() & "): checking if atom is a replica of " & $typ

  if atom.kind != Object:
    debug "runtime: isA(" & atom.crush() & "): atom is not an object, returning false."
    return false

  let objTypOpt = atom.tagged("bali_object_type")

  if !objTypOpt:
    debug "runtime: isA(" & atom.crush() &
      "): atom does not contain the tag `bali_object_type`, returning false. This is weird."
    return false

  if (&objTypOpt).kind != Integer:
    warn "runtime: isA(" & atom.crush() &
      "): atom's `bali_object_type` tag is not an integer! It is a " & $(&objTypOpt).kind

  let objTyp = &getInt(&objTypOpt)

  for etyp in runtime.types:
    if etyp.proto != hash($typ):
      continue

    if etyp.proto.int == objTyp:
      debug "runtime: isA(" & atom.crush() & "): atom is a replica of " & $typ
      return true

  false

proc getMethod*(runtime: Runtime, v: JSValue, p: string): Option[proc() {.gcsafe.}] =
  ## Get a method from the provided object's prototype.
  ## Returns an `Option[proc()]` if a function with the name `p` is found (it is wrapped!),
  ## else it returns an empty `Option`.
  ##
  ## If a `BytecodeCallable` is found, `getMethod` creates its own wrapper function.
  if v.contains(p):
    debug "runtime: getMethod(): value has field: " & p

    case v[p].kind
    of NativeCallable:
      debug "runtime: getMethod(): method is a native callable"
      return some(v[p].fn)
    of BytecodeCallable:
      debug "runtime: getMethod(): method is a bytecode callable; generating wrapper."
      return some(
        proc() =
          runtime.vm.registers.callArgs.add(v)
          runtime.vm[].call(&getBytecodeClause(v[p]), default(Operation))
            # FIXME: I don't think giving a bogus operation will allow us to get proper tracebacks...

          # If the function returned nothing, just push undefined to that register.
          if !runtime.vm.registers.retVal:
            runtime.vm.registers.retVal = some(undefined(runtime.heapManager))
      )
    else:
      debug "runtime: getMethod(): field is not callable"
  else:
    debug "runtime: getMethod(): value does not have function member: " & p

proc getTypeFromName*(runtime: Runtime, name: string): Option[JSType] =
  ## Returns a registered JS type based on its name, if it exists.
  for typ in runtime.types:
    if typ.name == name:
      return some(typ)

proc defineConstructor*(runtime: Runtime, name: string, fn: NativeFunction) {.inline.} =
  ## Expose a constructor for a type to a JavaScript runtime.
  debug "runtime: exposing constructor for type: " & name

  var found = false
  for i, jtype in runtime.types:
    if jtype.name == name:
      found = true
      runtime.types[i].constructor = fn
      break

  if not found:
    raise newException(
      ValueError, "Attempt to define constructor for unknown type: " & name
    )

template ret*(atom: JSValue) =
  ## Return an atom.
  ## Shorthand for:
  ## ..code-block:: Nim
  ##  runtime.vm.registers.retVal = some(atom)
  ##  return
  runtime.vm.registers.retVal = some(atom)
  return

template dangerRet*(atom: sink MAtom) =
  {.
    warning:
      "Don't use `dangerRet(MAtom)`, use `ret(JSValue)` instead. This is dangerous!"
  .}
  ## Return an atom.
  ## **WARNING**: The atom **MUST** be allocated on the heap, otherwise you
  ## will be rewarded with undefined behaviour and undiagnosable crashes.
  ## The functions `str`, `integer`, `floating`, `obj`, and any other atom creation
  ## functions that don't have "stack" in their name allocate on the heap alongside
  ## `createObjFromType` are safe to use.
  runtime.vm.registers.retVal = some(atom.addr)
  return

template ret*[T](value: T) =
  ## Return an atom.
  ## Shorthand for:
  ## ..code-block:: Nim
  ##  runtime.vm.registers.retVal = some(runtime.wrap(value))
  ##  return
  runtime.vm.registers.retVal = some(runtime.wrap(value))
  return

func argumentCount*(runtime: Runtime): int {.inline.} =
  ## Get the number of atoms in the `CallArgs` register
  runtime.vm.registers.callArgs.len

proc registerType*[T](runtime: Runtime, name: string, prototype: typedesc[T]) =
  ## Register a type in the JavaScript engine instance with the name of the type (`name`) alongside its prototype (`prototype`).
  var jsType: JSType

  let index = runtime.types.len
  jsType.proto = hash($prototype)
  jsType.name = name

  runtime.types &= jsType

  for fname, fatom in prototype().fieldPairs:
    when fatom is JSValue:
      jsType.members[fname] = initAtomOrFunction[NativeFunction](undefined(runtime))
    else:
      jsType.members[fname] = initAtomOrFunction[NativeFunction](runtime.wrap(fatom))

  runtime.types[index] = ensureMove(jsType)
  let typIdx = runtime.types.len - 1

  runtime.vm[].registerBuiltin(
    "BALI_CONSTRUCTOR_" & strutils.toUpperAscii(name),
    proc(_: Operation) {.gcsafe.} =
      if runtime.types[typIdx].constructor == nil:
        runtime.typeError(runtime.types[typIdx].name & " is not a constructor")

      runtime.types[typIdx].constructor(),
  )

proc call*(runtime: Runtime, callable: JSValue, arguments: varargs[JSValue]): JSValue =
  if callable.kind != BytecodeCallable:
    raise newException(ValueError, "Cannot call value of type " & $callable.kind)

  for arg in arguments:
    runtime.vm.registers.callArgs &= arg

  runtime.vm[].call(&callable.getBytecodeClause(), default(Operation))
  runtime.vm[].run()

  let retVal = runtime.getReturnValue()
  if !retVal:
    return undefined(runtime.heapManager)

  &retVal
