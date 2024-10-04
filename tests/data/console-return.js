let log = console.log("Does `console.log` return anything?")
assert.sameValue(log, undefined)

let warn = console.log("Does `console.warn` return anything?")
assert.sameValue(warn, undefined)

let error = console.log("Does `console.error` return anything?")
assert.sameValue(error, undefined)

let debug = console.log("Does `console.debug` return anything?")
assert.sameValue(debug, undefined)

console.log("Nice. Everything returns `undefined`, just as intended.")
