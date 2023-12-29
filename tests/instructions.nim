import bali/[jsvalue, instruction]

let instructions = @[
  Instruction(
    kind: SET_CONST,
    sConstName: "x",
    sConstValue: JSValue(
      payload: "5"
    )
  ),
  Instruction(
    kind: SET_CONST,
    sConstName: "y",
    sConstValue: JSValue(
      payload: "8"
    )
  )
]

for inst in instructions:
  echo $inst
