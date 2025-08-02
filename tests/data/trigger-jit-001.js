// this source file attempts to trigger bali's JIT compiler

function y()
{
	console.log("y is called!")
	return 1337
}

function x() {
	let useless_work = 5;
	let other_thing = 8;
	let val = y()
}

var i = 0;
while (i < 10000)
{
	i++
	x() // do totally valid and not useless work
}

console.log("done")
