#[
  AST parser
]#

import std/sugar, token, jsvalue

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
    ast = AST(
      tokens: @[],
      src: src,
      pos: -1
    )

  while not ?ast:
    case ++ast:
      of {'a'..'z'}, {'1'..'9'}, '=':
        let name = ~ast & consume(
          ast,
          (c: char) => c != ' '
        )
        if prev == nil:
          if name in ["let", "var", "const"]:
            prev = Token(
              kind: tkDeclaration,
              mutable: name == "var"
            )
            ast.tokens.add(prev)
          else:
            prev = Token(
              kind: tkKeyword,
              keyword: name
            )
            ast.tokens.add(prev)
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
            #echo "comparison pointer left"
            consumeWhitespace(ast)
            
            #echo "KEYWOOOORDS"
            #echo prev.keyword
            if prev.keyword == "if":
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
            consumeWhitespace(ast)

            echo ++ast
      else:
        discard
        # echo "oops: " & -ast

  ast
