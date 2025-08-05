## Taken from https://github.com/planety/cached
##
## BSD 3-Clause License
## Copyright (c) 2020, Planety
## All rights reserved.
##
## Redistribution and use in source and binary forms, with or without
## modification, are permitted provided that the following conditions are met:
##
## 1. Redistributions of source code must retain the above copyright notice, this
##   list of conditions and the following disclaimer.
##
## 2. Redistributions in binary form must reproduce the above copyright notice,
##   this list of conditions and the following disclaimer in the documentation
##   and/or other materials provided with the distribution.
##
## 3. Neither the name of the copyright holder nor the names of its
##   contributors may be used to endorse or promote products derived from
##   this software without specific prior written permission.
##
## THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
## AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
## IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
## DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
## FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
## DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
## SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
## CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
## OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
## OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

import tables
import lists
import macros

type
  CachedPolicy* = enum
    LRU
    LFU
    FIFO
    LRUFILE
    LFUFILE

  CachedInfo* = tuple[hits: int, misses: int, maxSize: int]

  KeyPair*[A, B] = tuple[keyPart: A, valuePart: B]

  LFUPair*[A, B] = tuple[keyPart: A, valuePart: B, hits: int]

  CachedKeyPair*[A, B] = DoublyLinkedList[KeyPair[A, B]]
  MapValue*[A, B] = DoublyLinkedNode[KeyPair[A, B]]

type
  LRUCached*[A, B] = object
    map: Table[A, MapValue[A, B]]
    cached: CachedKeyPair[A, B]
    info: CachedInfo

  LFUCached*[A, B] = object
    map: Table[A, MapValue[A, B]]
    cached: Table[int, CachedKeyPair[A, B]]
    info: CachedInfo

proc initLruCached*[A, B](maxSize: Natural = 128): LRUCached[A, B] {.inline.} =
  LRUCached[A, B](
    map: initTable[A, MapValue[A, B]](),
    cached: initDoublyLinkedList[KeyPair[A, B]](),
    info: (hits: 0, misses: 0, maxSize: maxSize),
  )

proc moveToFront*[A, B](x: var LRUCached[A, B], node: MapValue[A, B]) {.inline.} =
  x.cached.remove(node)
  x.cached.prepend(node)

proc get*[A, B](x: var LRUCached[A, B], key: A): B {.inline.} =
  if key in x.map:
    x.info.hits += 1
    let node = x.map[key]
    moveToFront(x, node)
    return node.value.valuePart
  x.info.misses += 1

proc put*[A, B](x: var LRUCached[A, B], key: A, value: B) {.inline.} =
  if key in x.map:
    x.info.hits += 1
    var node = x.map[key]
    node.value.valuePart = value
    moveToFront(x, node)
    return
  x.info.misses += 1
  if x.map.len >= x.info.maxSize:
    let node = x.cached.tail
    x.cached.remove(node)
    x.map.del(node.value.keyPart)
  let node = newDoublyLinkedNode((keyPart: key, valuePart: value))
  x.map[key] = node
  moveToFront(x, node)

proc `[]`*[A, B](x: var LRUCached[A, B], key: A): B {.inline.} =
  x.get(key)

proc `[]=`*[A, B](x: var LRUCached[A, B], key: A, value: B) {.inline.} =
  x.put(key, value)

proc contains*[A, B](x: var LRUCached[A, B], key: A): bool =
  if key in x.map:
    return true
  else:
    return false

macro cached(x: untyped): untyped =
  for i in 0 ..< x.len:
    expectKind x[i], nnkProcDef

  result = newStmtList()

  # maybe many function defs
  for i in 0 ..< x.len:
    # get information from origin function
    let
      funcStmt = x[i] # function statement
      funcName = funcStmt[0] # function name
      funcRewriting = funcStmt[1] # for template or macro, should be nnkEmpty
      funcGenericParams = funcStmt[2] # generic params
      funcFormalParams = funcStmt[3] # formal params
      returnParams = funcFormalParams[0] # return types
      funcPragma = funcStmt[4] # function paragma
      funcReversed = funcStmt[5]
        # reserved slot for future use, should be nnkEmpty
        # funcBody = funcStmt[6]

    let mainBody = newStmtList()
    # var key: Hash
    mainBody.add newNimNode(nnkVarSection).add(newIdentDefs(ident"key", ident"Hash"))

    # store func params names
    var funcParamsNames: seq[NimNode]
    for i in 1 ..< funcFormalParams.len:
      funcParamsNames.add funcFormalParams[i][0]
      # key = hash(key) !& hash(funcFormalParams[i][0])
      mainBody.add newAssignment(
        ident"key",
        infix(
          newCall("hash", ident"key"), "!&", newCall("hash", funcFormalParams[i][0])
        ),
      )

    # key = !$ key
    mainBody.add newAssignment(ident"key", prefix(ident"key", "!$"))
    # if key in table:
    #   return table[key]
    mainBody.add newIfStmt(
      (
        infix(ident"key", "in", ident"table"),
        newStmtList(
          # newCall(ident"echo"), newStrLitNode(
          #   "I\'m cached")),
          newNimNode(nnkReturnStmt).add(
            newNimNode(nnkBracketExpr).add(ident"table", ident"key")
          )
        ),
      )
    )

    # add origin function definitions
    mainBody.add funcStmt
    # result = funcName()
    mainBody.add newAssignment(ident"result", newCall(funcName, funcParamsNames))
    # table[key] = result
    mainBody.add newAssignment(
      newNimNode(nnkBracketExpr).add(ident"table", ident"key"), ident"result"
    )

    var name = strVal(funcName)
    name.add "_cached"
    name.add "_xzs"
    let wrapperNameNode = ident("wrapper" & name)

    let nameNode = ident(name)
    let main = newNimNode(nnkProcDef).add(
        wrapperNameNode, funcRewriting, funcGenericParams, funcFormalParams, funcPragma,
        funcReversed, mainBody,
      )

    let body = newStmtList()
    body.add newVarStmt(
      ident"table",
      newCall(
        newNimNode(nnkBracketExpr).add(ident"initLruCached", ident"Hash", returnParams)
      ),
    )
    body.add main
    body.add wrapperNameNode

    let templateBody = newNimNode(nnkTemplateDef).add(
        nameNode,
        newEmptyNode(),
        newEmptyNode(),
        newNimNode(nnkFormalParams).add(ident"untyped"),
        newEmptyNode(),
        newEmptyNode(),
        body,
      )

    result.add templateBody
    # let funcName {.inject.} = nameNode
    result.add newLetStmt(
      newNimNode(nnkPragmaExpr).add(funcName, newNimNode(nnkPragma).add(ident"inject")),
      newCall(nameNode),
    )

when isMainModule:
  import os, random, timeit

  randomize(128)

  cached:
    proc hello(a: int): string =
      sleep(20)
      $a

    proc play(b: string): string =
      $b

  # must export manually
  # let funcName {.inject.} = nameNode
  # TODO According to function, export funcName
  export hello
  export play

  proc helloWithoutCache(a: int): string =
    sleep(20)
    $a

  timeOnce("cached"):
    for i in 1 .. 100:
      discard hello(rand(10))

  timeOnce("without cached"):
    for i in 1 .. 100:
      discard helloWithoutCache(rand(10))
