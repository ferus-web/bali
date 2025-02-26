var x = new String("Hello")

function thing() {
	console.log("mrrp :3")
}

x.toString = thing;

console.log(x.toString)
