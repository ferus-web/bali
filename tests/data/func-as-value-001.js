function callSomething(x) {
	console.log(x)
	let v = x()
	console.log(v)
}

function cheezburgr() {
	return "can i haz cheezbrgur??"
}

callSomething(cheezburgr)
