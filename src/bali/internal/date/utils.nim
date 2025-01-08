## Implementations of date-related functions necessary for the JavaScript Date API
## Author(s): 
## Trayambak Rai (xtrayambak at disroot dot org)
import std/[math, times]
import bali/internal/date/constants
import bali/internal/sugar

func toDay*(t: float): int =
  ## The abstract operation Day takes argument t (a finite time value) and returns an integral Number. It returns the
  ## day number of the day in which t falls. It performs the following steps when called:
  
  int(
    floor(
      t / msPerDay
    )
  )

func toWeekDay*(t: float): int {.inline.} =
  ## The abstract operation WeekDay takes argument t (a finite time value) and returns an integral Number in the
  ## inclusive interval from +0𝔽 to 6𝔽. It returns a Number identifying the day of the week in which t falls. A weekday
  ## value of +0𝔽 specifies Sunday; 1𝔽 specifies Monday; 2𝔽 specifies Tuesday; 3𝔽 specifies Wednesday; 4𝔽 speci-
  ## fies Thursday; 5𝔽 specifies Friday; and 6𝔽 specifies Saturday

  # 1. Return 𝔽(ℝ(Day(t) + 4𝔽) modulo 7).
  int(
    (toDay(t) + 4) mod 7
  )

func getHourFromTime*(t: float): int {.inline.} =
  ## The abstract operation HourFromTime takes argument t (a finite time value) and returns an integral Number in
  ## the inclusive interval from +0𝔽 to 23𝔽. It returns the hour of the day in which t falls. It performs the following steps
  ## when called

  # 1. Return 𝔽(floor(ℝ(t / msPerHour)) modulo HoursPerDay).
  int(
    floor(
      t / msPerHour
    ) mod HoursPerDay
  )

func getDayFromYear*(y: int32): float =
  # 1. Let ry be ℝ(y).
  let ry = float(y)

  # 2. NOTE: In the following steps, each _numYearsN_ is the number of years divisible by N that occur between the
  #    epoch and the start of year y. (The number is negative if y is before the epoch.)

  let
    # 3. Let numYears1 be (ry - 1970).
    numYears1 = ry - 1970

    # 4. Let numYears4 be floor((ry - 1969) / 4).
    numYears4 = floor((ry - 1969) / 4)
    
    # 5. Let numYears100 be floor((ry - 1901) / 100).
    numYears100 = floor((ry - 1901) / 100)

    # 6. Let numYears400 be floor((ry - 1601) / 400).
    numYears400 = floor((ry - 1601) / 400)

  # Return 𝔽(365 × numYears1 + numYears4 - numYears100 + numYears400).
  365f * numYears1 + numYears4 - numYears100 + numYears400

func getTimeFromYear*(y: int32): float {.inline.} =
  float(msPerDay * getDayFromYear(y))

func getDaysInYear*(y: int32): uint16 =
  # 1. Let ry be ℝ(y).
  let ry = cast[float](y)

  # 2. If (ry modulo 400) = 0, return 366𝔽.
  if ry mod 400 == 0:
    return 366'u16

  # 3. If (ry modulo 100) = 0, return 365𝔽.
  if ry mod 100 == 0:
    return 365'u16

  # 4. If (ry modulo 4) = 0, return 366𝔽.
  if ry mod 4 == 0:
    return 366'u16

  # 5. Return 365𝔽.
  return 365'u16

func getYearFromTime*(t: float): int32 {.inline.} =
  ## The abstract operation YearFromTime takes argument t (a finite time value) and returns an integral Number. It
  ## returns the year in which t falls. It performs the following steps when called:

  # 1. Return the largest integral Number y (closest to +∞) such that TimeFromYear(y) ≤ t.
  if t == Inf:
    return int32.high()

  var year = int32(floor(t / (365.2425 * msPerDay) + 1970))
  
  let yearT = getTimeFromYear(year)
  if yearT > t:
    dec year
  elif (yearT + float(getDaysInYear(year).float * msPerDay)) <= t:
    inc year

  year

