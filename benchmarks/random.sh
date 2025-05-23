#!/usr/bin/env sh

build() {
	local ALG="$1"

	make RELEASE=1 NIMFLAGS="--define:BaliRNGAlgorithm=$ALG" > /dev/null 2>&1
}

run() {
	local ALG="$1"
	build $ALG

	echo "===== $ALG ====="
	time ./bin/balde tests/data/rand-loop.js
}

run "marsaglia"
run "xoroshiro128"
run "xoroshiro128pp"
run "xoroshiro128ss"
run "mersenne_twister"
run "marsaglia"
run "pcg"
run "lehmer"
run "splitmix"
