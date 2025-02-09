## IR generation utility. Helps with the manipulation of the IRGenerator state
## which can then be used by the MIR emitter to generate MIR.
##

import ../runtime/shared, ../[atom, utils]
import ./[emitter, shared, caching]

proc newModule*(gen: IRGenerator, name: string) {.inline.} =
  ## Create a new module/function/clause definition. 
  ## The name allotted to this module must be unique.
  when not defined(danger):
    for i, module in gen.modules:
      if module.name == name:
        raise newException(
          ValueError,
          "Attempt to create duplicate module \"" & name &
            "\"; already exists at position " & $i,
        )

  gen.modules.add(CodeModule(name: name, operations: newSeq[IROperation]()))
  gen.currModule = name

proc addOp*(gen: IRGenerator, operation: IROperation): uint {.inline.} =
  ## Add an operation to the current clause's operation list.
  ## You shouldn't have to use this directly.
  for i, _ in gen.modules:
    var module = gen.modules[i]
    if module.name == gen.currModule:
      module.operations &= operation
      gen.modules[i] = module
      return module.operations.len.uint

  raise newException(FieldDefect, "Cannot find any clause with name: " & gen.currModule)

proc loadInt*[V: SomeInteger](
    gen: IRGenerator, position: uint, value: V
): uint {.inline, discardable.} =
  ## Load an integer into the memory space.
  ## This is an overloadable function and can be provided any kind of integer type (`int`, `int8`, `int16`, `int32`, `int64` or their unsigned counterparts)
  ##
  ## **See also:**
  ## * `loadInt proc<#loadInt, IRGenerator, uint, MAtom>`
  ## * `loadFloat proc<#loadFloat, IRGenerator, uint, MAtom>`

  gen.addOp(
    IROperation(opCode: LoadInt, arguments: @[uinteger position, integer value])
  )

proc loadInt*(
    gen: IRGenerator, position: uint, value: MAtom
): uint {.inline, discardable.} =
  ## Load an integer into the memory space.
  ## This is an overloadable function and can be provided a `MAtom` that contains an integer.
  ##
  ## **See also:**
  ## * `loadInt proc<#loadInt, IRGenerator, uint, SomeInteger>`
  ## * `loadFloat proc<#loadFloat, IRGenerator, uint, MAtom>`

  if value.kind != Integer:
    raise newException(ValueError, "Attempt to load " & $value.kind & " as an integer.")

  gen.addOp(IROperation(opCode: LoadInt, arguments: @[uinteger position, value]))

proc loadList*(gen: IRGenerator, position: uint): uint {.inline, discardable.} =
  ## Load a list (vector, sequence, whatever you like to call it) into memory.
  ## This list initially starts out empty and you can fill it up as you wish.
  ## You can mark this list as homogenous to only allow a single type of atoms to populate it, 
  ## and you can set a cap on this list to prevent its element list from growing beyond what you intend.
  ##
  ## **See also:**
  ## * `appendList proc<#appendList, IRGenerator, uint, uint>`
  ## * `markHomogenous proc<#markHomogenous, IRGenerator, uint>`
  ## * `setCap proc<#setCap, IRGenerator, uint, int>`
  gen.addOp(IROperation(opCode: LoadList, arguments: @[uinteger position]))

proc appendList*(gen: IRGenerator, dest, source: uint): uint {.inline, discardable.} =
  ## Append an atom that has already been loaded into memory onto a list.
  ## This can fail, if:
  ## * the list is marked as homogenous and the atom you are attempting to load does not belong to the inferred type.
  ## * the list has a cap and appending this element will cause an overflow.
  gen.addOp(IROperation(opCode: AddList, arguments: @[uinteger dest, uinteger source]))

