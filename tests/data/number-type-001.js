let x = new Number(32)
console.log(x)

assert.sameValue(Number.MAX_SAFE_INTEGER, 9007199254740991)
assert.sameValue(Number.POSITIVE_INFINITY, Infinity)
assert.sameValue(Number.isFinite(32), true)
assert.sameValue(Number.isFinite(x), false)
assert.sameValue(Number.parseInt("32"), 32) // FIXME: Number.parseInt(32) returns NaN since parseInt() can't handle floats (32.0)
assert.sameValue(x.valueOf(), 32.0)
