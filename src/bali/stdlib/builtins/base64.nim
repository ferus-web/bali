## Base64 encoding/decoding
## These aren't part of the ECMAScript standard, but rather the HTML living spec.
##

import std/[options, logging]
import mirage/runtime/prelude
import bali/runtime/[arguments, types, bridge]
import bali/runtime/abstract/coercion
import bali/stdlib/errors
import bali/internal/sugar

when not defined(baliUseStdBase64):
  import simdutf/base64
else:
  import std/base64
  type Base64DecodeError = ValueError

proc generateStdIr*(runtime: Runtime) =
  info "builtins.base64: generating IR interfaces"

  # atob
  # Decode a base64 encoded string
  runtime.defineFn(
    "atob",
    proc() =
      if runtime.argumentCount() < 1:
        typeError(runtime, "atob: At least 1 argument required, but only 0 passed")
        return

      template decodeError() =
        warn "atob: failed to decode string: " & exc.msg
        typeError(runtime, "atob: String contains an invalid character")
        return

      let
        value = runtime.RequireObjectCoercible(&runtime.argument(1))
        strVal = runtime.ToString(value)

      try:
        ret str decode(strVal)
      except Base64DecodeError as exc:
        decodeError,
  )

  # btoa
  # Encode a string into Base64 data
  runtime.defineFn(
    "btoa",
    proc() =
      let
        value = runtime.RequireObjectCoercible(
          &runtime.argument(
            1,
            required = true,
            message = "btoa: At least 1 argument required, but only {nargs} passed",
          )
        )
        str = runtime.ToString(value)

      ret str encode(str)
    ,
  )
