#[
  AST parser
]#

import std/[tables, options, sugar], token, jsvalue, logging, pretty

type AST* = ref object of RootObj
  tokens*: seq[Token]
  src: string
  pos: int

proc `?`*(ast: AST): bool {.inline.} =
  ast.pos + 1 >= ast.src.len

proc `--`*(ast: AST): char {.inline.}  =
  dec ast.pos
  ast.src[ast.pos]

proc `~`*(ast: AST): char {.inline.} =
  ast.src[ast.pos]

proc back*(ast: AST): char {.inline.} =
  ast.src[ast.pos-1]

proc `++`*(ast: AST): char {.inline.} =
  inc ast.pos
  ast.src[ast.pos]

proc peek*(ast: AST): char {.inline.} =
  # echo "pos: " & $ast.pos
  ast.src[ast.pos+1]

proc consume*(
  ast: AST,
  conditional: proc(c: char): bool
): string =
  var str: string

  while not ?ast and conditional(peek(ast)):
    str &= ++ast

  str

proc swap*(parent, child: Token) {.inline.} =
  assert parent != nil
  assert child != nil

  parent.next = child
  child.prev = parent

proc consumeWhitespace*(
  ast: AST
) =
  discard consume(
    ast,
    (c: char) => c == ' '
  )

proc parse*(src: string): AST =
  var
    prev: Token
    scope: Token
    ast = AST(
      tokens: @[scope],
      src: src,
      pos: -1
    )
  
  while not ?ast:
    if peek(ast) == '}':
      assert scope != nil
      info "Closed scope, exiting to next closest scope!"
      let newScope = scope.traverseUntilParentFound(tkScope)

      if newScope.isSome:
        scope = newScope.get()
      else:
        scope.reset()

    case ++ast:
      of {'a'..'z'}, {'1'..'9'}, '=':
        let name = ~ast & consume(
          ast,
          (c: char) => c != ' '
        )
        if prev == nil:
          if name in ["let", "var", "const"]:
            var prevD = Token(
              kind: tkDeclaration,
              mutable: name == "var"
            )

            if scope != nil:
              info "scope != nil, adding to scope tokens list"
              scope.tokens.add(prevD)
            else:
              info "scope == nil, adding to root ast tokens list"
              ast.tokens.add(prevD)
            prev = prevD
          else:
            var prevK = Token(
              kind: tkKeyword,
              keyword: name
            )
            
            if scope != nil:
              info "scope != nil, adding to scope tokens list"
              scope.tokens.add(prevK)
            else:
              info "scope == nil, adding to root ast tokens list"
              ast.tokens.add(prevK)
            prev = prevK
        else:
          ast.pos -= name.len
          if prev.kind == tkDeclaration:
            consumeWhitespace(ast)
            let name = consume(
                ast,
                (c: char) => c != ' '
              )
            
            var ident = Token(
                kind: tkIdentifier,
                name: name
              )
            
            swap(prev, ident)
            prev = ident
          elif prev.kind == tkIdentifier:
            consumeWhitespace(ast)
            assert ++ast == '='
          
            var assignOp = Token(
              kind: tkAssignment
            )
            swap(prev, assignOp)
            prev = assignOp
          elif prev.kind == tkKeyword:
            consumeWhitespace(ast)
            if prev.keyword == "if":
              info "if-clause beginning!"
              var pointerOp = Token(
                kind: tkComparisonPointerLeft,
                pName: name
              )
              swap(prev, pointerOp)
              prev = pointerOp
          elif prev.kind == tkComparisonPointerLeft:
            consumeWhitespace(ast)
            var consumeForwards = 0 # prev.pName.len

            while consumeForwards < prev.pName.len:
              discard ++ast
              inc consumeForwards

            consumeWhitespace(ast)
            let sign = consume(
              ast,
              (c: char) => c != ' '
            )
            var cType: ComparisonType
            
            if sign == "==":
              cType = ctEquality
            elif sign == "!=":
              cType = ctNotEquality
            elif sign == "===":
              cType = ctTrueEquality
            elif sign == "!==":
              cType = ctNotTrueEquality

            var comparisonOp = Token(
              kind: tkComparison,
              comparisonType: cType
            )
            swap(prev, comparisonOp)
            prev = comparisonOp
          elif prev.kind == tkComparison:
            let ptrName = consume(
              ast,
              (c: char) => c != '{' and c notin ['\n', '\t', ' ', '\0']
            )
            var pointerOp = Token(
              kind: tkComparisonPointerRight,
              pName: ptrName
            )
            swap(prev, pointerOp)
            prev = pointerOp

            # FIXME: this is absolutely stupid even though I'm the one who wrote this.
            discard --ast
          elif prev.kind == tkAssignment:
            consumeWhitespace(ast)
 
            let
              value = consume(
                ast,
                (c: char) => c != ';'
              )
            var literal = Token(
                kind: tkLiteral,
                value: JSValue(
                  #kind: jskStr,
                  payload: value
                )
              )
            
            swap(prev, literal)
            prev.reset()
          elif prev.kind == tkComparisonPointerRight:
            # then we do this atrocity here. WTF?
            discard ++ast
            consumeWhitespace(ast)
            
            if ++ast == '{':
              info "Opened scope!"
              var scopeOp = Token(
                kind: tkScope,
                tokens: @[]
              )

              swap(prev, scopeOp)
              scopeOp.next = prev
              scope = scopeOp
              prev.reset()
      else:
        discard
        # echo "oops: " & -ast
  ast
