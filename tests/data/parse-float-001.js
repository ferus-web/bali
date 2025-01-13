let x = 0.4
let y = 1.0023822

let propX = JSON.parse("0.4")
let propY = JSON.parse("1.0023822")

assert.sameValue(x, propX)
assert.sameValue(y, propY)
