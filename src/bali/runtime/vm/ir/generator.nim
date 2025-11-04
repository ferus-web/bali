## IR generation utility. Helps with the manipulation of the IRGenerator state
## which can then be used by the MIR emitter to generate MIR.
##

import bali/runtime/vm/shared
import bali/runtime/vm/[atom]
import bali/runtime/vm/ir/[emitter, shared]
import pkg/shakar

func newModule*(gen: IRGenerator, name: string) {.inline, quirky.} =
  ## Create a new module/function/clause definition. 
  ## The name allotted to this module must be unique.
  gen.cachedModule = nil
  gen.modules.add(CodeModule(name: name, operations: newSeqOfCap[IROperation](8)))
  gen.currModule = name

proc addOp*(gen: IRGenerator, operation: IROperation): uint {.inline, quirky.} =
  ## Add an operation to the current clause's operation list.
  ## You shouldn't have to use this directly.

  if gen.cachedModule == nil:
    for i, _ in gen.modules:
      var module = gen.modules[i]
      if module.name == gen.currModule:
        module.operations &= operation
        gen.modules[i] = module
        gen.cachedIndex = module.operations.len.uint
        gen.cachedModule = gen.modules[i].addr
        return gen.cachedIndex
  else:
    gen.cachedModule.operations &= operation
    gen.cachedIndex = gen.cachedModule.operations.len.uint
    return gen.cachedIndex

  unreachable

{.push quirky.}
proc loadInt*[V: SomeInteger](
    gen: IRGenerator, position: uint, value: V
): uint {.inline, discardable.} =
  ## Load an stackInteger into the memory space.
  ## This is an overloadable function and can be provided any kind of stackInteger type (`int`, `int8`, `int16`, `int32`, `int64` or their unsigned counterparts)
  ##
  ## **See also:**
  ## * `loadInt proc<#loadInt, IRGenerator, uint, MAtom>`
  ## * `loadFloat proc<#loadFloat, IRGenerator, uint, MAtom>`

  gen.addOp(
    IROperation(
      opCode: LoadInt, arguments: @[stackInteger(position), stackInteger value]
    )
  )

proc loadInt*(
    gen: IRGenerator, position: uint, value: MAtom
): uint {.inline, discardable.} =
  ## Load an stackInteger into the memory space.
  ## This is an overloadable function and can be provided a `MAtom` that contains an stackInteger.
  ##
  ## **See also:**
  ## * `loadInt proc<#loadInt, IRGenerator, uint, SomeInteger>`
  ## * `loadFloat proc<#loadFloat, IRGenerator, uint, MAtom>`

  if value.kind != Integer:
    raise newException(
      ValueError, "Attempt to load " & $value.kind & " as an stackInteger."
    )

  gen.addOp(IROperation(opCode: LoadInt, arguments: @[stackInteger position, value]))

proc loadList*(gen: IRGenerator, position: uint): uint {.inline, discardable.} =
  ## Load a list (vector, stackSequence, whatever you like to call it) into memory.
  ## This list initially starts out empty and you can fill it up as you wish.
  ## You can mark this list as homogenous to only allow a single type of atoms to populate it, 
  ## and you can set a cap on this list to prevent its element list from growing beyond what you intend.
  ##
  ## **See also:**
  ## * `appendList proc<#appendList, IRGenerator, uint, uint>`
  ## * `setCap proc<#setCap, IRGenerator, uint, int>`
  gen.addOp(IROperation(opCode: LoadList, arguments: @[stackInteger position]))

proc appendList*(gen: IRGenerator, dest, source: uint): uint {.inline, discardable.} =
  ## Append an atom that has already been loaded into memory onto a list.
  ## This can fail, if:
  ## * the list is marked as homogenous and the atom you are attempting to load does not belong to the inferred type.
  ## * the list has a cap and appending this element will cause an overflow.
  gen.addOp(
    IROperation(opCode: AddList, arguments: @[stackInteger dest, stackInteger source])
  )

proc jump*(gen: IRGenerator, position: uint): uint {.inline, discardable.} =
  ## Jump to an operation index in the current clause. 
  ##
  ## .. warning:: Validate operations: If the operation index specified is beyond the number of operations in the current clause or below the least index (0), the interpreter will assume that the execution of the program has been completed and gracefully exit with no errors or warnings. This can become a nightmare to debug if you aren't keeping track of the operation indices properly.
  ##
  ## **See also:**
  ## * `call proc<#call, IRGenerator, string, seq[MAtom]>`
  gen.addOp(IROperation(opCode: Jump, arguments: @[stackInteger position]))

