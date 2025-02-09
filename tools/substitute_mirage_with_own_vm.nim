## Tool to replace Mirage with the new in-tree VM
import std/[os, strutils]

proc main() {.inline.} =
  var affected = 0
  for file in walkDirRec("src/"):
    if not fileExists(file):
      continue

    let data = readFile(file)
    let content = data.multiReplace(
      {
        "mirage/atom": "bali/runtime/vm/atom",
        "mirage/runtime/prelude": "bali/runtime/vm/runtime/prelude",
        "mirage/ir/generator": "bali/runtime/vm/ir/generator",
        "bali/runtime/ir/generator": "bali/runtime/vm/ir/generator",
      }
    )
    if content != data:
      echo "> " & file
      inc affected

    writeFile(file, content)

  echo "De-miragified " & $affected & " files"

when isMainModule:
  main()
