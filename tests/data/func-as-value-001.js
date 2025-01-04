function callSomething(x) {
	console.log("Upon calling the given function, I got:", x())
}

function cheezburgr() {
	return "can i haz cheezbrgur??"
}

callSomething(cheezburgr)
