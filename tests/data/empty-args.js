/* Passing no arguments to functions/constructors that should normally have arguments.
 * This is mostly just a test for our new `argument` mechanism.
*/

try {
	var x = new URL()
	console.log("Failed");
} catch (err) {
	console.log("Success")
}