proc jump*(gen: IRGenerator, position: uint): uint {.inline, discardable.} =
  ## Jump to an operation index in the current clause. 
  ##
  ## .. warning:: Validate operations: If the operation index specified is beyond the number of operations in the current clause or below the least index (0), the interpreter will assume that the execution of the program has been completed and gracefully exit with no errors or warnings. This can become a nightmare to debug if you aren't keeping track of the operation indices properly.
  ##
  ## **See also:**
  ## * `call proc<#call, IRGenerator, string, seq[MAtom]>`
  gen.addOp(IROperation(opCode: Jump, arguments: @[uinteger position]))

proc loadStr*(
    gen: IRGenerator, position: uint, value: string | MAtom
): uint {.inline, discardable.} =
  ## Load a string into memory.
  ## This is an overloadable function, and can be provided:
  ## * string type
  ## * `MAtom` that contains a string.
  when value is string:
    gen.addOp(IROperation(opCode: LoadStr, arguments: @[uinteger position, str value]))
  else:
    if value.kind != String:
      raise newException(ValueError, "Attempt to load " & $value.kind & " as a string.")

    gen.addOp(IROperation(opCode: LoadStr, arguments: @[uinteger position, value]))

proc loadNull*(gen: IRGenerator, position: uint): uint {.inline, discardable.} =
  ## Load a NULL atom into memory.
  gen.addOp(IROperation(opCode: LoadNull, arguments: @[uinteger position]))

proc markGlobal*(gen: IRGenerator, position: uint): uint {.inline, discardable.} =
  ## Mark an atom at a particular position as global, i.e it can be accessed by any other clause, matterless of whichever clause created it.
  gen.addOp(IROperation(opCode: MarkGlobal, arguments: @[uinteger position]))

proc readRegister*(
    gen: IRGenerator, position: uint, register: Register
): uint {.inline, discardable.} =
  ## Read a register (what the interpreter uses to hold data that is shared across clauses).
  gen.addOp(
    IROperation(
      opCode: ReadRegister, arguments: @[uinteger position, integer int(register)]
    )
  )

proc readRegister*(
    gen: IRGenerator, position: uint, index: uint, register: Register
): uint {.inline, discardable.} =
  ## Read a dynamically growing register
  gen.addOp(
    IROperation(
      opCode: ReadRegister,
      arguments: @[uinteger position, uinteger index, integer int(register)],
    )
  )

proc loadUint*[P: SomeUnsignedInt](
    gen: IRGenerator, position, value: P
): uint {.inline, discardable.} =
  gen.addOp(
    IROperation(opCode: LoadUint, arguments: @[uinteger position, uinteger value])
  )

proc returnFn*(gen: IRGenerator, position: int = -1): uint {.inline, discardable.} =
  ## Halt the execution of this clause, and optionally return an atom. The returned atom can be retrieved by reading the `CallArgument` register.
  ## .. warning:: Make sure to mark the atom as a global before passing it on!
  gen.addOp(IROperation(opCode: Return, arguments: @[integer position]))

proc loadBool*(
    gen: IRGenerator, position: uint, value: bool | MAtom
): uint {.inline, discardable.} =
  ## Load a boolean into memory.
  ## **This is an overloadable function, and can be provided:**
  ## * a boolean
  ## * a `MAtom` containing a boolean
  when value is bool:
    gen.addOp(
      IROperation(opCode: LoadBool, arguments: @[uinteger position, boolean value])
    )
  else:
    gen.addOp(IROperation(opCode: LoadBool, arguments: @[uinteger position, value]))

proc castStr*(gen: IRGenerator, src, dest: uint): uint {.inline, discardable.} =
  ## Cast an atom in memory into a string.
  ## This simply calls the `toString` function on the atom and stores the result in its position.
  gen.addOp(IROperation(opCode: CastStr, arguments: @[uinteger src, uinteger dest]))

