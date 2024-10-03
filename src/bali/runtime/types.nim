## Runtime types
## Copyright (C) 2024 Trayambak Rai and Ferus Authors
import std/[options, hashes, logging]
import mirage/ir/generator
import mirage/runtime/prelude
import bali/grammar/prelude

type
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
    line*, col*: uint
    case kind*: SemanticErrorKind
    of UnknownIdentifier:
      unknown*: string
    of ImmutableReassignment:
      imIdent*: string
      imNewValue*: MAtom

  InterpreterOpts* = object
    test262*: bool = false

  Runtime* = ref object
    ast*: AST
    ir*: IRGenerator
    vm*: PulsarInterpreter
    opts*: InterpreterOpts

    addrIdx*: uint
    values*: seq[Value]
    semanticErrors*: seq[SemanticError]
    clauses*: seq[string]

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
  runtime.values &=
    Value(
      kind: vkInternal, index: runtime.addrIdx, identifier: ident, ownerStmt: hash(stmt)
    )

  info "Ident \"" & ident & "\" is being internally marked at index " & $runtime.addrIdx &
    " with statement hash: " & $hash(stmt)

  inc runtime.addrIdx

proc markGlobal*(runtime: Runtime, ident: string) =
  runtime.values &= Value(kind: vkGlobal, index: runtime.addrIdx, identifier: ident)

  info "Ident \"" & ident & "\" is being globally marked at index " & $runtime.addrIdx

  inc runtime.addrIdx
