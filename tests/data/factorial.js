function iterative_fac(n)
{
	let sum = 1;
	for (var i = 1; i <= n; i++)
	{
		sum *= i
	}

	return sum;
}

for (var i = 0; i <= 256; i++)
{
	let y = iterative_fac(i) // FIXME: Putting this in there prints: "fac of <num> = undefined"
	console.log("fac of", i, "=", y)
}
