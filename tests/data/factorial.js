function fac(n, acc) {
	console.log("n:", n)
	console.log("acc:", acc)
	if (n == 0) {
		return acc;
	}

	let value = fac(n - 1, n * acc)
	return value
}

console.log(fac(5, 1))
