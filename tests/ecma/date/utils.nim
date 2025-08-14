## Test suite for the Date ECMAScript routines, which are used by Bali to implement
## the JavaScript Date API.
##
## Copyright (C) 2025 Trayambak Rai (xtrayambak at disroot dot org)
import std/unittest
import pkg/bali/internal/date/utils

suite "ECMAScript Date routines":
  test "toWeekDay(float)":
    check(toWeekDay(0) == 4)
    check(toWeekDay(1) == 4)
    check(toWeekDay(1755174291421f) == 4)

  test "getYearFromTime(float)":
    check(getYearFromTime(0) == 1970)
    check(getYearFromTime(1755174291421f) == 2025)
