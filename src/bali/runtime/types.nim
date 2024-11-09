## Runtime types

import std/[options, hashes, logging, strutils, tables]
import mirage/ir/generator
import mirage/runtime/prelude
import bali/grammar/prelude
import bali/internal/sugar
import bali/stdlib/errors
import bali/runtime/[normalize, atom_obj_variant, atom_helpers]
import pretty

type
  NativeFunction* = proc()

  ValueKind* = enum
    vkGlobal
    vkLocal
    vkInternal ## or immediate

  IndexParams* = object
    priorities*: seq[ValueKind] = @[vkLocal, vkGlobal]

    fn*: Option[Function]
    stmt*: Option[Statement]

  Value* = object
    index*: uint
    identifier*: string
    case kind*: ValueKind
    of vkLocal:
      ownerFunc*: Hash
    of vkInternal:
      ownerStmt*: Hash
    else:
      discard

  SemanticErrorKind* = enum
    UnknownIdentifier
    ImmutableReassignment

  SemanticError* = object
    line*, col*: uint = 1
    case kind*: SemanticErrorKind
    of UnknownIdentifier:
      unknown*: string
    of ImmutableReassignment:
      imIdent*: string
      imNewValue*: MAtom

  InterpreterOpts* = object
    test262*: bool = false

  JSType* = object
    name*: string
    constructor*: NativeFunction
    members*: Table[string, AtomOrFunction[NativeFunction]]
    singletonId*: uint

    proto*: Hash

  Runtime* = ref object
    ast*: AST
    ir*: IRGenerator
    vm*: PulsarInterpreter
    opts*: InterpreterOpts

    addrIdx*: uint
    values*: seq[Value]
    semanticErrors*: seq[SemanticError]
    clauses*: seq[string]

    types*: seq[JSType]

proc unknownIdentifier*(identifier: string): SemanticError {.inline.} =
  SemanticError(kind: UnknownIdentifier, unknown: identifier)

proc immutableReassignmentAttempt*(stmt: Statement): SemanticError {.inline.} =
  SemanticError(
    kind: ImmutableReassignment,
    imIdent: stmt.reIdentifier,
    imNewValue: stmt.reAtom,
    line: stmt.line,
    col: stmt.col,
  )

proc defaultParams*(fn: Function): IndexParams {.inline.} =
  IndexParams(fn: some fn)

proc internalIndex*(stmt: Statement): IndexParams {.inline.} =
  IndexParams(priorities: @[vkInternal], stmt: some stmt)

proc markInternal*(runtime: Runtime, stmt: Statement, ident: string) =
  var toRm: seq[int]
  for i, value in runtime.values:
    if value.kind == vkInternal and value.identifier == ident:
      toRm &= i

  for rm in toRm:
    runtime.values.del(rm)

  runtime.values &=
    Value(
      kind: vkInternal, index: runtime.addrIdx, identifier: ident, ownerStmt: hash(stmt)
    )

  info "Ident \"" & ident & "\" is being internally marked at index " & $runtime.addrIdx &
    " with statement hash: " & $hash(stmt)

  inc runtime.addrIdx

proc markGlobal*(runtime: Runtime, ident: string) =
  var toRm: seq[int]
  for i, value in runtime.values:
    if value.kind == vkGlobal and value.identifier == ident:
      toRm &= i

  for rm in toRm:
    runtime.values.del(rm)

  runtime.values &= Value(kind: vkGlobal, index: runtime.addrIdx, identifier: ident)

  info "Ident \"" & ident & "\" is being globally marked at index " & $runtime.addrIdx

  inc runtime.addrIdx

proc markLocal*(runtime: Runtime, fn: Function, ident: string) =
  var toRm: seq[int]
  for i, value in runtime.values:
    if value.kind == vkLocal and value.ownerFunc == hash(fn) and
        value.identifier == ident:
      toRm &= i

  for rm in toRm:
    runtime.values.del(rm)

  runtime.values &=
    Value(kind: vkLocal, index: runtime.addrIdx, identifier: ident, ownerFunc: hash(fn))

  info "Ident \"" & ident & "\" is being locally marked at index " & $runtime.addrIdx

  inc runtime.addrIdx

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

proc createAtom*(typ: JSType): MAtom =
  var atom = obj()

  for name, member in typ.members:
    if member.isAtom():
      let idx = atom.objValues.len
      atom.objValues &= undefined()
      atom.objFields[name] = idx

  atom

proc createObjFromType*[T](runtime: Runtime, typ: typedesc[T]): MAtom =
  for etyp in runtime.types:
    if etyp.proto == hash($typ):
      return etyp.createAtom()

  raise newException(ValueError, "No such registered type: `" & $typ & '`')

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

proc registerType*[T](runtime: Runtime, name: string, prototype: typedesc[T]) =
  var jsType: JSType

  for fname, fatom in prototype().fieldPairs:
    jsType.members[fname] = initAtomOrFunction[NativeFunction](
      fatom.wrap()
    )

  jsType.proto = hash($prototype)
  jsType.name = name

  runtime.types &= jsType.move()
  let typIdx = runtime.types.len - 1

  runtime.vm.registerBuiltin(
    "BALI_CONSTRUCTOR_" & name.toUpperAscii(),
    proc(_: Operation) =
      if runtime.types[typIdx].constructor == nil:
        runtime.vm.typeError(runtime.types[typIdx].name & " is not a constructor")

      runtime.types[typIdx].constructor(),
  )

proc setProperty*[T](
    runtime: Runtime, prototype: typedesc[T], name: string, value: MAtom
) =
  for i, typ in runtime.types:
    if typ.proto == hash($prototype):
      runtime.types[i].members[name] = initAtomOrFunction[NativeFunction](value)

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

func argumentCount*(runtime: Runtime): int {.inline.} =
  ## Get the number of atoms in the `CallArgs` register
  runtime.vm.registers.callArgs.len
