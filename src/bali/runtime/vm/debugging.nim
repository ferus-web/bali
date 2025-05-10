## Debugging utilities
## Author: Trayambak Rai (xtrayambak at disroot dot org)

template msg*(message: string) =
  ## Execution related VM debug messages
  when (not defined(release)) and not defined(silent):
    let
      pc = interpreter.currIndex
      clause = interpreter.clauses[interpreter.currClause].name
      op = interpreter.clauses[interpreter.currClause].operations[pc].opcode

    stdout.write("vm [pc=" & $pc & ", clause=" & $clause & ", op=" & $op & "] " & message & '\n')

template vmd*(phase: string, message: string) =
  ## Non-execution related VM debug messages
  when (not defined(release)) and not defined(silent):
    stdout.write("vm [" & $phase & "] " & message & '\n')
