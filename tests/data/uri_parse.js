var url = new URL("https://google.com:65535") // this works.
var url = new URL("https:google.com") // this will throw a TypeError as the URL is malformed
var url = new URL("https://google.com:65536") // this will throw a TypeError as the port is outside of the valid range
