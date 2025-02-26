var x = new String("Hello")

function thing(str) {
	// This function is passed a JSValue that is internally represented as a boxed string
	console.log("mrrp :3")
}

x.toString = thing;

console.log(x.toString)
let v = x.toString()
console.log(v)
