// Minimal reproduction of #32

function x() {
  return "hi there"
}

function y(value) {
  if (value == 4) {
    return "hi there"
  }
}
