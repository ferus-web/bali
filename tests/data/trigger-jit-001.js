// this source file attempts to trigger bali's JIT compiler

function x() {
	let useless_work = 5;
	let other_thing = 8;
	let other_thing = 8;
	let other_thing = 8;
	console.log(other_thing)
}

var i = 0;
while (i < 10000)
{
	i++
	x() // do totally valid and not useless work
}
