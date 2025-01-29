let x = new Number(32)
console.log(x)

assert.sameValue(Number.isFinite(32), true)
assert.sameValue(Number.isFinite(x), false)
assert.sameValue(Number.parseInt(32), 32)
assert.sameValue(x.valueOf(), 32.0)
