## JavaScript URL API - uses sanchar's builtin URL parser
import std/[options, logging]
import bali/internal/sugar
import bali/runtime/[arguments, types, atom_helpers, bridge, construction]
import bali/runtime/abstract/coercion
import bali/stdlib/errors
import bali/stdlib/types/std_string_type
import bali/runtime/vm/atom
import sanchar/parse/url
var parser = newURLParser()

type JSURL = object
  host*: string
  hostname*: string
  pathname*: string
  port*: int
  protocol*: string
  search*: string
  href*: string
  origin*: string
  source*: string
  hash*: string

proc transposeUrlToObject(runtime: Runtime, parsed: URL, source: string): JSValue =
  var url = runtime.createObjFromType(JSURL)
  url["hostname"] = runtime.newJSString(parsed.hostname())
  url["pathname"] = runtime.newJSString(parsed.path())
  url["port"] = integer(runtime, parsed.port.int)
  url["protocol"] = runtime.newJSString(parsed.scheme() & ':')
  url["search"] = runtime.newJSString(parsed.query())
  url["hostname"] = runtime.newJSString(parsed.hostname())
  url["source"] = runtime.newJSString(source)
  url["origin"] = runtime.newJSString(
    parsed.scheme() & "://" & parsed.hostname() & ":" & $parsed.port()
  )
  url["hash"] = runtime.newJSString(
    if parsed.fragment().len > 0:
      '#' & parsed.fragment()
    else:
      newString(0)
  )

  ensureMove(url)

proc generateStdIR*(runtime: Runtime) =
  info "url: generating IR interfaces"

  runtime.registerType("URL", JSURL)

  # URL constructor (`new URL()` syntax)
  runtime.defineConstructor(
    "URL",
    proc() =
      var osource: Option[JSValue]

      if (;
        osource = runtime.argument(
          1, true,
          "URL constructor: At least 1 argument required, but only {nargs} passed",
        )
        !osource
      ):
        return

      let source = &ensureMove(osource)

      if not runtime.isA(source, JSString):
        runtime.typeError(
          "URL constructor: " & runtime.ToString(source) & " is not a valid URL."
        )
        return

      let str = runtime.ToString(source)

      let parsed =
        try:
          parser.parse(str)
        except URLParseError as pError:
          debug "url: encountered parse error whilst parsing url: " & str & ": " &
            pError.msg
          debug "url: this is a constructor, so a TypeError will be thrown."
          runtime.typeError(pError.msg)
          newURL("", "", "", "")
            # unreachable, no need to worry. this just exists to make the compiler happy.

      if parsed.scheme().len < 1:
        return

      ret transposeUrlToObject(runtime, parsed, str)
    ,
  )

  # URL.parse()
  runtime.defineFn(
    JSURL,
    "parse",
    proc() =
      var osource: Option[JSValue]

      if (;
        osource = runtime.argument(
          1, true, "URL.new: At least 1 argument required, but only {nargs} passed"
        )
        !osource
      ):
        return

      let source = &ensureMove(osource)

      if not runtime.isA(source, JSString):
        ret null(runtime)

      let str = runtime.ToString(source)

      var parsed =
        try:
          parser.parse(str)
        except URLParseError as exc:
          debug "url: encountered parse error whilst parsing url: " & str & ": " &
            exc.msg
          debug "url: this is the function variant, so no error will be thrown."
          URL()

      ret transposeUrlToObject(runtime, parsed, str)
    ,
  )
