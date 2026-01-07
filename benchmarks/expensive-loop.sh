#!/usr/bin/env sh
# Checking how well Bali, SpiderMonkey, Boa and QuickJS can run an expensive loop
# Boa times out, so it is not included.
hyperfine "./balde tests/data/iterate-for-no-reason-001.js" "./balde tests/data/iterate-for-no-reason-001.js --disable-jit" "qjs tests/data/iterate-for-no-reason-001.js" --shell=none --warmup=10
