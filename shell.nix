with import <nixpkgs> { };

mkShell {
  nativeBuildInputs = [
    pkg-config
    simdutf
    gmp
    icu76
    spidermonkey_128
    quickjs
    boa
    nph
    mimalloc
  ];

  LD_LIBRARY_PATH = lib.makeLibraryPath [
    simdutf
    gmp.dev
    icu76.dev
    mimalloc.dev
  ];
}
