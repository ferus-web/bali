## Coercion abstract functions
##

#[ 
proc toPrimitive*(vm: PulsarInterpreter, value: MAtom, preferred: MAtomKind): MAtom =
  if not value.isObject():
    debug "runtime: toPrimitive(): atom is not an object, using fast path."
    return value
  
  debug "runtime: toPrimitive(): atom is an object, taking slow path."
  vm.toPrimitiveSlowPath(value, preferred)
]#

import ./[coercible, to_number, to_string]

export coercible, to_number, to_string