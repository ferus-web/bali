proc normalizeIRName*(name: string): string =
  ## Normalize or "mangle" a raw identifier to be MIR-friendly.
  var buffer: string

  for i, c in name:
    case c
    of {'a' .. 'z'}, {'A' .. 'Z'}:
      buffer &= c
    of '.':
      buffer &= "dot"
    of '$':
      {.linearScanEnd.}
      buffer &= "dollar"
    of '0':
      buffer &= "zero"
    of '1':
      buffer &= "one"
    of '2':
      buffer &= "two"
    of '3':
      buffer &= "three"
    of '4':
      buffer &= "four"
    of '5':
      buffer &= "five"
    of '6':
      buffer &= "six"
    of '7':
      buffer &= "seven"
    of '8':
      buffer &= "eight"
    of '9':
      buffer &= "nine"
    of '_':
      buffer &= "underscore"
    of '@':
      buffer &= "at"
    of '%':
      buffer &= "percent"
    of '^':
      buffer &= "pow"
    of '!':
      buffer &= "excl"
    else:
      raise newException(
        ValueError,
        "Found invalid character in buffer during normalization (pos " & $i & "): '" & c &
          "' in " & name,
      )

  buffer
