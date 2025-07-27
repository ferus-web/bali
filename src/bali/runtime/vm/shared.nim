import std/tables

type
  TokenKind* = enum
    tkComment
    tkOperation
    tkQuotedString
    tkInteger
    tkDouble
    tkWhitespace
    tkClause
    tkIdent
    tkEnd

  Token* = object
    case kind*: TokenKind
    of tkComment:
      comment*: string
    of tkQuotedString:
      str*: string
    of tkInteger:
      integer*: int32
      iHasSign*: bool
    of tkOperation:
      op*: string
    of tkDouble:
      double*: float64
      dHasSign*: bool
    of tkWhitespace:
      whitespace*: string
    of tkClause:
      clause*: string
    of tkIdent:
      ident*: string
    of tkEnd:
      endClause*: string

  Ops* {.size: sizeof(uint8).} = enum
    ## Call a function.
    ## Arguments:
    ## `name`: Ident -  name of the function or builtin
    ## `...`: Integers - stack indexes as arguments
    Call

    ## Load an integer onto the stack
    ## Arguments:
    ## `idx`: Integer - stack index
    ## `value`: Integer - int value
    LoadInt

    ## Load a string onto the stack
    ## Arguments:
    ## `idx`: Integer - stack index
    ## `value`: string - str value
    LoadStr

    ## Jump to an operation in the current clause
    ## Arguments:
    ## `idx`: Integer - operation ID
    Jump

    ## Generic functions for dynamic values where the emitter did not know what types are going to be operated upon.
    ## These are slower than their "targetted-type" counterparts as they need to check for exceptions.
    Add
    Mult
    Div
    Sub

    ## Executes the line after this instruction if the condition is true, otherwise the line after that line.
    ## Wherever the line is, execution continues from there on.
    ## Arguments:
    ## `...`: Integer - indexes on the stack
    Equate

    ## Do not execute any more lines after this, signifying an end to a clause.
    ## Arguments:
    ## value: Integer - a return value, can be NULL
    Return

    ## Load a list
    ## Arguments:
    ## `idx`: the index on which the list is loaded
    LoadList

    ## Add an atom to a list
    ## Arguments:
    ## `idx`: the index on which the list is located
    ## `value`: Integer/String/List - any accepted atom
    AddList

    ## Load an unsigned integer onto the stack
    LoadUint

    ## Load a boolean onto the stack
    LoadBool

    ## Swap two indices that hold atoms on the stack
    Swap

    ## Jump to an operation in the clause if an error occurs whilst executing a line of code.
    JumpOnError

    ## Same as EQU, but compares if `a` is greater than `b`
    GreaterThanInt

    ## Same as EQU, but compares if `a` is lesser than `b`
    LesserThanInt

    ## Load an object onto the stack
    LoadObject

    ## Create a field in an object
    CreateField

    ## Write an atom into the field of an object without its name, just by its index.
    ## This is faster than finding the field via its name.
    FastWriteField

    ## Write an atom into the field of an object without its name, just by its index.
    ## This is slower than just providing the index.
    WriteField

    ## Crash the interpreter. That's it.
    ## This opcode gets ignored in release mode.
    CrashInterpreter

    ## Increment an integer/unsigned integer atom by one. This just exists to avoid creating ints again and again to use for `LoadInt`
    Increment

    ## Decrement an integer/unsigned integer atom by one. This just exists to avoid creating ints again and again to use for `LoadInt`.
    Decrement

    ## Load a null atom onto the stack position provided.
    LoadNull

    ## Read a builtin interpreter register and store its value (if there is any) to a specified location. If the register is empty, overwrite the
    ## location to a NULL atom
    ReadRegister

    ## Add an atom to the call arguments register.
    PassArgument

    ## Reset the call arguments register.
    ResetArgs

    ## Copy an atom to another position.
    CopyAtom

    ## Move an atom to another position, replacing the source with a NULL atom.
    MoveAtom

    ## Load a float onto a position
    LoadFloat

    ## Zero-out the retval register
    ## Useful for immediately clearing memory if the return value is to be discarded
    ## This opcode is ignored if the retval register is already empty
    ZeroRetval

    ## Load a bytecode callable into memory
    ## This just holds a reference to a clause
    LoadBytecodeCallable

    ## Execute a bytecode callable
    ExecuteBytecodeCallable

    ## Load undefined
    LoadUndefined

    ## Greater-or-equal
    GreaterThanEqualInt

    ## Lesser-or-equal
    LesserThanEqualInt

    ## Generic opcode to invoke either a bytecode callable (reference to clause), clause or builtin.
    Invoke
    Power

const
  OpCodeToTable* = {
    "CALL": Call,
    "LDI": LoadInt,
    "LDS": LoadStr,
    "LDL": LoadList,
    "JUMP": Jump,
    "RET": Return,
    "ADD": Add,
    "MUL": Mult,
    "DIV": Div,
    "SUB": Sub,
    "EQU": Equate,
    "ADDL": AddList,
    "LDUI": LoadUint,
    "LDB": LoadBool,
    "SWAP": Swap,
    "JMPE": JumpOnError,
    "GTI": GreaterThanInt,
    "LTI": LesserThanInt,
    "LDO": LoadObject,
    "CFLD": CreateField,
    "FWFLD": FastWriteField,
    "WFLD": WriteField,
    "CRASHINTERP": CrashInterpreter,
    "INC": Increment,
    "DEC": Decrement,
    "LDN": LoadNull,
    "RREG": ReadRegister,
    "PARG": PassArgument,
    "RARG": ResetArgs,
    "COPY": CopyAtom,
    "MOV": MoveAtom,
    "LDF": LoadFloat,
    "ZRETV": ZeroRetval,
    "LDBC": LoadBytecodeCallable,
    "EXEBC": ExecuteBytecodeCallable,
    "LDUD": LoadUndefined,
    "GTEI": GreaterThanEqualInt,
    "LTEI": LesserThanEqualInt,
    "INVK": Invoke,
    "POW": Power,
  }.toTable

  OpCodeToString* = static:
    var vals = initTable[Ops, string]()
    for str, operation in OpCodeToTable:
      vals[operation] = str

    vals

{.push checks: off, inline.}
proc toOp*(op: string): Ops {.raises: [ValueError].} =
  when not defined(release):
    if op in OpCodeToTable:
      return OpCodeToTable[op]
    else:
      raise newException(ValueError, "Invalid operation: " & op)
  else:
    OpCodeToTable[op]

proc opToString*(op: Ops): string =
  OpCodeToString[op]
