## Implementation of the `Date` object
##
## Author(s): 
## Trayambak Rai (xtrayambak at disroot dot org)
import std/[math, strformat, times, logging]
import bali/internal/sugar
import bali/stdlib/errors
import mirage/atom
import bali/runtime/[normalize, atom_helpers, arguments, types, bridge]
import bali/runtime/abstract/coercion
import bali/internal/date/[utils, constants, parser]

## 21.4.1.1 Time Values and Time Range
## Time measurement in ECMAScript is analogous to time measurement in POSIX, in particular sharing definition in terms of the proleptic Gregorian calendar, an epoch of midnight at the beginning of 1 January 1970 UTC, and an accounting of every day as comprising exactly 86,400 seconds (each of which is 1000 milliseconds long).
## An ECMAScript time value is a Number, either a finite integral Number representing an instant in time to millisecond precision or NaN representing no specific instant. A time value that is a multiple of 24 × 60 × 60 × 1000 = 86,400,000 (i.e., is 86,400,000 × d for some integer d) represents the instant at the start of the UTC day that follows the epoch by d whole UTC days (preceding the epoch for negative d). Every other finite time value t is defined relative to the greatest preceding time value s that is such a multiple, and represents the instant that occurs within the same UTC day as s but follows it by (t - s) milliseconds.
## Time values do not account for UTC leap seconds—there are no time values representing instants within positive leap seconds, and there are time values representing instants removed from the UTC timeline by negative leap seconds. However, the definition of time values nonetheless yields piecewise alignment with UTC, with discontinuities only at leap second boundaries and zero difference outside of leap seconds.
## A Number can exactly represent all integers from -9,007,199,254,740,992 to 9,007,199,254,740,992 (21.1.2.8 and 21.1.2.6). A time value supports a slightly smaller range of -8,640,000,000,000,000 to 8,640,000,000,000,000 milliseconds. This yields a supported time value range of exactly -100,000,000 days to 100,000,000 days relative to midnight at the beginning of 1 January 1970 UTC.
## The exact moment of midnight at the beginning of 1 January 1970 UTC is represented by the time value +0𝔽.

type JSDate* = object
  `@ epoch`*: float
  `@ invalid`*: bool = false

proc parseDateString(runtime: Runtime, dateString: string): float =
  if dateString.len < 1:
    return NaN

  if (let time = parseSimplifiedISO8601(dateString); *time):
    return &time

  warn "date: TODO: implementation-specific date formats are not supported"
  # TODO: Implement implementation-specific formats. For instance,
  #       Firefox and Chrome support "DD/MM/YYYY HH:mm AM/PM +TZ"
  #       The spec isn't very clear on this, so it's best to implement
  #       only a few of these.
  NaN

proc dateToString*(tv: float): string =
  ## The abstract operation DateString takes argument tv (a Number, but not NaN) and returns a String. It performs
  ## the following steps when called:

  # 1. Let weekday be the Name of the entry in Table 63 with the Number WeekDay(tv).
  let weekDay = WeekdayName[toWeekDay(tv)]

  # 2. Let month be the Name of the entry in Table 64 with the Number MonthFromTime(tv).
  let month = MonthName[getMonthFromTime(tv)]

  # 3. Let day be ToZeroPaddedDecimalString(ℝ(DateFromTime(tv)), 2).
  let day = fmt"{getDateFromTime(tv):02d}"

  # 4. Let yv be YearFromTime(tv).
  let year = getYearFromTime(tv)

  # 5. If yv is +0𝔽 or yv > +0𝔽, let yearSign be the empty String; otherwise, let yearSign be "-".
  let yearSign =
    if year >= 0:
      newString(0)
    else:
      "-"

  # 6. Let paddedYear be ToZeroPaddedDecimalString(abs(ℝ(yv)), 4).
  # 7. Return the string-concatenation of weekday, the code unit 0x0020 (SPACE), month, the code unit 0x0020 (SPACE), day, the code unit 0x0020 (SPACE), yearSign, and paddedYear.
  fmt"{weekday} {month} {day} {yearSign}{abs(year):04d}"

proc timeToString*(tv: float): string =
  # FIXME: non-compliant!
  let timeString =
    fmt"{getHourFromTime(tv):02d}:{getMinuteFromTime(tv):02d}:{getSecondFromTime(tv):02d}"

  timeString & " GMT"

proc toDateString*(tv: float): string =
  # 1. If tv is NaN, return "Invalid Date".
  if tv == NaN:
    return "Invalid Date"

  # FIXME: non-compliant!
  #        This should ideally call LocalTime(tv)
  let t = tv

  # FIXME: non-compliant!
  #        This should ideally also include the timezone string
  fmt"{dateToString(tv)} {timeToString(tv)}"

