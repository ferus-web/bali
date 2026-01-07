#!/usr/bin/env sh
# Checking how many times Bali, SpiderMonkey, Boa and QuickJS can search a medium-sized string for a needle.
hyperfine "./balde tests/data/string-find-001.js --disable-jit" "./balde tests/data/string-find-001.js" "qjs tests/data/string-find-001.js" --shell=none --warmup=100
