let str = '{"age": 25, "interests": ["Programming", "Listening to Music", "Breaking Things", 1337]}'
let bob = JSON.parse(str)
let interestsShouldBe = ["Programming", "Listening to Music", "Breaking Things", 1337]
assert.sameValue(bob.age, 25)

let serialized = JSON.stringify(bob)
assert.sameValue(str, serialized)
