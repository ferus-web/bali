/* 
	* Bali's test suite for the ECMAScript Set type
	* Requires the --test262 flag to be passed!
	*
	* Copyright (C) 2025 Trayambak Rai
*/

var x = new Set()

// Set.prototype.add()
x.add(32)
x.add(38)
x.add(87)
assert.sameValue(x.size(), 3)

// Set.prototype.delete()
assert.sameValue(x.delete(32), true)
assert.sameValue(x.size(), 2)
assert.sameValue(x.delete(1337), false)
assert.sameValue(x.size(), 2)

// Set.prototype.has()
assert.sameValue(x.has(32), false)
assert.sameValue(x.has(1337), false)
assert.sameValue(x.has(87), true)
assert.sameValue(x.has(32), false)
assert.sameValue(x.has("the last thing you want in your burger king burger"), false)

// Set.prototype.clear()
assert.sameValue(x.clear(), undefined)
assert.sameValue(x.size(), 0)
assert.sameValue(x.has(87), false)