proc loadStr*(
    gen: IRGenerator, position: uint, value: string | MAtom
): uint {.inline, discardable.} =
  ## Load a string into memory.
  ## This is an overloadable function, and can be provided:
  ## * string type
  ## * `MAtom` that contains a string.
  when value is string:
    gen.addOp(
      IROperation(
        opCode: LoadStr,
        arguments:
          @[
            stackInteger position,
            when value is string:
              stackStr value
            else:
              value,
          ],
      )
    )
  else:
    if value.kind != String:
      raise newException(ValueError, "Attempt to load " & $value.kind & " as a string.")

    gen.addOp(IROperation(opCode: LoadStr, arguments: @[stackInteger position, value]))

proc loadNull*(gen: IRGenerator, position: uint): uint {.inline, discardable.} =
  ## Load a NULL atom into memory.
  gen.addOp(IROperation(opCode: LoadNull, arguments: @[stackInteger position]))

proc readRegister*(
    gen: IRGenerator, position: int | uint, register: Register
): uint {.inline, discardable.} =
  ## Read a scalar register.
  gen.addOp(
    IROperation(
      opCode: ReadRegister,
      arguments: @[stackInteger position.int, stackInteger int(register)],
    )
  )

proc readRegister*(
    gen: IRGenerator, position: uint, index: uint, register: Register
): uint {.inline, discardable.} =
  ## Read a dynamically growing register
  gen.addOp(
    IROperation(
      opCode: ReadRegister,
      arguments:
        @[stackInteger position, stackInteger int(register), stackInteger index],
    )
  )

proc loadUint*[P: SomeInteger](
    gen: IRGenerator, position: uint, value: P
): uint {.inline, discardable.} =
  gen.addOp(
    IROperation(
      opCode: LoadUint,
      arguments: @[stackInteger position.uint, stackInteger value.uint],
    )
  )

proc loadUint*(
    gen: IRGenerator, position: uint | int, value: MAtom
): uint {.inline, discardable.} =
  gen.addOp(
    IROperation(opCode: LoadUint, arguments: @[stackInteger position.uint, value])
  )

proc returnFn*(gen: IRGenerator, position: int = -1): uint {.inline, discardable.} =
  ## Halt the execution of this clause, and optionally return an atom. The returned atom can be retrieved by reading the `CallArgument` register.
  ## .. warning:: Make sure to mark the atom as a global before passing it on!
  gen.addOp(IROperation(opCode: Return, arguments: @[stackInteger position]))

proc loadBool*(
    gen: IRGenerator, position: uint, value: bool | MAtom
): uint {.inline, discardable.} =
  ## Load a boolean into memory.
  ## **This is an overloadable function, and can be provided:**
  ## * a boolean
  ## * a `MAtom` containing a boolean
  when value is bool:
    gen.addOp(
      IROperation(
        opCode: LoadBool, arguments: @[stackInteger position, stackBoolean value]
      )
    )
  else:
    gen.addOp(IROperation(opCode: LoadBool, arguments: @[stackInteger position, value]))

proc call*(
    gen: IRGenerator, function: string, arguments: seq[MAtom] = @[]
): uint {.inline, discardable.} =
  ## Call a function/clause. This halts the current function's execution, enters the other function, executes it and returns back to where it left off.
  ## .. warning:: The `arguments` argument is not meant to be used to pass real arguments! They're used for passing arguments to the `Call` operation.
  ##
  ## **See also:**
  ## * `passArgument proc<#passArgument, IRGenerator, uint>` for actually passing arguments to a function.
  ## * `resetArgs proc<#resetArgs, IRGenerator>` for resetting the list of arguments passed to a function.
  gen.addOp(IROperation(opCode: Call, arguments: @[stackIdent function] & arguments))

