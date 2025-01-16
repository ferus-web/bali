import std/[logging, options, strutils]
import mirage/atom
import mirage/runtime/pulsar/interpreter
import bali/runtime/[atom_helpers, types]
import bali/stdlib/errors

proc argument*(
    runtime: Runtime, position: Natural, required: bool = false, message: string = ""
): Option[MAtom] =
  ## Get an argument from the call arguments register.
  ## If `required` is `true`, then a TypeError with an error message of your choice will be thrown.
  ## This routine is guaranteed to return a value when `required` is set to `false`, which it is by default.
  ##
  ## Error message substitutions:
  ## `{nargs}` - the number of arguments currently in the call arguments register
  assert(position > 0, "argument() only accepts naturals.")
  debug "runtime: fetching argument #" & $position

  if runtime.vm.registers.callArgs.len < position:
    debug "runtime: argument(): " & $position & " > " &
      $runtime.vm.registers.callArgs.len
    if required:
      debug "runtime: argument(): `required` == true, throwing TypeError"
      when not defined(danger):
        if message.len < 1:
          warn "runtime: FIXME: argument() was provided an empty error message for when an atom is required, this can make debugging more difficult for users."

      let msg = message.multiReplace({"{nargs}": $runtime.vm.registers.callArgs.len})

      typeError(runtime, msg)
      return
    else:
      debug "runtime: argument(): `required` == false, ignoring and returning `undefined`"
      return some(undefined())

  some(runtime.vm.registers.callArgs[position - 1])
