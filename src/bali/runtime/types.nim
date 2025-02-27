## Runtime types

import std/[options, hashes, logging, tables]
import bali/runtime/vm/ir/generator
import bali/runtime/vm/runtime/prelude
import bali/grammar/prelude
import bali/internal/sugar
import bali/runtime/[atom_obj_variant, atom_helpers]

type
  NativeFunction* = proc()
  NativePrototypeFunction* = proc(value: JSValue)

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

  ExperimentOpts* = object

  CodegenOpts* = object
    elideLoops*: bool = true
    loopAllocationEliminator*: bool = true
    aggressivelyFreeRetvals*: bool = true

  InterpreterOpts* = object
    test262*: bool = false
    repl*: bool = false
    dumpBytecode*: bool = false
    insertDebugHooks*: bool = false
      ## Allow some calls from JS-land that expose the engine's internals to it.

    codegen*: CodegenOpts
    experiments*: ExperimentOpts

  JSType* = object
    name*: string
    constructor*: NativeFunction
    members*: Table[string, AtomOrFunction[NativeFunction]]
    prototypeFunctions*: Table[string, NativePrototypeFunction]
      ## Functions inherited by each object that derives from this type
    singletonId*: uint

    proto*: Hash

  IRLabel* = object
    start*, dummy*, ending*: uint

  IRHints* = object
    breaksGeneratedAt*: seq[uint]
    generatedClauses*: seq[string]
      ## FIXME: This is a horrible fix for the double-clause codegen bug!

  RuntimeStats* = object
    atomsAllocated*: uint ## How many atoms have been allocated so far?
    bytecodeSize*: uint ## How many kilobytes is the bytecode?
    breaksGenerated*: uint ## How many breaks did the codegen phase generate?
    vmHasHalted*: bool ## Has execution ended?
    fieldAccesses*: uint ## How many times has a field-access occurred?
    typeofCalls*: uint ## How many times has a typeof call occured?
    clausesGenerated*: uint ## How many clauses did the codegen phase generate?

    numAllocations*, numDeallocations*: uint
      ## How many allocations/deallocations happened during execution?

  Runtime* = ref object
    ast*: AST
    ir*: IRGenerator
    vm*: PulsarInterpreter
    opts*: InterpreterOpts

    irHints*: IRHints
    constantsGenerated*: bool = false

    addrIdx*: uint
    values*: seq[Value]
    clauses*: seq[string]
    test262*: Test262Opts

    statFieldAccesses, statTypeofCalls: uint
    allocStatsStart*: AllocStats

    types*: seq[JSType]
    predefinedBytecode*: string

{.push warning[UnreachableCode]: off.}
proc setExperiment*(opts: var ExperimentOpts, name: string, value: bool): bool =
  case name
  else:
    warn "Unrecognized experiment \"" & name & "\"!"
    return false

  info "Enabling experiment \"" & name & '"'
  true

{.pop.}

proc getMethods*(
    runtime: Runtime, proto: Hash
): Table[string, NativePrototypeFunction] {.inline.} =
  for typ in runtime.types:
    if typ.proto == proto:
      var fns: Table[string, NativeFunction]
      #for name, member in typ.members:
      #  if member.isFn: fns[name] = member.fn()
      return typ.prototypeFunctions

  raise newException(KeyError, "No such type with proto hash: " & $proto & " exists!")

proc defaultParams*(fn: Function): IndexParams {.inline.} =
  IndexParams(fn: some fn)

proc globalIndex*(): IndexParams {.inline.} =
  IndexParams(priorities: @[vkGlobal])

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

proc markGlobal*(runtime: Runtime, ident: string, index: Option[uint] = none(uint)) =
  var toRm: seq[int]
  for i, value in runtime.values:
    if value.kind == vkGlobal and value.identifier == ident:
      toRm &= i

  for rm in toRm:
    runtime.values.del(rm)

  let idx =
    if *index:
      &index
    else:
      runtime.addrIdx

  runtime.values &= Value(kind: vkGlobal, index: idx, identifier: ident)

  info "Ident \"" & ident & "\" is being globally marked at index " & $runtime.addrIdx

  inc runtime.addrIdx

proc markLocal*(
    runtime: Runtime, fn: Function, ident: string, index: Option[uint] = none(uint)
) =
  var toRm: seq[int]
  for i, value in runtime.values:
    if value.kind == vkLocal and value.ownerFunc == hash(fn) and
        value.identifier == ident:
      toRm &= i

  for rm in toRm:
    runtime.values.del(rm)

  let idx =
    if *index:
      &index
    else:
      runtime.addrIdx

  runtime.values &=
    Value(kind: vkLocal, index: idx, identifier: ident, ownerFunc: hash(fn))

  info "Ident \"" & ident & "\" is being locally marked at index " & $runtime.addrIdx

  inc runtime.addrIdx

proc loadIRAtom*(runtime: Runtime, atom: MAtom): uint =
  debug "codegen: loading atom with kind: " & $atom.kind
  case atom.kind
  of Integer:
    runtime.ir.loadInt(runtime.addrIdx, atom)
    return runtime.addrIdx
  of UnsignedInt:
    runtime.ir.loadUint(runtime.addrIdx, atom)
    return runtime.addrIdx
  of String:
    runtime.ir.loadStr(runtime.addrIdx, atom)
    runtime.ir.passArgument(runtime.addrIdx)
    runtime.ir.call("BALI_CONSTRUCTOR_STRING")
    runtime.ir.resetArgs()
    runtime.ir.readRegister(runtime.addrIdx, Register.ReturnValue)
    runtime.ir.zeroRetval()
    return runtime.addrIdx
  of Null:
    runtime.ir.loadNull(runtime.addrIdx)
    return runtime.addrIdx
  of Ident:
    unreachable
  of Boolean:
    runtime.ir.loadBool(runtime.addrIdx, atom)
    return runtime.addrIdx
  of Object:
    if atom.isUndefined():
      runtime.ir.loadObject(runtime.addrIdx)
      return runtime.addrIdx
    else:
      unreachable # FIXME
  of Float:
    runtime.ir.loadFloat(runtime.addrIdx, atom)
    return runtime.addrIdx
  of Sequence:
    runtime.ir.loadList(runtime.addrIdx)
    result = runtime.addrIdx

    for item in atom.sequence:
      inc runtime.addrIdx
      let idx = runtime.loadIRAtom(item)
      runtime.ir.appendList(result, idx)
  of Undefined:
    runtime.ir.loadUndefined(runtime.addrIdx)
    return runtime.addrIdx
  else:
    unreachable

proc index*(runtime: Runtime, ident: string, params: IndexParams): uint =
  for value in runtime.values:
    for prio in params.priorities:
      if value.kind == vkGlobal and value.identifier == ident:
        return value.index

      if value.kind != prio:
        continue

      let cond =
        case value.kind
        of vkGlobal:
          value.identifier == ident
        of vkLocal:
          assert *params.fn
          value.identifier == ident and value.ownerFunc == hash(&params.fn)
        of vkInternal:
          assert *params.stmt
          value.identifier == ident and value.ownerStmt == hash(&params.stmt)

      if cond:
        return value.index

  debug "runtime: cannot find identifier \"" & ident &
    "\" in index search, returning pointer to undefined()"
  runtime.index("undefined", params)
  # raise newException(ValueError, "No such ident: " & ident)
