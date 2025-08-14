## Test suite for the Date parser
##
## Copyright (C) 2025 Trayambak Rai
import std/unittest
import pkg/bali/internal/date/parser, pkg/shakar

suite "ISO8601 Date parser":
  test "parse dates":
    check(&parseSimplifiedISO8601("2025-01-05T18:30:00") == 1736082000.0)
    check(&parseSimplifiedISO8601("2029-01-05T21:30:00") == 1862323200.0)

  test "erroneous inputs":
    check(!parseSimplifiedISO8601("wejrnewrnwdfndsfsdf"))
    check(!parseSimplifiedISO8601("28282822-99292-392:#:12:22:23"))
