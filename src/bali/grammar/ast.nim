import std/[options]
import bali/grammar/[statement, errors]

type
  Test262Negativity* = object
    phase*: string
    `type`*: string

  Test262Opts* = object ## Information inferred from the Test262 YAML metadata
    description*: string
    esid*: string
    features*: seq[string]
    flags*: seq[string]
    negative*: Test262Negativity
    info*: string

  AST* = ref object
    currentScope*: int
    scopes*: seq[Scope]
    errors*: seq[ParseError]

    doNotEvaluate*: bool = false # For Test262
    test262*: Test262Opts

proc `&=`*(ast: AST, scope: Scope) =
  ast.scopes &= scope

proc appendToCurrentScope*(ast: AST, stmt: Statement) =
  ast.scopes[ast.currentScope].stmts &= stmt

proc appendFunctionToCurrentScope*(ast: AST, fn: Function) =
  ast.scopes[ast.currentScope].children &= Scope(fn)

proc `[]`*(ast: AST, name: string): Option[Function] =
  for scope in ast.scopes:
    let fn = cast[Function](scope)
    if fn.name == name:
      return some fn

proc append*(ast: AST, name: string, stmt: Statement) =
  for scope in ast.scopes:
    let fn =
      try:
        Function(scope)
      except ObjectConversionDefect:
        continue

    if fn.name == name:
      fn.stmts &= stmt
      return

  raise newException(ValueError, "No such scope: " & name)

iterator items*(ast: AST): Scope =
  for scope in ast.scopes:
    yield scope

func function*(
    name: string, stmts: seq[Statement], args: seq[string]
): Function {.inline.} =
  Function(name: name, stmts: stmts, arguments: args)

func scope*(stmts: seq[Statement]): Scope {.inline.} =
  Scope(stmts: stmts)

func newAST*(): AST {.inline.} =
  AST(
    scopes:
      @[
        Scope() # top-level scope
      ]
  )
