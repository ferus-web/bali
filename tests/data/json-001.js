let bob = JSON.parse('{"age": 25, "interests": ["Programming", "Listening to Music", "Breaking Things", 1337]}')
console.log(bob.age)
console.log(bob.interests)
assert.sameValue(bob.age, 25)

let serialized = JSON.stringify(bob)
console.log(serialized)
