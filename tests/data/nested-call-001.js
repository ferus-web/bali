function a()
{
	return "Hello nested calls!"
}

function b(msg)
{
	return msg
}

function c(msg)
{
	console.log("a() says:", msg)
}

c(b(a()))
