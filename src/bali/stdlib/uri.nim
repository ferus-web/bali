## JavaScript URL API - uses nim-url for URL parsing as per WHATWG
##
## Copyright (C) 2024-2025 Trayambak Rai (xtrayambak at disroot dot org)

import std/[options, logging]
import
  pkg/bali/internal/sugar,
  pkg/bali/runtime/[arguments, types, atom_helpers, bridge, construction],
  pkg/bali/runtime/abstract/coercion,
  pkg/bali/stdlib/errors,
  pkg/bali/stdlib/types/std_string_type,
  pkg/bali/runtime/vm/atom
import pkg/[results, url]

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

  if *parsed.hostname:
    url["hostname"] = runtime.newJSString(&parsed.hostname)

  url["pathname"] = runtime.newJSString(parsed.pathname)

  if *parsed.port:
    url["port"] = integer(runtime, &parsed.port)

  url["protocol"] = runtime.newJSString(parsed.scheme & ':')

  if *parsed.query:
    url["search"] = runtime.newJSString(&parsed.query)

  url["source"] = runtime.newJSString(source)
  url["origin"] = runtime.newJSString(serialize(parsed))

  if *parsed.fragment:
    url["hash"] = runtime.newJSString('#' & &parsed.fragment)

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

      let
        str = runtime.ToString(source)
        parsed = tryParseUrl(str)

      if !parsed:
        runtime.typeError($parsed.error())
      else:
        ret transposeUrlToObject(runtime, &parsed, str)
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

      let
        str = runtime.ToString(source)
        parsed = tryParseURL(str)

      if *parsed:
        ret transposeUrlToObject(runtime, &parsed, str)
      else:
        ret JSURL()
    ,
  )
