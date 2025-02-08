import std/[options, strutils]
import mirage/atom

type
  ExceptionTrace* = ref object
    prev*, next*: Option[ExceptionTrace]
    clause*: int
    index*: uint
    exception*: RuntimeException

  RuntimeException* = ref object of RootObj
    operation*: uint
    clause*: string
    message*: string

  WrongType* = ref object of RuntimeException

proc wrongType*(expected, got: MAtomKind): WrongType {.inline, noSideEffect, gcsafe.} =
  WrongType(message: "Expected $1; got $2 instead." % [$expected, $got])
