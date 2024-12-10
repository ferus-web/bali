## JavaScript URL API - uses sanchar's builtin URL parser
import std/[options, logging, tables]
import bali/internal/sugar
import bali/runtime/[normalize, arguments, types, atom_helpers]
import bali/runtime/abstract/coercion
import bali/stdlib/errors
import mirage/ir/generator
import mirage/atom
import mirage/runtime/[prelude]
import sanchar/parse/url
import pretty

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

proc transposeUrlToObject(runtime: Runtime, parsed: URL, source: string): MAtom =
  var url = runtime.createObjFromType(JSURL)
  url["hostname"] = str(parsed.hostname())
  url["pathname"] = parsed.path().str()
  url["port"] = parsed.port().int.integer()
  url["protocol"] = str(parsed.scheme() & ':')
  url["search"] = parsed.query().str()
  url["hostname"] = parsed.hostname().str()
  url["source"] = source.str()
  url["origin"] =
    str(parsed.scheme() & "://" & parsed.hostname() & ":" & $parsed.port())
  url["hash"] =
    (if parsed.fragment().len > 0: str '#' & parsed.fragment()
    else: str newString(0))

  url

proc generateStdIR*(runtime: Runtime) =
  info "url: generating IR interfaces"

  runtime.registerType("URL", JSURL)

  # URL constructor (`new URL()` syntax)
  runtime.defineConstructor(
    "URL",
    proc() =
      var osource: Option[MAtom]

      if (;
        osource = runtime.argument(
          1, true,
          "URL constructor: At least 1 argument required, but only {nargs} passed",
        )
        !osource
      ):
        return

      let source = &move(osource)

      if source.kind != String:
        runtime.typeError(
          "URL constructor: " & runtime.ToString(source) & " is not a valid URL."
        )
        return

      let parsed =
        try:
          parser.parse(runtime.ToString(source))
        except URLParseError as pError:
          debug "url: encountered parse error whilst parsing url: " & &source.getStr() &
            ": " & pError.msg
          debug "url: this is a constructor, so a TypeError will be thrown."
          runtime.typeError(pError.msg)
          newURL("", "", "", "")
            # unreachable, no need to worry. this just exists to make the compiler happy.

      if parsed.scheme().len < 1:
        return

      ret transposeUrlToObject(runtime, parsed, &source.getStr())
    ,
  )

  # URL.parse()
  runtime.defineFn(
    JSURL,
    "parse",
    proc() =
      var osource: Option[MAtom]

      if (;
        osource = runtime.argument(
          1, true, "URL.new: At least 1 argument required, but only {nargs} passed"
        )
        !osource
      ):
        return

      let source = &move(osource)

      if source.kind != String:
        ret null()

      var parsed =
        try:
          parser.parse(&source.getStr())
        except URLParseError as exc:
          debug "url: encountered parse error whilst parsing url: " & &source.getStr() &
            ": " & exc.msg
          debug "url: this is the function variant, so no error will be thrown."
          URL()

      ret transposeUrlToObject(runtime, parsed, &source.getStr())
    ,
  )
