with import <nixpkgs> { };

mkShell {
  nativeBuildInputs = [
    pkg-config
    simdutf
    gmp
    spidermonkey_128
    quickjs
    boa
  ];

  LD_LIBRARY_PATH = lib.makeLibraryPath [
    simdutf
    gmp.dev
  ];
}