func inLeapYear*(t: float): bool {.inline.} =
  # 1. If DaysInYear(YearFromTime(t)) is 366𝔽, return true; else return false.
  getDaysInYear(getYearFromTime(t)) == 366'u16

func getDayWithinYear*(t: float): uint16 {.inline.} =
  if t == Inf:
    return 0'u16
  
  # 1. Return Day(t) - DayFromYear(YearFromTime(t)).
  uint16(toDay(t).float - getDayFromYear(getYearFromTime(t)))

func getMinuteFromTime*(t: float): uint8 {.inline.} =
  if t == Inf:
    return 0'u8

  uint8(floor(t / msPerMinute) mod MinutesPerHour)

func getSecondFromTime*(t: float): uint8 {.inline.} =
  if t == Inf:
    return 0'u8

  uint8(floor(t / msPerSecond) mod SecondsPerMinute)

func getMsecondsFromTime*(t: float): uint16 {.inline.} =
  if t == Inf:
    return 0'u8

  uint16(t mod msPerSecond)
  
func getMonthFromTime*(t: float): int {.inline.} =
  ## The abstract operation MonthFromTime takes argument t (a finite time value) and returns an integral Number in
  ## the inclusive interval from +0𝔽 to 11𝔽. It returns a Number identifying the month in which t falls. A month value of
  ## +0𝔽 specifies January; 1𝔽 specifies February; 2𝔽 specifies March; 3𝔽 specifies April; 4𝔽 specifies May; 5𝔽 speci-
  ## fies June; 6𝔽 specifies July; 7𝔽 specifies August; 8𝔽 specifies September; 9𝔽 specifies October; 10𝔽 specifies
  ## November; and 11𝔽 specifies December. Note that MonthFromTime(+0𝔽) = +0𝔽, corresponding to Thursday, 1
  ## January 1970. It performs the following steps when called:

  # 1. Let inLeapYear be InLeapYear(t)
  let inLeapYear = cast[uint8](inLeapYear(t))

  # 2. Let dayWithinYear be DayWithinYear(t).
  let dayWithinYear = getDayWithinYear(t)

  if dayWithinYear < 31:
    return 0

  if dayWithinYear < (59 + inLeapYear):
    return 1

  if dayWithinYear < (90 + inLeapYear):
    return 2

  if dayWithinYear < (120 + inLeapYear):
    return 3

  if dayWithinYear < (151 + inLeapYear):
    return 4

  if dayWithinYear < (181 + inLeapYear):
    return 5

  if dayWithinYear < (212 + inLeapYear):
    return 6

  if dayWithinYear < (243 + inLeapYear):
    return 7

  if dayWithinYear < (273 + inLeapYear):
    return 8

  if dayWithinYear < (304 + inLeapYear):
    return 9

  if dayWithinYear < (334 + inLeapYear):
    return 10

  assert(dayWithinYear < 365 + inLeapYear)

  return 11

func getDateFromTime*(t: float): uint8 {.inline.} =
  let
    inLeapYear = cast[uint8](inLeapYear(t))
    dayWithinYear = uint8(getDayWithinYear(t))
    month = getMonthFromTime(t)

  case month
  of 0:
    return dayWithinYear + 1
  of 1:
    return dayWithinYear - 30
  of 2:
    return dayWithinYear - 58 - inLeapYear
  of 3:
    return dayWithinYear - 89 - inLeapYear
  of 4:
    return dayWithinYear - 119 - inLeapYear
  of 5:
    return dayWithinYear - 150 - inLeapYear
  of 6:
    return dayWithinYear - 180 - inLeapYear
  of 7:
    return dayWithinYear - 211 - inLeapYear
  of 8:
    return dayWithinYear - 242 - inLeapYear
  of 9:
    return uint8(dayWithinYear - 272 - inLeapYear)
  of 10:
    return uint8(dayWithinYear - 303 - inLeapYear)
  of 11:
    return uint8(dayWithinYear - 333 - inLeapYear)
  else: unreachable
