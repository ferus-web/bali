let i = 32
let ityp = typeof i
console.log(ityp, i)

let x = new String(i)
let xtyp = typeof x
console.log(xtyp, x)

let value = x.toString()
let valuetyp = typeof value
console.log(valuetyp, value)

let parsed = parseInt(value)
if (parsed == i) {
	console.log("Yay! 32 == 32!")
} else {
	throw "32 != 32, weird!"
}
