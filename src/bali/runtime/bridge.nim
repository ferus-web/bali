import std/[logging, tables, options, strutils, hashes, importutils]
import mirage/runtime/prelude
import mirage/ir/generator
import bali/runtime/[atom_obj_variant, atom_helpers, types, normalize]
import bali/stdlib/errors
import bali/internal/sugar
import pretty

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

  let moduleName = normalizeIRName(&typName & '.' & name)
  runtime.ir.newModule(moduleName)
  let name =
    "BALI_" & toUpperAscii((&typName).normalizeIRName()) & '_' &
    toUpperAscii(normalizeIRName name)
  runtime.vm.registerBuiltin(
    name,
    proc(_: Operation) =
      fn(),
  )
  runtime.ir.call(name)

proc setProperty*[T](
    runtime: Runtime, prototype: typedesc[T], name: string, value: MAtom
) {.inline.} =
  for i, typ in runtime.types:
    if typ.proto == hash($prototype):
      runtime.types[i].members[name] = initAtomOrFunction[NativeFunction](value)

proc dumpStatistics*(
  runtime: Runtime
): RuntimeStats =
  info "runtime: dumping statistics"
  var stats: RuntimeStats

  stats.atomsAllocated = uint(runtime.vm.stack.len)
  stats.bytecodeSize = uint(runtime.vm.tokenizer.input.len / 1024)
  stats.breaksGenerated = uint(runtime.irHints.breaksGeneratedAt.len)
  stats.vmHasHalted = runtime.vm.halt
  stats.fieldAccesses = runtime.statFieldAccesses
  stats.typeofCalls = runtime.statTypeofCalls
  stats.clausesGenerated = uint(runtime.ir.modules.len)

  let allocStats = runtime.allocStatsStart - getAllocStats()
  stats.numAllocations = uint(allocStats.allocCount)
  stats.numDeallocations = uint(allocStats.deallocCount)

  info "runtime: completed statistics dump"

  stats

proc setProperty*[V: not MAtom, T](
  runtime: Runtime,
  prototype: typedesc[T], name: string, value: V
) {.inline.} =
  runtime.setProperty(prototype = prototype, name = name, value = value.wrap())

proc defineFn*(runtime: Runtime, name: string, fn: NativeFunction) =
  ## Expose a native function to a JavaScript runtime.
  debug "runtime: exposing native function to runtime: " & name
  runtime.ir.newModule(normalizeIRName name)
  let builtinName = "BALI_" & toUpperAscii(normalizeIRName(name))
  runtime.vm.registerBuiltin(
    builtinName,
    proc(_: Operation) =
      fn(),
  )
  runtime.ir.call(builtinName)

proc definePrototypeFn*[T](runtime: Runtime, prototype: typedesc[T], name: string, fn: NativePrototypeFunction) =
  runtime.vm.registerBuiltin(
    name,
    proc(_: Operation) =
      let typ = deepCopy(runtime.vm.registers.callArgs[0])
      runtime.vm.registers.callArgs.delete(0)
      fn(typ)
  )
  for i, typ in runtime.types:
    if typ.proto == hash($prototype):
      runtime.types[i].prototypeFunctions[name] = fn

proc getReturnValue*(runtime: Runtime): Option[MAtom] =
  ## Get the value in the return-value register, if there is any.
  ## NOTE: You need to disable aggressive retval scrubbing if you want to get the return value of a function called in bytecode
  runtime.vm.registers.retVal

proc createAtom*(typ: JSType): MAtom =
  var atom = obj()

  for name, member in typ.members:
    if member.isAtom():
      let idx = atom.objValues.len
      atom.objValues &= undefined()
      atom.objFields[name] = idx
  
  atom.tag("bali_object_type", typ.proto.int)

  atom

proc isA*[T: object](runtime: Runtime, atom: MAtom, typ: typedesc[T]): bool =
  ## This function returns a boolean based off of whether `atom` is a replica of the supplied Nim-native type `typ`.
  ## It checks the `bali_object_type` that's attached to all objects created by `createAtom` (and by extension, `createObjFromType`)
  debug "runtime: isA(" & atom.crush() & "): checking if atom is a replica of " & $typ

  if atom.kind != Object:
    debug "runtime: isA(" & atom.crush() & "): atom is not an object, returning false."
    return false

  let objTypOpt = atom.tagged("bali_object_type")

  if !objTypOpt:
    debug "runtime: isA(" & atom.crush() & "): atom does not contain the tag `bali_object_type`, returning false. This is weird."
    return false

  if (&objTypOpt).kind != Integer:
    warn "runtime: isA(" & atom.crush() & "): atom's `bali_object_type` tag is not an integer! It is a " & $(&objTypOpt).kind

  let objTyp = &getInt(&objTypOpt)

  for etyp in runtime.types:
    if etyp.proto != hash($typ):
      continue

    if etyp.proto.int == objTyp:
      debug "runtime: isA(" & atom.crush() & "): atom is a replica of " & $typ
      return true

  false

proc getMethod*(runtime: Runtime, v: MAtom, p: string): Option[NativePrototypeFunction] =
  for typ in runtime.types:
    if typ.proto.int != &getInt(&v.tagged("bali_object_type")):
      continue

    for name, meth in typ.prototypeFunctions:
      if name == p:
        return some(meth)

proc getTypeFromName*(runtime: Runtime, name: string): Option[JSType] =
  ## Returns a registered JS type based on its name, if it exists.
  for typ in runtime.types:
    if typ.name == name:
      return some(typ)

proc createObjFromType*[T](runtime: Runtime, typ: typedesc[T]): MAtom =
  for etyp in runtime.types:
    if etyp.proto == hash($typ):
      return etyp.createAtom()

  raise newException(ValueError, "No such registered type: `" & $typ & '`')

proc defineConstructor*(runtime: Runtime, name: string, fn: NativeFunction) {.inline.} =
  debug "runtime: exposing constructor for type: " & name
  ## Expose a constructor for a type to a JavaScript runtime.

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

template ret*(atom: MAtom) =
  ## Shorthand for:
  ## ..code-block:: Nim
  ##  runtime.vm.registers.retVal = some(atom)
  ##  return
  runtime.vm.registers.retVal = some(atom)
  return

template ret*[T](value: T) =
  ## Shorthand for:
  ## ..code-block:: Nim
  ##  runtime.vm.registers.retVal = some(wrap(value))
  ##  return
  runtime.vm.registers.retVal = some(wrap(value))
  return

func argumentCount*(runtime: Runtime): int {.inline.} =
  ## Get the number of atoms in the `CallArgs` register
  runtime.vm.registers.callArgs.len

proc registerType*[T](runtime: Runtime, name: string, prototype: typedesc[T]) =
  var jsType: JSType

  for fname, fatom in prototype().fieldPairs:
    #if not fname.startsWith('@'):
    jsType.members[fname] = initAtomOrFunction[NativeFunction](fatom.wrap())
    #else:
    #  debug "runtime: registerType(): field name starts with at-the-rate (@); not exposing it to the JS runtime."
  
  jsType.proto = hash($prototype)
  jsType.name = name

  runtime.types &= jsType.move()
  let typIdx = runtime.types.len - 1

  runtime.vm.registerBuiltin(
    "BALI_CONSTRUCTOR_" & strutils.toUpperAscii(name),
    proc(_: Operation) =
      if runtime.types[typIdx].constructor == nil:
        runtime.typeError(runtime.types[typIdx].name & " is not a constructor")

      runtime.types[typIdx].constructor(),
  )
