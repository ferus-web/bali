function main()
{
	let x = new String();

	for (var i = 0; i < 32; i++) {
		let r = Math.random();
		let corrected = Math.floor(r * 100);
		x = x.concat(corrected + " ")
	}

	console.log(x)
}

for (var i = 0; i < 32768; i++) { main(); }
