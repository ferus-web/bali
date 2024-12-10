import std/[strutils, unittest]
import bali/internal/trim_string

suite "TrimString( string, where )":
  test "trim leading whitespace":
    check "   32".internalTrim(strutils.Whitespace, TrimMode.Left) == "32"
    check "           :^)".internalTrim(strutils.Whitespace, TrimMode.Left) == ":^)"

  #[ test "trim ending whitespace":
    check "32   ".internalTrim(strutils.Whitespace, TrimMode.Right) == "32"
    check ":^)                  ".internalTrim(strutils.Whitespace, TrimMode.Right) == ":^)" ]#
