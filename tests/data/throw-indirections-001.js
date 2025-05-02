function e() { throw "BOOM" }
function d() { e() }
function c() { d() }
function b() { c() }
function a() { b() }

a()
