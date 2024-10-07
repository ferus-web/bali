## JSON methods
## Copyright (C) 2024 Trayambak Rai and Ferus Authors
import std/[json, options, logging, tables]
import bali/internal/sugar
import bali/runtime/[objects, normalize, atom_helpers, arguments]
import bali/runtime/abstract/coercion
import bali/stdlib/errors
import mirage/ir/generator
import mirage/atom
import mirage/runtime/[prelude]
import jsony

proc convertJsonNodeToAtom*(node: JsonNode): MAtom =
  if node.kind == JInt:
    let value = node.getInt()
    if value > -1: return uinteger(value.uint())
    else: return integer(value)
  elif node.kind == JString:
    return str(node.getStr())
  elif node.kind == JNull:
    return null()
  elif node.kind == JBool:
    return boolean(node.getBool())
  elif node.kind == JArray:
    var arr = sequence(@[])
    for elem in node.getElems():
      arr.sequence &= elem.convertJsonNodeToAtom()
    
    return arr
  elif node.kind == JFloat:
    return floating(node.getFloat())
  elif node.kind == JObject:
    var jObj = obj()

    for key, value in node.getFields():
      jObj.objValues &= value.convertJsonNodeToAtom()
      jObj.objFields[key] = jObj.objValues.len - 1

    return jObj

  null()

proc atomToJsonNode*(atom: MAtom): JsonNode =
  if atom.kind == Integer:
    return newJInt(&atom.getInt())
  elif atom.kind == UnsignedInt:
    return newJInt(int(&atom.getUint()))
  elif atom.kind == Float:
    return newJFloat(&atom.getFloat())
  elif atom.kind == String:
    return newJString(&atom.getStr())
  elif atom.kind == Sequence:
    var arr = newJArray()
    
    for item in atom.sequence:
      arr &= item.atomToJsonNode()

    return arr
  elif atom.kind == Object:
    var jObj = newJObject()
    
    for key, index in atom.objFields:
      jObj[key] = atom.objValues[index].atomToJsonNode()

    return jObj

  newJNull()

proc generateStdIR*(vm: PulsarInterpreter, ir: IRGenerator) =
  info "json: generating IR interfaces"

  ir.newModule(normalizeIRName "JSON.parse")
  ## 25.5.1 JSON.parse ( text [ , reviver ] )
  ## This function parses a JSON text (a JSON-formatted String) and produces an ECMAScript language value. The JSON format represents literals, arrays, and objects with a syntax similar to the syntax for ECMAScript literals, Array Initializers, and Object Initializers. After parsing, JSON objects are realized as ECMAScript objects. JSON arrays are realized as ECMAScript Array instances. JSON strings, numbers, booleans, and null are realized as ECMAScript Strings, Numbers, Booleans, and null.
  vm.registerBuiltin(
    "BALI_JSONPARSE",
    proc(op: Operation) =
      # 1. Let jsonString be ? ToString(text).
      let jsonString = if vm.registers.callArgs.len != 0:
        vm.ToString(vm.registers.callArgs[0])
      else: ""

      let parsed =
        try:
          fromJson(jsonString)
        except jsony.JsonError as exc:
          vm.syntaxError(exc.msg)
          JsonNode()

      let atom = convertJsonNodeToAtom(parsed)
      vm.registers.retVal = some(atom),
  )
  ir.call("BALI_JSONPARSE")

  ir.newModule(normalizeIRName "JSON.stringify")
  ## 25.5.2 JSON.stringify ( value [ , replacer [ , space ] ] )
  # FIXME: not compliant yet!
  ## This function returns a String in UTF-16 encoded JSON format representing an ECMAScript language value, or undefined. It can take three parameters. The value parameter is an ECMAScript language value, which is usually an object or array, although it can also be a String, Boolean, Number or null. The optional replacer parameter is either a function that alters the way objects and arrays are stringified, or an array of Strings and Numbers that acts as an inclusion list for selecting the object properties that will be stringified. The optional space parameter is a String or Number that allows the result to have white space injected into it to improve human readability.
  vm.registerBuiltin(
    "BALI_JSONSTRINGIFY",
    proc(op: Operation) =
      let 
        atom = &vm.argument(0)
        node = atomToJsonNode(atom)

      vm.registers.retVal = some(
        str(
          pretty node
        )
      ),
  )
  ir.call("BALI_JSONSTRINGIFY")
