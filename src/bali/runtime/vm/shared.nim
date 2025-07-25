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

  Ops* = enum
    ## Call a function.
    ## Arguments:
    ## `name`: Ident -  name of the function or builtin
    ## `...`: Integers - stack indexes as arguments
    Call = 0x00

    ## Load an integer onto the stack
    ## Arguments:
    ## `idx`: Integer - stack index
    ## `value`: Integer - int value
    LoadInt = 0x1

    ## Load a string onto the stack
    ## Arguments:
    ## `idx`: Integer - stack index
    ## `value`: string - str value
    LoadStr = 0x2

    ## Jump to an operation in the current clause
    ## Arguments:
    ## `idx`: Integer - operation ID
    Jump = 0x3

    ## Generic functions for dynamic values where the emitter did not know what types are going to be operated upon.
    ## These are slower than their "targetted-type" counterparts as they need to check for exceptions.
    Add = 0x4
    Mult = 0x5
    Div = 0x6
    Sub = 0x7

    ## Executes the line after this instruction if the condition is true, otherwise the line after that line.
    ## Wherever the line is, execution continues from there on.
    ## Arguments:
    ## `...`: Integer - indexes on the stack
    Equate = 0x8

    ## Do not execute any more lines after this, signifying an end to a clause.
    ## Arguments:
    ## value: Integer - a return value, can be NULL
    Return = 0x9

    ## Load a list
    ## Arguments:
    ## `idx`: the index on which the list is loaded
    LoadList = 0xd

    ## Add an atom to a list
    ## Arguments:
    ## `idx`: the index on which the list is located
    ## `value`: Integer/String/List - any accepted atom
    AddList = 0xe

    ## Load an unsigned integer onto the stack
    LoadUint = 0x14

    ## Load a boolean onto the stack
    LoadBool = 0x15

    ## Swap two indices that hold atoms on the stack
    Swap = 0x16

    ## Jump to an operation in the clause if an error occurs whilst executing a line of code.
    JumpOnError = 0x17

    ## Same as EQU, but compares if `a` is greater than `b`
    GreaterThanInt = 0x18

    ## Same as EQU, but compares if `a` is lesser than `b`
    LesserThanInt = 0x19

    ## Load an object onto the stack
    LoadObject = 0x1a

    ## Create a field in an object
    CreateField = 0x1b

    ## Write an atom into the field of an object without its name, just by its index.
    ## This is faster than finding the field via its name.
    FastWriteField = 0x1c

    ## Write an atom into the field of an object without its name, just by its index.
    ## This is slower than just providing the index.
    WriteField = 0x1d

    ## Crash the interpreter. That's it.
    ## This opcode gets ignored in release mode.
    CrashInterpreter = 0x1e

    ## Increment an integer/unsigned integer atom by one. This just exists to avoid creating ints again and again to use for `LoadInt`
    Increment = 0x1f

    ## Decrement an integer/unsigned integer atom by one. This just exists to avoid creating ints again and again to use for `LoadInt`.
    Decrement = 0x20

    ## Load a null atom onto the stack position provided.
    LoadNull = 0x24

    ## Read a builtin interpreter register and store its value (if there is any) to a specified location. If the register is empty, overwrite the
    ## location to a NULL atom
    ReadRegister = 0x26

    ## Add an atom to the call arguments register.
    PassArgument = 0x27

    ## Reset the call arguments register.
    ResetArgs = 0x28

    ## Copy an atom to another position.
    CopyAtom = 0x29

    ## Move an atom to another position, replacing the source with a NULL atom.
    MoveAtom = 0x2a

    ## Load a float onto a position
    LoadFloat = 0x2b

    ## Zero-out the retval register
    ## Useful for immediately clearing memory if the return value is to be discarded
    ## This opcode is ignored if the retval register is already empty
    ZeroRetval = 0x34

    ## Load a bytecode callable into memory
    ## This just holds a reference to a clause
    LoadBytecodeCallable = 0x35

    ## Execute a bytecode callable
    ExecuteBytecodeCallable = 0x36

    ## Load undefined
    LoadUndefined = 0x37

    ## Greater-or-equal
    GreaterThanEqualInt = 0x38

    ## Lesser-or-equal
    LesserThanEqualInt = 0x39

    ## Generic opcode to invoke either a bytecode callable (reference to clause), clause or builtin.
    Invoke = 0x3a
    Power = 0x3b

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
