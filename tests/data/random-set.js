var x = new Set;
var total = 0;

for (var i = 0; i < 9999; i++)
{
	let v = Math.random()
	x.add(v)
	total++
}

console.log("Total:", total)
console.log("Set size:", x.size())

let sz = x.size()
let duplicated = total - sz
console.log("Duplicated:", duplicated)

let dup = duplicated / total
let dup2 = dup * 100

console.log("Duplicated%: ", dup2)
