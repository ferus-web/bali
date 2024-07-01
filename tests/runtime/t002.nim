import bali/runtime/normalize

assert normalizeIRName("Math.random") == "Mathdotrandom"
assert normalizeIRName("console.log") == "consoledotlog"
assert normalizeIRName("myfunction123") == "myfunctiononetwothree"
