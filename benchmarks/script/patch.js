/* Benchmark to use for mid-clause JIT patching
 * run with --disable-loop-elision for maximum CPU torture
 * 
 * Copyright (C) 2026 Trayambak Rai (xtrayambak@disroot.org)
*/

function expensiveLoop()
{
	var i = 0;
	while (i < 65536)
	{
		i++;
	}

	return i;
}

// NOTE: madhyasthal triggers at i < 1471
for (var i = 0; i < 65536; i++)
{
	expensiveLoop();
}