proc castInt*(gen: IRGenerator, src, dest: uint): uint {.inline, discardable.} =
  ## Cast an atom in memory into an integer.
  ## This simply calls the `toInt` function on the atom, causing the following conversions:
  ## * String -> Contents are parsed and stored as integer. If parsing fails, zero is saved in its position instead.
  ## * List -> The list's length is stored as an integer.
  ## * Null -> Zero is stored
  ## * Bool -> The boolean is converted to true (1) or false (0)
  ## * Object -> Not converted at all as there is no good or non-nonsensical way to do this. Zero is stored.
  gen.addOp(IROperation(opCode: CastInt, arguments: @[uinteger src, uinteger dest]))

proc call*(
    gen: IRGenerator, function: string, arguments: seq[MAtom] = @[]
): uint {.inline, discardable.} =
  ## Call a function/clause. This halts the current function's execution, enters the other function, executes it and returns back to where it left off.
  ## .. warning:: The `arguments` argument is not meant to be used to pass real arguments! They're used for passing arguments to the `Call` operation.
  ##
  ## **See also:**
  ## * `passArgument proc<#passArgument, IRGenerator, uint>` for actually passing arguments to a function.
  ## * `resetArgs proc<#resetArgs, IRGenerator>` for resetting the list of arguments passed to a function.
  gen.addOp(IROperation(opCode: Call, arguments: @[ident function] & arguments))

proc loadObject*(gen: IRGenerator, position: uint): uint {.inline, discardable.} =
  ## Load an object into memory.
  ## Objects are like hashmaps (or tables). They store key-value pairs.
  ##
  ## **See also:**
  ## * `createField proc<#createField, IRGenerator, uint, int, string>`
  ## * `writeField proc<#writeField, IRGenerator, uint, int, MAtom>`
  ## * `writeField proc<#writeField, IRGenerator, uint, string, MAtom>`
  gen.addOp(IROperation(opCode: LoadObject, arguments: @[uinteger position]))

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
      opCode: CreateField, arguments: @[uinteger position, integer index, str name]
    )
  )

# "slow"
proc writeField*(
    gen: IRGenerator, position: uint, name: string, value: MAtom
): uint {.inline, discardable.} =
  ## Modify a field of an object. 
  ## Keep in mind that this can be slow* as it requires a search in the field name-to-index lookup table.
  ## For a faster alternative (direct index access), use the `writeField proc<#writeField, IRGenerator, uint, int, MAtom>` instead.
  gen.addOp(
    IROperation(opCode: WriteField, arguments: @[uinteger position, str name, value])
  )

# "fast"
proc writeField*(
    gen: IRGenerator, position: uint, index: int, value: MAtom
): uint {.inline, discardable.} =
  ## Modify a field of an object.
  ## This is the faster alternative to `writeField proc<#writeField, IRGenerator, uint, string, MAtom>`
  gen.addOp(
    IROperation(
      opCode: FastWriteField, arguments: @[uinteger position, integer index, value]
    )
  )

proc incrementInt*(gen: IRGenerator, position: uint): uint {.inline, discardable.} =
  ## Increment an integer at the specified position by one.
  gen.addOp(IROperation(opCode: Increment, arguments: @[uinteger position]))

proc decrementInt*(gen: IRGenerator, position: uint): uint {.inline, discardable.} =
  ## Decrement an integer at the specified position by one.
  gen.addOp(IROperation(opCode: Decrement, arguments: @[uinteger position]))

proc addFloat*(gen: IRGenerator, a, b: uint): uint {.inline, discardable.} =
  ## Add two floats together
  gen.addOp(IROperation(opCode: AddFloat, arguments: @[uinteger a, uinteger b]))

proc subFloat*(gen: IRGenerator, a, b: uint): uint {.inline, discardable.} =
  gen.addOp(IROperation(opCode: SubFloat, arguments: @[uinteger a, uinteger b]))

proc multFloat*(gen: IRGenerator, a, b: uint): uint {.inline, discardable.} =
  gen.addOp(IROperation(opCode: MultFloat, arguments: @[uinteger a, uinteger b]))

