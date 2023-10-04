# WARNING: this is for internal interpreter errors, not JavaScript errors.
proc error*(msg: string) =
  echo "\e[0;31m" & "ERROR" & "\e[0m" & ": " & msg
  quit 1

# debug/info
proc info*(msg: string) =
  echo "\e[0;32m" & "INFO" & "\e[0m" & ": " & msg
