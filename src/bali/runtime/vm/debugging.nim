## Debugging utilities
## Author: Trayambak Rai (xtrayambak at disroot dot org)

template msg*(message: string) =
  ## Execution related VM debug messages
  when (not defined(release)) and defined(baliLogExecDbg):
    let
      pc = interpreter.currIndex
      clauseObj = interpreter.clauses[interpreter.currClause]
      clause = clauseObj.name

    stdout.write(
      "vm [pc=" & $pc & ", clause=" & $clause) 
    
    if clauseObj.operations.len.uint > pc:
      let op = clauseObj.operations[pc].opcode
      stdout.write(", op=" & $op)

    stdout.write("] " & message & '\n')

template vmd*(phase: string, message: string) =
  ## Non-execution related VM debug messages
  when (not defined(release)) and defined(baliLogVmDbg):
    stdout.write("vm [" & $phase & "] " & message & '\n')
