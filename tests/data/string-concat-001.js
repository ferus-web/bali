let x = new String("hello ")
let vals = [
	"world",
	"nerds",
	"folks",
	"readers"
]
var i = 0

while (i < 4)
{
	let val = vals[i]
	console.log(x.concat(val))
	i++
}
