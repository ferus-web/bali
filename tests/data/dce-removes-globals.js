/* A simple test case to see how the midtier's DCE acts when a global is involved */
var x = "yeehaw";
var i = 0;

function thing()
{
	i++;
}

for (var i = 0; i < 10000; i++) { thing() }
console.log(x, i)
