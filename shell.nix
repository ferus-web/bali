with import <nixpkgs> { };

mkShell {
  nativeBuildInputs = [
    pkg-config
    simdutf
    gmp
    boehmgc
    icu76
    pcre
    nph
    quickjs
    boa
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
