## JavaScript URL API - uses sanchar's builtin URL parser
import std/[options, logging, tables]
import bali/internal/sugar
import bali/runtime/[objects, normalize]
import bali/runtime/abstract/coercion
import bali/stdlib/errors
import mirage/ir/generator
import mirage/atom
import mirage/runtime/[prelude]
import sanchar/parse/url
import pretty

const URL_FIELDS = [
  "hostname",
  "pathname",
  "href",
  "hash",
  "host",
  "pathname",
  "port",
  "protocol",
  "searchParams"
]

var parser = newURLParser()

proc transposeUrlToObject(parsed: URL, url: var MAtom, source: MAtom) =
  when not defined(danger):
    assert url.kind == Object, $url.kind

  url.objFields["hostname"] = 0#str parsed.hostname()
  url.objFields["pathname"] = 1#str parsed.path()
  url.objFields["port"] = 2#integer parsed.port()
  url.objFields["protocol"] = 3#str parsed.scheme()
  url.objFields["search"] = 4#str parsed.query()
  url.objFields["host"] = 5#str parsed.hostname()
  url.objFields["href"] = 6#source
  url.objFields["origin"] = 7
  url.objFields["hash"] = 8

  url.objValues = @[
    str parsed.hostname(),
    str parsed.path(),
    integer parsed.port().int,
    str parsed.scheme(),
    str parsed.query(),
    str parsed.hostname(),
    source,
    str(parsed.scheme() & "://" & parsed.hostname() & ":" & $parsed.port()),
    (if parsed.fragment().len > 0: str '#' & parsed.fragment() else: str newString(0))
  ]

proc generateStdIR*(vm: PulsarInterpreter, ir: IRGenerator) =
  info "url: generating IR interfaces"

  # `new URL()` syntax
  vm.registerBuiltin("BALI_CONSTRUCTOR_URL",
    proc(op: Operation) =
      let source =
        if vm.registers.callArgs.len > 0:
          vm.registers.callArgs[0]
        else:
          null()

      if source.kind != String:
        vm.typeError("URL constructor: " & ToString(vm, source) & " is not a valid URL.")
        return

      let parsed = parser.parse(ToString(vm, source))
      var url = obj()

      transposeUrlToObject(parsed, url, source)
      
      vm.registers.retVal = some(url)
  )
  
  ir.newModule(normalizeIRName "URL.parse")
  vm.registerBuiltin("BALI_URLPARSE",
    proc(op: Operation) =
      if vm.registers.callArgs.len < 1:
        vm.registers.retVal = some null()
        return

      let source = vm.registers.callArgs[0]
      
      if source.kind != String:
        vm.registers.retVal = some null()
        return

      var parsed = parser.parse(&source.getStr())

      # allocate object
      var url = obj()
      transposeUrlToObject(parsed, url, source)

      vm.registers.retVal = some(url)
  )
  ir.call("BALI_URLPARSE")
