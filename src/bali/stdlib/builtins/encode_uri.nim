## Implementation of encodeURI()
## Author(s):
## Trayambak Rai (xtrayambak at disroot dot org)
import pkg/bali/runtime/[arguments, bridge, types, construction]
import pkg/bali/runtime/abstract/coercion
import pkg/bali/internal/[sugar, uri_coding]

proc generateStdIR*(runtime: Runtime) =
  runtime.defineFn(
    "encodeURI",
    proc() =
      let uri =
        if runtime.argumentCount() > 0:
          &runtime.argument(1)
        else:
          undefined(runtime)

      # 1. Let uriString be ? ToString(uri)
      let uriString = runtime.ToString(uri)

      # 2. Let extraUnescaped be ";/?:@&=+$,#"
      const extraUnescaped: set[char] =
        {';', '/', '?', ':', '@', '&', '=', '+', '$', ',', '#'}

      # 3. Return ? Encode (uriString, extraUnescaped)
      ret encode(uriString, extraUnescaped)
    ,
  )
