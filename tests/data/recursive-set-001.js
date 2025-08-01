let x = new Set;
x.add(x)

assert.sameValue(x.toString(), "[object Set]")
