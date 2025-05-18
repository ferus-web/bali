/* Test suite for compound assignments
 * Author: Trayambak Rai (xtrayambak at disroot dot org)
*/

let x = 0.1
x += 0.2

let y = 32
y *= 0.5
assert.sameValue(y, 16)

let z = 32
z /= 4
assert.sameValue(z, 8)

let a = 32
a -= 2
assert.sameValue(a, 30)

a -= 1.5
assert.sameValue(a, 28.5)

// BUG: The parser cannot parse such high-precision floats.
assert.sameValue(x, 0.30000000000000004)
