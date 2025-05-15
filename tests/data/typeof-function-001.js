function a()
{
	return 32;
}

let typ = typeof a
let ret = a()
let retyp = typeof ret

assert.sameValue(typ, "function") // the function is of the type `function`
assert.sameValue(retyp, "number") // the retval of it is a `number`
