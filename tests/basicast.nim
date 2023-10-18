import unittest, bali, pretty, std/tables

test "Basic parser converting string to AST + AST interpreter":
  let ast = parse("""
let x = 5;
let y = 8;

if x == y {
  let z = 32;
}

let a = 98;

if x != y {
  let p = 23;
}

let b = 89;
""")
  
  echo "Parsing done; total tokens = " & $ast.tokens.len
  
  let interpreter = newASTInterpreter(ast)
  interpreter.interpret()

  print ast
