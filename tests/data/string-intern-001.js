// Optimization Opportunity: Instead of allocating this string 99999 times, why not just allocate it outside the loop's body?

var i = 0

while (i < 99999)
{
	i++
}
