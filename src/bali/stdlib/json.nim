## JSON methods

import std/[json, options, logging, tables]
import bali/internal/sugar
import bali/runtime/[arguments, types, bridge, construction]
import bali/runtime/abstract/coercion
import bali/stdlib/errors
import bali/runtime/vm/atom
import jsony

proc convertJsonNodeToAtom*(runtime: Runtime, node: JsonNode): JSValue =
  if node.kind == JInt:
    let value = node.getInt()

    return integer(runtime, value)
  elif node.kind == JString:
    return str(runtime, node.getStr())
  elif node.kind == JNull:
    return null(runtime)
  elif node.kind == JBool:
    return boolean(runtime, node.getBool())
  elif node.kind == JArray:
    var arr = sequence(runtime, @[])
    for elem in node.getElems():
      arr.sequence &= convertJsonNodeToAtom(runtime, elem)[]

    return arr
  elif node.kind == JFloat:
    return floating(runtime, node.getFloat())
  elif node.kind == JObject:
    var jObj = obj(runtime)

    for key, value in node.getFields():
      jObj.objValues &= convertJsonNodeToAtom(runtime, value)
      jObj.objFields[key] = jObj.objValues.len - 1

    return jObj

  null(runtime)

type JSON = object

proc atomToJsonNode*(atom: JSValue): JsonNode =
  if atom.kind == Integer:
    return newJInt(&atom.getInt())
  elif atom.kind == Float:
    return newJFloat(&atom.getFloat())
  elif atom.kind == String:
    return newJString(&atom.getStr())
  elif atom.kind == Sequence:
    var arr = newJArray()

    for i, _ in atom.sequence:
      arr &= atom.sequence[i].addr.atomToJsonNode()

    return arr
  elif atom.kind == Object:
    var jObj = newJObject()

    for key, index in atom.objFields:
      jObj[key] = atom.objValues[index].atomToJsonNode()

    return jObj

  newJNull()

proc generateStdIR*(runtime: Runtime) =
  info "json: generating IR interfaces"

  runtime.registerType("JSON", JSON)

  ## 25.5.1 JSON.parse ( text [ , reviver ] )
  ## This function parses a JSON text (a JSON-formatted String) and produces an ECMAScript language value. The JSON format represents literals, arrays, and objects with a syntax similar to the syntax for ECMAScript literals, Array Initializers, and Object Initializers. After parsing, JSON objects are realized as ECMAScript objects. JSON arrays are realized as ECMAScript Array instances. JSON strings, numbers, booleans, and null are realized as ECMAScript Strings, Numbers, Booleans, and null.
  runtime.defineFn(
    JSON,
    "parse",
    proc() =
      # 1. Let jsonString be ? ToString(text).
      let jsonString =
        if runtime.argumentCount() != 0:
          runtime.ToString(&runtime.argument(1))
        else:
          newString(0)

      let parsed =
        try:
          fromJson(jsonString)
        except jsony.JsonError as exc:
          runtime.syntaxError(exc.msg)
          JsonNode()

      let atom = runtime.convertJsonNodeToAtom(parsed)
      ret atom
    ,
  )

  ## 25.5.2 JSON.stringify ( value [ , replacer [ , space ] ] )
  ## This function returns a String in UTF-16 encoded JSON format representing an ECMAScript language value, or undefined. It can take three parameters. The value parameter is an ECMAScript language value, which is usually an object or array, although it can also be a String, Boolean, Number or null. The optional replacer parameter is either a function that alters the way objects and arrays are stringified, or an array of Strings and Numbers that acts as an inclusion list for selecting the object properties that will be stringified. The optional space parameter is a String or Number that allows the result to have white space injected into it to improve human readability.

  #when defined(baliOldJsonStringifyImpl):
  # Old implementation, not compliant.
  runtime.defineFn(
    JSON,
    "stringify",
    proc() =
      let
        atom = &runtime.argument(1)
        node = atomToJsonNode(atom)

      ret str(runtime, pretty node)
    ,
  )
  #[ else:
    # New implementation, compliant.
    runtime.defineFn(
      JSON,
      "stringify",
      proc() =
        # 1. Let stack be a new empty List.
        var stack: seq[JSValue] # Not to be confused with stack atoms!
      ,
    ) ]#
