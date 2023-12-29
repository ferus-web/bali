import std/[strutils, marshal], nimSHA2

type
  JSValueKind* = enum
    jskInt
    jskStr
    jskNone
  
  JSValue* = ref object of RootObj
    payload*: string
    # kind*: JSValueKind

proc `$`*(jsk: JSValueKind): string =
  case jsk:
    of jskInt:
      return "Integer (bits not specified)"
    of jskStr:
      return "String"
    of jskNone:
      return "None"

proc `$`*(jsv: JSValue): string {.inline.} =
  $$jsv

proc getInt*(value: JSValue): int =
  assert {'a'..'z'} notin value.payload.toLowerAscii()

  parseInt(value.payload)

proc getBool*(value: JSValue): bool =
  result = case value.payload
  of "true": true
  of "false": false
  else: raise newException(ValueError, "getBool() failed: " & value.payload)

proc hash*(value: JSValue): string =
  var state = initSHA[SHA256]()

  state.update(value.payload)

  $state.final()

proc inferType*(value: string): JSValueKind =
  if value.startsWith('"') and value.endsWith('"'):
    return jskStr
  
  var canBeInt = true
  for c in value:
    if c notin {'0'..'9'}:
      canBeInt = false
      break
  
  if canBeInt:
    return jskInt

  return jskNone

proc inferType*(value: JSValue): JSValueKind =
  inferType(value.payload)

proc getStr*(value: JSValue): string =
  value.payload
