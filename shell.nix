with import <nixpkgs> { };

mkShell {
  nativeBuildInputs = [
    pkg-config
    simdutf
    gmp
    boehmgc
    icu76
    spidermonkey_128
    quickjs
    boa
    pcre
    nph
    emscripten
    mimalloc
  ];

  LD_LIBRARY_PATH = lib.makeLibraryPath [
    simdutf
    gmp.dev
    icu76.dev
    pcre.dev
    boehmgc.dev
    mimalloc.dev
  ];
}
