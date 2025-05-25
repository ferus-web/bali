## Here's how you can make a simple JavaScript grammar validator in Nim.
## Obviously, there's a lot of syntax that Bali simply cannot handle, in which case it'll
## mark it as invalid.
import std/os
import pkg/bali/easy

proc main() =
  if paramCount() < 1:
    quit("Usage: javascript_validator [file]")

  let file = paramStr(1)

  if not fileExists(file):
    quit("File not found: " & file)

  if isValidJS(readFile(file)):
    echo "This is valid JavaScript."
    quit(0)
  else:
    echo "Aw, this is invalid JavaScript code."
    quit(1)

when isMainModule:
  main()
