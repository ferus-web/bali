## Caching utility for the IR generator to speed-up IR generation.
## This isn't really needed yet but it should help with a few potential slowdowns later.
## It uses its own MIR format that is encoded via Flatty and compressed via Zippy to save on space.
##


import std/[os, options, hashes]
import zippy, flatty/binny
import ./shared

const IrMagic* = 0xF33DC0DE'u64

proc getMirageCacheDir*(): string {.inline.} =
  getCacheDir() / "mirage"

proc cache*(name: string, ir: string, gen: IRGenerator) {.inline.} =
  when defined(mirageDontCacheBytecode):
    return

  let path = getMirageCacheDir()

  if not dirExists(path):
    createDir(path)

  let emissionCache = path / "emission_cache"

  if not dirExists(emissionCache):
    createDir(emissionCache)

  # Create binary data
  var final: string
  final.addUint64(IrMagic) # append IR magic
  final.addInt64(hash(gen)) # append op list + module list hash
  final.addStr(ir)

  writeFile(emissionCache / name & ".mir", final.compress())

proc retrieve*(name: string, gen: IRGenerator): Option[string] {.inline.} =
  when defined(mirageDontCacheBytecode):
    return

  let emissionCache = getMirageCacheDir() / "emission_cache"

  if not dirExists(emissionCache):
    return

  let fPath = emissionCache / name & ".mir"

  if not fileExists(fPath):
    return

  var data: string

  try:
    data = readFile(fPath).uncompress()
  except ZippyError:
    return # invalid compression scheme

  if data.readUint64(0) != IrMagic: # not a valid MIR file (or corrupted)
    return

  let hashValue = cast[Hash](data.readInt64(sizeof uint64))

  if hashValue != hash gen: # invalidated cache
    return

  some data.readStr(2 * sizeof uint64, data.len - 1)

proc retrieve*(name: string): Option[string] {.inline.} =
  let emissionCache = getMirageCacheDir() / "emission_cache"

  if not dirExists(emissionCache):
    return

  let fPath = emissionCache / name & ".mir"

  if not fileExists(fPath):
    return

  var data: string

  try:
    data = readFile(fPath).uncompress()
  except ZippyError:
    return

  some data.readStr(2 * sizeof uint64, data.len - 1)