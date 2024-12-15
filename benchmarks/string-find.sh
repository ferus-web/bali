#!/usr/bin/env sh
# Checking how many times Bali, SpiderMonkey, Boa and QuickJS can search a medium-sized string for a needle.
hyperfine "./bin/balde tests/data/string-find-001.js" "js tests/data/string-find-001.js" "boa tests/data/string-find-001.js" "qjs tests/data/string-find-001.js" --shell=none --warmup=100
