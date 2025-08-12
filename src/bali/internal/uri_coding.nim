## URI encoding/decoding routines
##
## Copyright (C) 2025 Trayambak Rai (xtrayambak at disroot dot org)
## https://ecma-international.org/wp-content/uploads/ECMA-262_15th_edition_june_2024.pdf
import std/[strutils]
import pkg/bali/internal/[str_padding], pkg/ferrite/utf16view

proc encode*(uri: string, extraUnescaped: set[char] = {}): string =
  ## 19.2.6.5 Encode ( string, extraUnescaped )
  ## The abstract operation Encode takes arguments string (a String) and extraUnescaped (a String) and returns
  ## either a normal completion containing a String or a throw completion. It performs URI encoding and escaping,
  ## interpreting string as a sequence of UTF-16 encoded code points as described in 6.1.4. If a character is identified
  ## as unreserved in RFC 2396 or appears in extraUnescaped, it is not escaped. It performs the following steps
  ## when called:

  let length = uint32(uri.len) # 1. Let len be the length of uri.
  var res: string # 2. Let R be the empty string
  const alwaysUnescaped: set[char] = {'-', '.', '!', '~', '*', '\'', '(', ')'} + Letters
    # 3. Let alwaysUnescaped be the string-concatenation of the ASCII word characters and "-.!~*'()"
  let unescapedSet = alwaysUnescaped + extraUnescaped
    # 4. Let unescapedSet be the string-concatenation of alwaysUnescaped and extraUnescaped
  var k = 0'u32 # 5. Let k be 0
  let view = newUTF16View(uri)

  # 6. Repeat, while k < len
  while k < length:
    # a. Let c be the code unit at index k within uri
    let c = uri[k]

    # b. If unescapedSet contains C, then
    if unescapedSet.contains(c):
      # i. Set k to k + 1
      inc k

      # ii. Set R to the string-concatenation of res and C.
      res &= c
    else: # c. Else,
      # i. Let cp be CodePointAt(uri, k)
      let cp = cast[uint8](view.codePointAt(k))
      inc k

      let hex = cp.toHex()

      res &= '%' & padString(hex, 2, "0", PaddingPlacement.Start)

  # 7. Return res.
  res

proc encodeURI*(uri: string): string =
  encode(uri, {';', '/', '?', ':', '@', '&', '=', '+', '$', ',', '#'})
