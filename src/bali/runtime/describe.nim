import std/[strutils, terminal]
import bali/runtime/vm/atom
import bali/runtime/[bridge, arguments, types]
import bali/internal/sugar
import bali/stdlib/prelude

proc generateDescribeFnCode*(runtime: Runtime) =
  runtime.defineFn(
    "describe",
    proc() =
      let argument = uint(
        &getInt(
          &runtime.argument(
            1,
            required = true,
            message = "describe() expects 1 argument (stack index), got {nargs}",
          )
        )
      )
      if (argument < 0) or (argument > uint(runtime.vm.stack.len - 1)):
        stderr.styledWriteLine(
          fgRed, "No such value exists at index " & $argument, resetStyle
        )
        return

      var val = runtime.vm.stack[argument].addr

      stdout.styledWriteLine(
        styleBright,
        "Location",
        resetStyle,
        ": ",
        fgGreen,
        "0x" & $toHex(cast[uint](val)),
        resetStyle,
      )
      stdout.styledWriteLine(
        styleBright, "Kind", resetStyle, ": ", fgGreen, $val[].kind, resetStyle
      )

      stdout.styledWrite(styleBright, "Description", resetStyle, ": ", fgGreen)
      case val[].kind
      of String:
        stdout.write "Unboxed string (atom String)\n"
      of Integer:
        stdout.write "Unboxed number (atom Int32)\n"
      of Float:
        stdout.write "Unboxed number (atom Float64)\n"
      else:
        if runtime.isA(val[], JSString):
          echo "Boxed string (JSString)"
        else:
          stdout.write "N/A\n"
      stdout.styledWrite(resetStyle),
  )
