## JavaScript URL API - uses sanchar's builtin URL parser
import std/[options, logging, tables]
import bali/internal/sugar
import bali/runtime/[objects, normalize, arguments]
import bali/runtime/abstract/coercion
import bali/stdlib/errors
import mirage/ir/generator
import mirage/atom
import mirage/runtime/[prelude]
import sanchar/parse/url
import pretty

var parser = newURLParser()

proc transposeUrlToObject(parsed: URL, url: var MAtom, source: MAtom) =
  when not defined(danger):
    assert url.kind == Object,
      "transposeUrlToObject() was given non-Object type: " & $url.kind

  url.objFields["hostname"] = 0 #str parsed.hostname()
  url.objFields["pathname"] = 1 #str parsed.path()
  url.objFields["port"] = 2 #integer parsed.port()
  url.objFields["protocol"] = 3 #str parsed.scheme()
  url.objFields["search"] = 4 #str parsed.query()
  url.objFields["host"] = 5 #str parsed.hostname()
  url.objFields["href"] = 6 #source
  url.objFields["origin"] = 7
  url.objFields["hash"] = 8

  url.objValues =
    @[
      str parsed.hostname(),
      str parsed.path(),
      integer parsed.port().int,
      str parsed.scheme(),
      str parsed.query(),
      str parsed.hostname(),
      source,
      str(parsed.scheme() & "://" & parsed.hostname() & ":" & $parsed.port()),
      (if parsed.fragment().len > 0: str '#' & parsed.fragment()
      else: str newString(0)),
    ]

proc generateStdIR*(vm: PulsarInterpreter, ir: IRGenerator) =
  info "url: generating IR interfaces"

  # `new URL()` syntax
  vm.registerBuiltin(
    "BALI_CONSTRUCTOR_URL",
    proc(op: Operation) =
      var osource: Option[MAtom]

      if (;
        osource = vm.argument(
          1, true,
          "URL constructor: At least 1 argument required, but only {nargs} passed",
        )
        !osource
      ):
        return

      let source = &move(osource)

      if source.kind != String:
        vm.typeError(
          "URL constructor: " & ToString(vm, source) & " is not a valid URL."
        )
        return

      let parsed =
        try:
          parser.parse(ToString(vm, source))
        except URLParseError as pError:
          debug "url: encountered parse error whilst parsing url: " & &source.getStr() &
            ": " & pError.msg
          debug "url: this is a constructor, so a TypeError will be thrown."
          vm.typeError(pError.msg)
          newURL("", "", "", "")
            # unreachable, no need to worry. this just exists to make the compiler happy.

      if parsed.scheme().len < 1:
        return

      var url = obj()

      transposeUrlToObject(parsed, url, source)

      vm.registers.retVal = some(url),
  )

  ir.newModule(normalizeIRName "URL.parse")
  vm.registerBuiltin(
    "BALI_URLPARSE",
    proc(op: Operation) =
      if vm.registers.callArgs.len < 1:
        vm.registers.retVal = some null()
        return

      var osource: Option[MAtom]

      if (;
        osource = vm.argument(
          1, true, "URL.new: At least 1 argument required, but only {nargs} passed"
        )
        !osource
      ):
        return

      let source = &move(osource)

      if source.kind != String:
        vm.registers.retVal = some null()
        return

      var parsed =
        try:
          parser.parse(&source.getStr())
        except URLParseError as exc:
          debug "url: encountered parse error whilst parsing url: " & &source.getStr() &
            ": " & exc.msg
          debug "url: this is the function variant, so no error will be thrown."
          URL()

      # allocate object
      var url = obj()
      transposeUrlToObject(parsed, url, source)

      vm.registers.retVal = some(url),
  )
  ir.call("BALI_URLPARSE")
