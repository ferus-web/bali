import unittest

import bali, pretty

test "basic tokens":
  # A simple statement
  #
  # let x = 4;

  let 
    decl = Token(
      kind: tkDeclaration,
      mutable: false         # let and const are immutable, var is mutable
    )
    ident = Token(
      kind: tkIdentifier,
      name: "x"
    )
    assignOp = Token(
      kind: tkAssignment
    )
    lit = Token(
      kind: tkLiteral,
      value: JSValue(
        kind: jskInt,
        payload: "4"
      )
    )

  # Throw everything together
  # decl is the parent of ident, which is the parent of assignOp, which is the parent of lit

  decl.next = ident
  ident.prev = decl
  ident.next = assignOp
  assignOp.prev = ident
  assignOp.next = ident
  lit.prev = assignOp
  
  # Make sure everything's alright with a sanity check
  
  for tok in @[decl, ident, assignOp, lit]:
    tok.sanityCheck()
  
  # Print a fancy tree
  print decl

  # Get a declaration's value
  let dVal = decl.getValue()
  let x = dVal.getInt()
  echo "x = " & $x
