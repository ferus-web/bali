// A bunch of stuff for the Date prototype
// Make sure to pass the `--test262` flag!

let x = new Date(0)
assert.sameValue(x.getYear(), 70) // Is it the year of our lord, 197- ahem, 70? (This returns the years passed since 1900, it's so stupid... we didn't even have proper beep boop computers back then and the charles cabbage guy had died smh my head)
assert.sameValue(x.getDay(), 4) // It was a Thursday, which is the 4th day here because we're weirdos
assert.sameValue(x.getFullYear(), 1970) // Oh hey, the year of our lord, 1970
assert.sameValue(x.getDate(), 1)