proc generateStdIR*(runtime: Runtime) =
  info "date: generating IR interfaces"

  runtime.registerType("Date", JSDate)
  runtime.defineConstructor(
    "Date",
    proc() =
      var dateValue: float

      # 2. Let numberOfArgs be the number of elements in values.
      # 3. If numberOfArgs = 0, then
      if runtime.argumentCount() == 0:
        # a. Let dv be SystemUTCEpochMilliseconds().
        # FIXME: I think this is... wrong.
        dateValue =
          float(cast[Duration](getTime().inZone(utc()).toTime()).inMilliseconds())
      # 4. Else if numberOfArgs = 1, then
      elif runtime.argumentCount() == 1:
        # a. Let value be values[0].
        let value = &runtime.argument(1, required = true)

        # FIXME: uncompliant.
        case value.kind
        of String:
          dateValue = runtime.parseDateString(&value.getStr())
        else:
          dateValue = runtime.ToNumber(value)

      var date = runtime.createObjFromType(JSDate)
      date.tag("epoch", dateValue)
      ret date
    ,
  )

  runtime.defineFn(
    JSDate,
    "now",
    proc() =
      let nowNs = inNanoseconds(cast[Duration](getTime()))

      # Return 𝔽(floor(nowNs / 10**6)).
      ret int(floor(nowNs / 1000000))
    ,
  )

  runtime.defineFn(
    JSDate,
    "parse",
    proc() =
      if runtime.argumentCount() < 1:
        ret NaN

      let dateString = runtime.ToString(&runtime.argument(1))

      ret runtime.parseDateString(dateString)
    ,
  )

  # B.2.3 Additional Properties of the Date.prototype Object
  runtime.definePrototypeFn(
    JSDate,
    "getYear",
    proc(value: MAtom) =
      ## B.2.3.1 Date.prototype.getYear ( )

      # 1. Let dateObject be the this value.
      let dateObject = value

      # 2. Perform ? RequireInternalSlot(dateObject, [[DateValue]]).
      assert(runtime.isA(dateObject, JSDate))

      # 3. Let t be dateObject.[[DateValue]].
      let time = runtime.ToNumber(&dateObject.tagged("epoch"))

      # 4. If t is NaN, return NaN.
      if time == NaN:
        ret NaN

      # 5. Return YearFromTime(LocalTime(t)) - 1900𝔽.
      # FIXME: This is uncompliant as it doesn't return the value in the local time.
      ret getYearFromTime(time) - 1900
    ,
  )

  # 21.4.4.1 Date.prototype.constructor
  runtime.definePrototypeFn(
    JSDate,
    "getFullYear",
    proc(value: MAtom) =
      ## 21.4.4.4 Date.prototype.getFullYear ( )

      # 1. Let dateObject be the this value.
      let dateObject = value

      # 2. Perform ? RequireInternalSlot(dateObject, [[DateValue]]).
      assert(runtime.isA(dateObject, JSDate))

      # 3. Let t be dateObject.[[DateValue]].
      let time = runtime.ToNumber(&dateObject.tagged("epoch"))

      # 4. If t is NaN, return NaN.
      if time == NaN:
        ret NaN

      # 5. Return YearFromTime(LocalTime(t)).
      ret getYearFromTime(time)
    ,
  )

  runtime.definePrototypeFn(
    JSDate,
    "toString",
    proc(value: MAtom) =
      ## 21.4.4.41 Date.prototype.toString ( )

      # 1. Let dateObject be the this value.
      let dateObject = value

      # 2. Perform ? RequireInternalSlot(dateObject, [[DateValue]])
      assert(runtime.isA(dateObject, JSDate))

      # 3. Let tv be dateObject.[[DateValue]].
      let time = runtime.ToNumber(&dateObject.tagged("epoch"))

      # 4. Return ToDateString(tv).
      ret toDateString(time)
    ,
  )

  runtime.definePrototypeFn(
    JSDate,
    "getDay",
    proc(value: MAtom) =
      ## 21.4.4.3 Date.prototype.getDay ( )

      # 1. Let dateObject be the this value.
      let dateObject = value

      # 2. Perform ? RequireInternalSlot(dateObject, [[DateValue]]).
      assert(runtime.isA(dateObject, JSDate))

      # 3. Let t be dateObject.[[DateValue]].
      let time = runtime.ToNumber(&dateObject.tagged("epoch"))

      # 4. If t is NaN, return NaN.
      if time == NaN:
        ret NaN

      # 5. Return WeekDay(LocalTime(t)).
      ret toWeekDay(time)
    ,
  )

  runtime.definePrototypeFn(
    JSDate,
    "getDate",
    proc(value: MAtom) =
      ## 21.4.4.3 Date.prototype.getDate ( )

      # 1. Let dateObject be the this value.
      let dateObject = value

      # 2. Perform ? RequireInternalSlot(dateObject, [[DateValue]]).
      assert(runtime.isA(dateObject, JSDate))

      # 3. Let t be dateObject.[[DateValue]].
      let time = runtime.ToNumber(&dateObject.tagged("epoch"))

      # 4. If t is NaN, return NaN.
      if time == NaN:
        ret NaN

      # 5. Return DateFromTime(LocalTime(t)).
      ret getDateFromTime(time)
    ,
  )