proc divFloat*(gen: IRGenerator, a, b: uint): uint {.inline, discardable.} =
  gen.addOp(IROperation(opCode: DivFloat, arguments: @[uinteger a, uinteger b]))

proc powerFloat*(gen: IRGenerator, a, b: uint): uint {.inline, discardable.} =
  gen.addOp(IROperation(opCode: PowerFloat, arguments: @[uinteger a, uinteger b]))

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

proc equate*(gen: IRGenerator, a, b: uint): uint {.inline, discardable.} =
  ## Equate two atoms together.
  ## If they match, the operation directly below this conditional is executed. Otherwise, the operation two operations down this conditional is executed.
  gen.addOp(IROperation(opCode: Equate, arguments: @[uinteger a, uinteger b]))

proc addInt*(
    gen: IRGenerator, destination, source: uint
): uint {.inline, discardable.} =
  ## Add two integers together.
  gen.addOp(
    IROperation(opCode: AddInt, arguments: @[uinteger destination, uinteger source])
  )

proc multInt*(
    gen: IRGenerator, destination, source: uint
): uint {.inline, discardable.} =
  ## Multiply two integers together.
  gen.addOp(
    IROperation(opCode: MultInt, arguments: @[uinteger destination, uinteger source])
  )

proc divInt*(
    gen: IRGenerator, destination, source: uint
): uint {.inline, discardable.} =
  ## Divide two integers together.
  gen.addOp(
    IROperation(opCode: DivInt, arguments: @[uinteger destination, uinteger source])
  )

proc powerInt*(
    gen: IRGenerator, destination, source: uint
): uint {.inline, discardable.} =
  ## Exponentiate an integer
  gen.addOp(
    IROperation(opCode: PowerInt, arguments: @[uinteger destination, uinteger source])
  )

proc subInt*(
    gen: IRGenerator, destination, source: uint
): uint {.inline, discardable.} =
  ## Subtract an integer from another.
  gen.addOp(
    IROperation(opCode: SubInt, arguments: @[uinteger destination, uinteger source])
  )

proc mult2xBatch*(
    gen: IRGenerator, vec1, vec2: array[2, uint], # pos to vector
): uint {.inline, discardable.} =
  ## Multiply a 2x batch of integers together. On most modern CPUs, this would be SIMD accelerated unless Mirage was compiled with SIMD support disabled.
  gen.addOp(
    IROperation(
      opCode: Mult2xBatch,
      arguments:
        @[uinteger vec1[0], uinteger vec1[1], uinteger vec2[0], uinteger vec2[1]],
    )
  )

proc setCap*(gen: IRGenerator, source: uint, cap: int): uint {.inline, discardable.} =
  ## Set a cap on a list. This prevents more than `cap` number of elements from being added ot it.
  ## .. warning:: This does not perform the overflow checks if the cap has already been reached before calling this function. Hence, it is recommended to call this function immediately upon the list's initialization if possible.
  gen.addOp(IROperation(opCode: SetCapList, arguments: @[uinteger source, integer cap]))

proc passArgument*(gen: IRGenerator, position: uint): uint {.inline, discardable.} =
  ## Adds an atom index to the call arguments register.
  gen.addOp(IROperation(opCode: PassArgument, arguments: @[uinteger position]))

proc loadFloat*(
    gen: IRGenerator, position: uint, value: float | MAtom
): uint {.inline, discardable.} =
  ## Load a float into memory.
  ## **This function is overloadable, and can be provided:**
  ## * a floating point value
  ## * a `MAtom` containing a floating point value
  when value is float:
    gen.addOp(
      IROperation(opCode: LoadFloat, arguments: @[uinteger position, floating value])
    )
  else:
    if value.kind != Float:
      raise newException(ValueError, "Attempt to load " & $value.kind & " as float.")

    gen.addOp(IROperation(opCode: LoadFloat, arguments: @[uinteger position, value]))

