with import <nixpkgs> { };

mkShell {
  nativeBuildInputs = [
    pkg-config
    simdutf
    gmp
    nodejs_22
    quickjs
  ];

  LD_LIBRARY_PATH = lib.makeLibraryPath [
    simdutf
    gmp.dev
  ];
}
