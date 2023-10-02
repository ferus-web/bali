import unittest, bali, pretty, std/tables

test "Basic parser converting string to AST":
  let ast = parse("""
let x = 5;
let y = 8;

if x == y {
  let z = 32;
}
""")
  
  echo "Parsing done; total tokens = " & $ast.tokens.len
  #[for tok in ast.tokens:
    print tok]#
  
  let interpreter = newASTInterpreter(ast)
  #interpreter.interpret()

  print ast
