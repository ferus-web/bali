with import <nixpkgs> { };

mkShell {
  nativeBuildInputs = [
    pkg-config
    simdutf
    nodejs_22
    quickjs
  ];

  LD_LIBRARY_PATH = lib.makeLibraryPath [
    simdutf
  ];
}
