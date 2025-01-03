let x = [5, 4, "hi", 5, ["This", "is", "a", "nested", "array"]]
let elem = x[0]
console.log(elem)

let a = x[1]
console.log(a)

let b = x[2]
console.log(b)

let c = x[3]
console.log(c)

let d = x[4]
console.log(d)

let e = x[5]
console.log(e)

let f = x[
	3 // This comment right here just uncovered a small bug in the parser - the array index code doesn't ignore comments properly!
]
console.log("quirky array access:", f)

let y = [
	2, 3, // Comedically placed comment
	":3",
	"minecraft was a warning" // hit em when they least expect it
]
console.log(y)
