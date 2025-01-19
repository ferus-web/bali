import std/[strutils, logging, options]

proc parseNumberText*(text: string): Option[float] {.inline.} =
  debug "parseNumberText: " & text

  try:
    return float(parseInt(text)).some()
  except ValueError as exc:
    debug "parseNumberText: " & exc.msg
    try:
      return float(parseFloat(text)).some()
    except ValueError as exc:
      debug "parseNumberText: malformed data provided: " & text & " (" & exc.msg & ')'
