# Compare how fast base64 is decoded and encoded by NodeJS (V8) and Balde (Bali)

echo "Compiling Balde..." &&
nimble balde && echo "Compiled Balde successfully." &&
time ./balde run data/b64_encode_decode.js &&
time node data/b64_encode_decode.js
