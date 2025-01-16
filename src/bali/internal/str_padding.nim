## String padding routine
## Author(s):
## Trayambak Rai (xtrayambak at disroot dot org)
import std/[strutils]

type PaddingPlacement* {.pure.} = enum
  Start
  End

func padString*(
    s: string, maxLength: uint, fillString: string, placement: PaddingPlacement
): string =
  ## 22.1.3.17.2 StringPad ( s, maxLength, fillString, placement )
  ## The abstract operation StringPad takes arguments S (a String), maxLength (a non-negative integer), fillString (a
  ## String), and placement (START or END) and returns a String. It performs the following steps when called:

  let stringLength = s.len.uint # 1. Let stringLength be the length of s

  if maxLength <= stringLength:
    # 2. If maxLength ≤ stringLength, return S.
    return s

  if fillString.len < 1:
    # 3. If fillString is empty string, return S.
    return s

  # 4. Let fillLen be maxLength - stringLength
  let fillLen = maxLength - stringLength

  # 5. Let truncatedStringFiller be the string value consisting of repeated concatenations of fillString truncated to length fillLen
  let truncatedStringFiller = repeat(fillString, fillLen)

  # 6. If placement is START, return the string-concatenation of truncatedStringFiller and s.
  if placement == PaddingPlacement.Start:
    return truncatedStringFiller & s
  else:
    # 7. Else, return the string-concatenation of S and truncatedStringFiller.
    return s & truncatedStringFiller
