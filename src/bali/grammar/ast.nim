import std/[options]
import bali/internal/sugar
import pretty
import ./[statement, scopes]

type
  AST* = ref object
    currentScope*: int
    scopes*: seq[Scope]

proc `&=`*(ast: AST, scope: Scope) =
  ast.scopes &= scope

proc appendToCurrentScope*(ast: AST, stmt: Statement) =
  ast.scopes[ast.currentScope].stmts &= stmt

proc appendFunctionToCurrentScope*(ast: AST, fn: Function) =
  ast.scopes[ast.currentScope].next = some(cast[Scope](fn))

proc `[]`*(ast: AST, name: string): Option[Function] =
  for scope in ast.scopes:
    let fn = cast[Function](scope)
    if fn.name == name:
      return some fn

proc append*(ast: AST, name: string, stmt: Statement) =
  for scope in ast.scopes:
    var fn = cast[Function](scope)
    if fn.name == name:
      fn.stmts &= stmt
      return
  
  raise newException(ValueError, "No such scope: " & name)

iterator items*(ast: AST): Scope =
  for scope in ast.scopes:
    yield scope

func function*(name: string, stmts: seq[Statement], args: seq[string]): Function {.inline.} =
  print args
  Function(
    name: name,
    stmts: stmts,
    arguments: args
  )

proc newAST*: AST {.inline.} =
  AST(
    scopes: @[
      Scope() # top-level scope
    ]
  )
