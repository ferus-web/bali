/* Test suite for validating identifier-bound anonymous functions
 *    pass the --test262 flag for the hooks to work!!!
 * 
 * Copyright (C) 2025 Trayambak Rai (xtrayambak at disroot dot org)
*/

const a = function() {
	assert.success("a() can be called")
};

const b = function() {
	a();
	assert.success("a() can be called from b()");
};

const c = function() {
	var i = 0;
	while (i < 4) {
		i++
		console.log("c iter ", i)
	}

	assert.success("c() can execute nested scopes inside it")
};

a();
b();
c();