proc moveAtom*(gen: IRGenerator, source, dest: uint): uint {.inline, discardable.} =
  ## Move an atom from one index to another. The source index is replaced with a NULL `MAtom` and 
  ## the destination index occupies what was previously the content stored at the source index.
  gen.addOp(IROperation(opCode: MoveAtom, arguments: @[uinteger source, uinteger dest]))

proc copyAtom*(gen: IRGenerator, source, dest: uint): uint {.inline, discardable.} =
  ## Copy an atom from one index to another.
  gen.addOp(IROperation(opCode: CopyAtom, arguments: @[uinteger source, uinteger dest]))

proc markHomogenous*(gen: IRGenerator, position: uint): uint {.inline, discardable.} =
  ## Mark a list as homogenous (i.e, it cannot store more than one type of value).
  ##
  ## The first element of the list's type is inferred to be the type of the rest of the elements and this will be enforced with every append.
  ## .. warning:: This does not check if the list already contains more than one type of value and only performs this check on newly added atoms. It is recommended to call this directly after initializing the list, if possible.
  ## .. warning:: This does not aim to provide any speed boosts whatsoever. Once the JIT compiler is implemented, this might come in handy as a programmer-specified optimization hint, but for now it does absolutely nothing for optimization. It simply exists for semantics.
  gen.addOp(IROperation(opCode: MarkHomogenous, arguments: @[uinteger position]))

proc resetArgs*(gen: IRGenerator): uint {.inline, discardable.} =
  ## Reset the call arguments register.
  gen.addOp(IROperation(opCode: ResetArgs))

proc popList*(gen: IRGenerator, listPos, storeAt: uint): uint {.inline, discardable.} =
  ## Pop the last element of a sequence at `listPos` and store it in `storeAt`.
  ## **See also:**
  ## * `popListPrefix proc<#popListPrefix, IRGenerator, uint, uint>` to pop the first element instead of the last
  gen.addOp(
    IROperation(opCode: PopList, arguments: @[uinteger listPos, uinteger storeAt])
  )

proc popListPrefix*(
    gen: IRGenerator, listPos, storeAt: uint
): uint {.inline, discardable.} =
  ## Pop the first element of a sequence at `listPos` and store it in `storeAt`.
  ## **See also:**
  ## * `popList proc<#popList, IRGenerator, uint, uint>` to pop the last element
  gen.addOp(
    IROperation(opCode: PopListPrefix, arguments: @[uinteger listPos, uinteger storeAt])
  )

proc emit*(gen: IRGenerator, ignoreCache: bool = false): string {.inline.} =
  ## Emit all the IR generated by the IR generation module.
  ## If possible, retrieve pre-generated IR from the MIR cache. Cache hits prevent regeneration of IR, which might be costly*

  if not ignoreCache:
    let cached = retrieve(gen.name, gen)
    if *cached:
      return &cached

  let ir = gen.emitIR()
  cache(gen.name, ir, gen)

  ir

proc emit*(
    gen: IRGenerator, destination: out string, ignoreCache: bool = false
) {.inline.} =
  ## Emit all the IR generated by the IR generation module and store it at `destination`.
  ## If possible, retrieve pre-generated IR from the MIR cache. Cache hits prevent regeneration of IR, which might be costly*
  destination = gen.emit(ignoreCache = ignoreCache)

proc emit*(gen: IRGenerator, destination: File, ignoreCache: bool = false) {.inline.} =
  ## Emit all the IR generated by the IR generation module and write it to the file specified.
  ## If possible, retrieve pre-generated IR from the MIR cache. Cache hits prevent regeneration of IR, which might be costly*
  destination.write(gen.emit(ignoreCache = ignoreCache))

func newIRGenerator*(name: string): IRGenerator {.inline.} =
  ## Initialize a new IR generation helper.
  IRGenerator(name: name, modules: newSeq[CodeModule]())

export shared, Ops
