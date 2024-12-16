// If the capture rules are implemented correctly, value will be `0` after calling thing() as well, since the function
// is passed a copy of the variable and not given permission to modify the atom at the base address itself

function thing(x) { 
	x ++ 
	console.log("thing() thinks x is:", x)
}

let value = 0
console.log("value before calling thing():", value)
thing(value)
console.log("value after calling thing():", value)
