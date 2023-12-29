import std/marshal, jsvalue

const
  BYTECODE_OP_SEP = '\32'
  BYTECODE_SEP_MAGIC = '\200'

  EXPECTS_ADDRESS = '\170'

proc normalizeIfMagic*(magic: char): char {.inline.} =
  if magic in [BYTECODE_OP_SEP, BYTECODE_SEP_MAGIC, EXPECTS_ADDRESS]:
    return ' '

  magic

type
  InstructionKind* = enum
    # Variables
    SetVar
    GetVar
    
    # Constants
    SetConst
    GetConst
    
    # Math operations
    Add
    Mul
    Div
    Sub

    # Bitwise ops
    And
    Or
    Xor
    Equal
    NEqual
    Greater
    Lesser

    # Control flow
    While
    If
    For
    Continue
    Break

  Instruction* = object
    case kind*: InstructionKind
    of GetVar:
      gVarName*: string
    of SetVar:
      sVarName*: string
      sVarValue*: JSValue
    of SetConst:
      sConstName*: string
      sConstValue*: JSValue
    of GetConst:
      gConstName*: string
    of Add, Mul, Sub, Div, And, Or, Xor, Equal, NEqual, Greater, Lesser:
      opLhsAddr*, opRhsAddr*: string
    else: discard

# Only for operations
proc `$`*(ik: InstructionKind): string =
  case ik
  of Add:
    result = "Add"
  of Mul:
    result = "Mul"
  of Sub:
    result = "Sub"
  of Div:
    result = "Div"
  of And:
    result = "And"
  of Xor:
    result = "Xor"
  of Or:
    result = "Or"
  of Equal:
    result = "Equate"
  of NEqual:
    result = "NEquate"
  of Greater:
    result = "Greater"
  of Lesser:
    result = "Lesser"
  else: discard

proc `$`*(instruction: Instruction): string =
  case instruction.kind
  of GetVar:
    result = "GetMut" & BYTECODE_OP_SEP & instruction.gVarName
  of SetVar:
    result = "SetMut" & BYTECODE_OP_SEP & instruction.sVarName & BYTECODE_SEP_MAGIC & $instruction.sVarValue & BYTECODE_SEP_MAGIC & EXPECTS_ADDRESS
  of SetConst:
    result = "SetConst" & BYTECODE_OP_SEP & instruction.sConstName & BYTECODE_SEP_MAGIC & $instruction.sConstValue & BYTECODE_SEP_MAGIC & EXPECTS_ADDRESS
  of GetConst:
    result = "GetConst" & BYTECODE_OP_SEP & instruction.gConstName & BYTECODE_SEP_MAGIC & EXPECTS_ADDRESS
  else:
    result = ""

proc magicToInstruction*(magic: string): Instruction =
  var
    pos: int
    curr: char

    instName: string
  
  # Get the instruction name.
  while pos < magic.len:
    curr = magic[pos]
    
    if curr != BYTECODE_OP_SEP:
      instName &= curr
    else:
      inc pos
      break
    
    inc pos
