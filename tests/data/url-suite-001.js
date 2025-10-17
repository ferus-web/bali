/* Comprehensive URL test suite for Bali
 * 
 * Bali internally uses nim-url for URL parsing. That library
 * can handle the vast majority of URLs, since it closely adheres
 * to the WHATWG spec (and it's mostly a Nim rewrite of ada-url,
 * which is used in Node.js, among other places)
*/

function basicUrlTests()
{
	console.log("Basic/Trivial URL tests");
	let x = new URL("https://google.com:443/search?query=thing#cute-fragment");
	
	assert.sameValue(x.protocol, "https:");
	assert.sameValue(x.hostname, "google.com");
	assert.sameValue(x.pathname, "/search");
	assert.sameValue(x.port, 443);
	assert.sameValue(x.search, "query=thing");
	assert.sameValue(x.hash, "#cute-fragment");

	try
	{
		// Something that's certainly _NOT_ a URL.
		let thing = new URL(".cvxmrw;/ewqsd.13pez-['");
		assert.fail("URL constructor throws error on failure");
	} catch (error)
	{
		assert.success("URL constructor throws error on failure");
	}
}

function opaqueTests()
{
	console.log("Opaque URL tests")
	let x = new URL("mailto:xtrayambak@gmail.com");
	
	assert.sameValue(x.protocol, "mailto:")
	assert.sameValue(x.hostname, undefined);
	assert.sameValue(x.pathname, "xtrayambak@gmail.com");
	assert.sameValue(x.port, undefined);
	assert.sameValue(x.search, undefined);
	assert.sameValue(x.source, "mailto:xtrayambak@gmail.com");
	assert.sameValue(x.origin, "mailto:xtrayambak@gmail.com");
	assert.sameValue(x.hash, undefined);
}

basicUrlTests();
opaqueTests();
