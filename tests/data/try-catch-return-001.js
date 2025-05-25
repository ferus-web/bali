function main()
{
	try {
		throw "YOLOOOOOO"
		return false
	}
	catch (e)
	{
		return true
	}

	return false
}

let x = main()
assert.sameValue(x, 1)
