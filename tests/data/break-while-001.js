// Break while loop with the `break` keyword
var i = 0

while (true == true) {
	i++
	console.log("Iteration", i)

	if (i > 32) {
		console.log("Reached >32 iterations, breaking loop.")
		break
	}
}
