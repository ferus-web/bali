function fibb(n) {
	if (n == 0) {
		return n
	}

	let a = fibonacci(n - 1)
	let b = fibonacci(n - 2)
	let c = a + b

	return c
}

let fib = fibb(6)
console.log(fib)
