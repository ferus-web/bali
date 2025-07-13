// Test case to see if a VM register gets leaked
// Run with --test262
function test(y)
{
	var x = new String("Hello there, ")
	x.concat(y) // This puts "Hello there, <y>" in the retval register.
}

let v = test("tray")
assert.sameValue(v, undefined)
