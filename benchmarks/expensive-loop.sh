#!/usr/bin/env sh
# Checking how well Bali, SpiderMonkey, Boa and QuickJS can run an expensive loop
# Boa times out, so it is not included.
hyperfine "./bin/balde tests/data/iterate-for-no-reason-001.js" "./bin/balde tests/data/iterate-for-no-reason-001.js -Z" "qjs tests/data/iterate-for-no-reason-001.js" --shell=none --warmup=10
