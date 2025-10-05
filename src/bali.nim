{.
  error:
    """Do not import pkg/bali directly! It is a fairly "heavyweight" library in relativity to other Nim packages.
  * Import `pkg/bali/runtime/prelude` if you wish to execute JavaScript and bind Nim interfaces to it.
  * Import `pkg/bali/grammar/prelude` if you wish to simply parse JavaScript and turn it into a traversable representation.
  * Import `pkg/bali/easy` if you want a quick-and-dirty way to toy around with JavaScript in your program.
  """
.}
