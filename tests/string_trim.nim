import std/[strutils]
import bali/internal/trim_string

let x = "   32".internalTrim(strutils.Whitespace, TrimMode.Left)
echo x
