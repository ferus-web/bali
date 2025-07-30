// this source file attempts to trigger bali's JIT compiler

function x() {
	let useless_work = 5 + 5;
}

var i = 0;
while (i < 10000)
{
	x() // do totally valid and not useless work
}