proc loadObject*(gen: IRGenerator, position: uint): uint {.inline, discardable.} =
  ## Load an object into memory.
  ## Objects are like hashmaps (or tables). They store key-value pairs.
  ##
  ## **See also:**
  ## * `createField proc<#createField, IRGenerator, uint, int, string>`
  ## * `writeField proc<#writeField, IRGenerator, uint, int, MAtom>`
  ## * `writeField proc<#writeField, IRGenerator, uint, string, MAtom>`
  gen.addOp(IROperation(opCode: LoadObject, arguments: @[stackInteger position]))

proc loadUndefined*(gen: IRGenerator, position: uint): uint {.inline, discardable.} =
  ## Load `undefined` into memory.
  gen.addOp(IROperation(opCode: LoadUndefined, arguments: @[stackInteger position]))

proc createField*(
    gen: IRGenerator, position: uint, index: int, name: string
): uint {.inline, discardable.} =
  ## Create a field in the object with a name and index.
  ## By default, the field will be occupied by a NULL `MAtom`.
  ##
  ## **See also:**
  ## * `writeField proc<#writeField, IRGenerator, uint, int, MAtom>`
  ## * `writeField proc<#writeField, IRGenerator, uint, string, MAtom>`
  gen.addOp(
    IROperation(
      opCode: CreateField,
      arguments: @[stackInteger position, stackInteger index, stackStr name],
    )
  )

# "slow"
proc writeField*(
    gen: IRGenerator, position: uint, name: string, value: uint
): uint {.inline, discardable.} =
  ## Modify a field of an object. 
  ## Keep in mind that this can be slow* as it requires a search in the field name-to-index lookup table.
  ## For a faster alternative (direct index access), use the `writeField proc<#writeField, IRGenerator, uint, int, uint>` instead.
  gen.addOp(
    IROperation(
      opCode: WriteField,
      arguments: @[stackInteger position, stackStr name, stackInteger value],
    )
  )

# "fast"
proc writeField*(
    gen: IRGenerator, position: uint, index: int, value: uint
): uint {.inline, discardable.} =
  ## Modify a field of an object.
  ## This is the faster alternative to `writeField proc<#writeField, IRGenerator, uint, string, uint>`
  gen.addOp(
    IROperation(
      opCode: FastWriteField,
      arguments: @[stackInteger position, stackInteger index, stackInteger value],
    )
  )

proc incrementInt*(gen: IRGenerator, position: uint): uint {.inline, discardable.} =
  ## Increment an stackInteger at the specified position by one.
  gen.addOp(IROperation(opCode: Increment, arguments: @[stackInteger position]))

proc decrementInt*(gen: IRGenerator, position: uint): uint {.inline, discardable.} =
  ## Decrement an stackInteger at the specified position by one.
  gen.addOp(IROperation(opCode: Decrement, arguments: @[stackInteger position]))

proc zeroRetval*(gen: IRGenerator): uint {.inline, discardable.} =
  gen.addOp(IROperation(opCode: ZeroRetval))

proc placeholder*(gen: IRGenerator, opCode: Ops): uint {.inline, discardable.} =
  gen.addOp(IROperation(opCode: opCode))

proc overrideArgs*(
    gen: IRGenerator, instruction: uint, arguments: seq[MAtom]
) {.inline.} =
  for i, _ in gen.modules:
    var module = gen.modules[i]
    if module.name == gen.currModule:
      module.operations[instruction.int].arguments = arguments
      gen.modules[i] = module
      return

  raise newException(FieldDefect, "Cannot find any clause with name: " & gen.currModule)

#[ proc equate*(gen: IRGenerator, a, b: uint): uint {.inline, discardable.} =
  ## Equate two atoms together.
  ## If they match, the operation directly below this conditional is executed. Otherwise, the operation two operations down this conditional is executed.
  gen.addOp(IROperation(opCode: Equate, arguments: @[stackInteger a, stackInteger b]))
]#

proc add*(gen: IRGenerator, dest, source: uint): uint {.inline, discardable.} =
  gen.addOp(
    IROperation(opCode: Add, arguments: @[stackInteger dest, stackInteger source])
  )

proc mult*(gen: IRGenerator, dest, source: uint): uint {.inline, discardable.} =
  gen.addOp(
    IROperation(opCode: Mult, arguments: @[stackInteger dest, stackInteger source])
  )

proc divide*(gen: IRGenerator, dest, source: uint): uint {.inline, discardable.} =
  gen.addOp(
    IROperation(opCode: Div, arguments: @[stackInteger dest, stackInteger source])
  )

