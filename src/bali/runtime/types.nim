## Runtime types

import std/[options, hashes, logging, strutils, tables]
import mirage/ir/generator
import mirage/runtime/prelude
import bali/grammar/prelude
import bali/internal/sugar
import bali/runtime/[normalize, atom_obj_variant, atom_helpers]
import pretty

type
  NativeFunction* = proc()
  NativePrototypeFunction* = proc(value: MAtom)

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
  
  ExperimentOpts* = object

  CodegenOpts* = object
    elideLoops*: bool = true
    loopAllocationEliminator*: bool = true
    aggressivelyFreeRetvals*: bool = true

  InterpreterOpts* = object
    test262*: bool = false
    repl*: bool = false
    dumpBytecode*: bool = false
    insertDebugHooks*: bool = false ## Allow some calls from JS-land that expose the engine's internals to it.
    
    codegen*: CodegenOpts
    experiments*: ExperimentOpts

  JSType* = object
    name*: string
    constructor*: NativeFunction
    members*: Table[string, AtomOrFunction[NativeFunction]]
    prototypeFunctions*: Table[string, NativePrototypeFunction] ## Functions inherited by each object that derives from this type
    singletonId*: uint

    proto*: Hash
  
  IRLabel* = object
    start*, dummy*, ending*: uint

  IRHints* = object
    breaksGeneratedAt*: seq[uint]

  Runtime* = ref object
    ast*: AST
    ir*: IRGenerator
    vm*: PulsarInterpreter
    opts*: InterpreterOpts

    irHints*: IRHints
    constantsGenerated*: bool = false

    addrIdx*: uint
    values*: seq[Value]
    semanticErrors*: seq[SemanticError]
    clauses*: seq[string]
    test262*: Test262Opts

    types*: seq[JSType]

proc setExperiment*(opts: var ExperimentOpts, name: string, value: bool): bool =
  case name
  else:
    warn "Unrecognized experiment \"" & name & "\"!"
    return false
  
  info "Enabling experiment \"" & name & '"'
  true

proc unknownIdentifier*(identifier: string): SemanticError {.inline.} =
  SemanticError(kind: UnknownIdentifier, unknown: identifier)

proc getMethods*(runtime: Runtime, proto: Hash): Table[string, NativePrototypeFunction] {.inline.} =
  for typ in runtime.types:
    if typ.proto == proto:
      var fns: Table[string, NativeFunction]
      #for name, member in typ.members:
      #  if member.isFn: fns[name] = member.fn()
      return typ.prototypeFunctions

  raise newException(KeyError, "No such type with proto hash: " & $proto & " exists!")

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

proc markGlobal*(runtime: Runtime, ident: string, index: Option[uint] = none(uint)) =
  var toRm: seq[int]
  for i, value in runtime.values:
    if value.kind == vkGlobal and value.identifier == ident:
      toRm &= i

  for rm in toRm:
    runtime.values.del(rm)

  let idx = if *index: &index else: runtime.addrIdx

  runtime.values &= Value(kind: vkGlobal, index: idx, identifier: ident)

  info "Ident \"" & ident & "\" is being globally marked at index " & $runtime.addrIdx

  inc runtime.addrIdx

proc markLocal*(runtime: Runtime, fn: Function, ident: string, index: Option[uint] = none(uint)) =
  var toRm: seq[int]
  for i, value in runtime.values:
    if value.kind == vkLocal and value.ownerFunc == hash(fn) and
        value.identifier == ident:
      toRm &= i

  for rm in toRm:
    runtime.values.del(rm)

  let idx = if *index: &index else: runtime.addrIdx

  runtime.values &=
    Value(kind: vkLocal, index: idx, identifier: ident, ownerFunc: hash(fn))

  info "Ident \"" & ident & "\" is being locally marked at index " & $runtime.addrIdx

  inc runtime.addrIdx

proc loadIRAtom*(runtime: Runtime, atom: MAtom): uint =
  case atom.kind
  of Integer:
    runtime.ir.loadInt(runtime.addrIdx, atom)
    return runtime.addrIdx
  of UnsignedInt:
    runtime.ir.loadUint(runtime.addrIdx, &atom.getUint())
    return runtime.addrIdx
  of String:
    runtime.ir.loadStr(runtime.addrIdx, atom)
    runtime.ir.passArgument(runtime.addrIdx)
    runtime.ir.call("BALI_CONSTRUCTOR_STRING")
    runtime.ir.resetArgs()
    runtime.ir.readRegister(runtime.addrIdx, Register.ReturnValue)
    return runtime.addrIdx
  of Null:
    runtime.ir.loadNull(runtime.addrIdx)
    return runtime.addrIdx
  of Ident: unreachable
  of Boolean:
    runtime.ir.loadBool(runtime.addrIdx, atom)
    return runtime.addrIdx
  of Object:
    if atom.isUndefined():
      runtime.ir.loadObject(runtime.addrIdx)
      return runtime.addrIdx
    else: unreachable # FIXME
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

proc index*(runtime: Runtime, ident: string, params: IndexParams): uint =
  for value in runtime.values:
    for prio in params.priorities:
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
  
  debug "runtime: cannot find identifier \"" & ident & "\" in index search, returning pointer to undefined()"
  runtime.index("undefined", params)
  # raise newException(ValueError, "No such ident: " & ident)
