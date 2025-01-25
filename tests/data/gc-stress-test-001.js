/* This is just a simple stress test to see how well the GC handles constant referencing to the same atom
 * and discarding the change immediately
 * Make sure to run this with the --insert-debug-hooks flag!
*/

let a = new String("a")
a = new String(a.repeat(65536))

console.log(a)