proc sub*(gen: IRGenerator, dest, source: uint): uint {.inline, discardable.} =
  gen.addOp(
    IROperation(opCode: Sub, arguments: @[stackInteger dest, stackInteger source])
  )

proc passArgument*(gen: IRGenerator, position: uint): uint {.inline, discardable.} =
  ## Adds an atom index to the call arguments register.
  gen.addOp(IROperation(opCode: PassArgument, arguments: @[stackInteger position]))

proc loadFloat*(
    gen: IRGenerator, position: uint, value: float | MAtom
): uint {.inline, discardable.} =
  ## Load a float into memory.
  ## **This function is overloadable, and can be provided:**
  ## * a floating point value
  ## * a `MAtom` containing a floating point value
  when value is float:
    gen.addOp(
      IROperation(
        opCode: LoadFloat, arguments: @[stackInteger position, floating value]
      )
    )
  else:
    if value.kind != Float:
      raise newException(ValueError, "Attempt to load " & $value.kind & " as float.")

    gen.addOp(
      IROperation(opCode: LoadFloat, arguments: @[stackInteger position, value])
    )

proc moveAtom*(gen: IRGenerator, source, dest: uint): uint {.inline, discardable.} =
  ## Move an atom from one index to another. The source index is replaced with a NULL `MAtom` and 
  ## the destination index occupies what was previously the content stored at the source index.
  gen.addOp(
    IROperation(opCode: MoveAtom, arguments: @[stackInteger source, stackInteger dest])
  )

proc copyAtom*(gen: IRGenerator, source, dest: uint): uint {.inline, discardable.} =
  ## Copy an atom from one index to another.
  gen.addOp(
    IROperation(opCode: CopyAtom, arguments: @[stackInteger source, stackInteger dest])
  )

proc resetArgs*(gen: IRGenerator): uint {.inline, discardable.} =
  ## Reset the call arguments register.
  gen.addOp(IROperation(opCode: ResetArgs))

proc lesserThan*(gen: IRGenerator, a, b: uint): uint {.inline, discardable.} =
  gen.addOp(
    IROperation(opcode: LesserThanInt, arguments: @[stackInteger a, stackInteger b])
  )

proc greaterThan*(gen: IRGenerator, a, b: uint): uint {.inline, discardable.} =
  gen.addOp(
    IROperation(opcode: GreaterThanInt, arguments: @[stackInteger a, stackInteger b])
  )

proc greaterThanEqual*(gen: IRGenerator, a, b: uint): uint {.inline, discardable.} =
  gen.addOp(
    IROperation(
      opcode: GreaterThanEqualInt, arguments: @[stackInteger a, stackInteger b]
    )
  )

proc lesserThanEqual*(gen: IRGenerator, a, b: uint): uint {.inline, discardable.} =
  gen.addOp(
    IROperation(
      opcode: LesserThanEqualInt, arguments: @[stackInteger a, stackInteger b]
    )
  )

proc loadBytecodeCallable*(
    gen: IRGenerator, index: uint, clause: string
): uint {.inline, discardable.} =
  gen.addOp(
    IROperation(
      opcode: LoadBytecodeCallable, arguments: @[stackInteger(index), stackStr(clause)]
    )
  )

proc invoke*(gen: IRGenerator, index: uint): uint {.inline, discardable.} =
  gen.addOp(IROperation(opcode: Invoke, arguments: @[stackInteger(index)]))

proc emit*(gen: IRGenerator): string {.inline.} =
  ## Emit all the IR generated by the IR generation module.
  ## If possible, retrieve pre-generated IR from the MIR cache. Cache hits prevent regeneration of IR, which might be costly*

  gen.emitIR()

proc emit*(gen: IRGenerator, destination: out string) {.inline.} =
  ## Emit all the IR generated by the IR generation module and store it at `destination`.
  destination = gen.emit()

proc emit*(gen: IRGenerator, destination: File) {.inline, sideEffect.} =
  ## Emit all the IR generated by the IR generation module and write it to the file specified.
  destination.write(gen.emit())

func newIRGenerator*(name: string): IRGenerator {.inline.} =
  ## Initialize a new IR generation helper.
  IRGenerator(name: name, modules: newSeq[CodeModule]())

{.pop.}

export shared, Ops
