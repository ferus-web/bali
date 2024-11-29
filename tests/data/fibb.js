function fibb(n) {
	console.log(n)
	if (n < 1) {
		return n
	}

	let a = fibb(n - 1)
	let b = fibb(n - 2)
	let c = a + b

	return c
}

let fib = fibb(6)
console.log(fib)
