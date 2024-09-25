// Used for the benchmark.
let x = btoa("Both NodeJS's base64 module and Bali's builtin base64 module use simdutf. How much do they differ in terms of speed?")
let y = atob("QmFsaSBpcyBuZWF0LCBJIGd1ZXNzLiAoSWdub3JlIHRoZSBmYWN0IHRoYXQgYSBCYWxpIGRldmVsb3BlciB3cm90ZSB0aGlzIHRlc3Qp")

console.log(x)
console.log(y)
