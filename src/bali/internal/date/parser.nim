## Very cool date parser
## Mostly based off of Ladybird/LibJS's implementation

import std/[logging, options, strutils, times]
import bali/internal/[generic_lexer, trim_string, sugar]

proc parseSimplifiedISO8601*(date: string): Option[float] =
  ## 21.4.3.2 Date.parse ( string ), https://tc39.es/ecma262/#sec-date.parse

  # TODO: Make this function less complex. The static analyzer shouts at us when it sees this function.
  var lexer = newGenericLexer(date)

  var year, month, day, hours, minutes, seconds, milliseconds: Option[int]
  var timezone: Option[char]
  var timezoneHours, timezoneMinutes: Option[int]

  proc lexYear(): bool =
    if lexer.consumeSpecific('+'):
      year = lexer.lexNDigits(6)
      return *year

    if lexer.consumeSpecific('-'):
      var absYear: Option[int]
      if (absYear = lexer.lexNDigits(6); !absYear):
        return false

      if &absYear == 0:
        return false

      year = some(-(&absYear))

    result = (year = lexer.lexNDigits(4); *year)

  proc lexMonth(): bool =
    month = lexer.lexNDigits(2)
    return *month and &month >= 1 and &month <= 12

  proc lexDay(): bool =
    day = lexer.lexNDigits(2)
    return *day and &day >= 1 and &day <= 31

  proc lexDate(): bool =
    return
      lexYear() and (
        lexer.consumeSpecific('-') and
        (lexMonth() and (not lexer.consumeSpecific('-') or lexDay()))
      )

  proc lexHoursMinutes(oHours, oMinutes: var Option[int]): bool =
    var h, m: Option[int]
    if (h = lexer.lexNDigits(2); *h and &h >= 0 and &h <= 24) and
        lexer.consumeSpecific(':') and
        (m = lexer.lexNDigits(2); *m and &m >= 0 and &m <= 59):
      oHours = ensureMove(h)
      oMinutes = ensureMove(m)
      return true

  proc lexSeconds(): bool =
    seconds = lexer.lexNDigits(2)

    return *seconds and &seconds >= 0 and &seconds <= 59

  proc lexMilliseconds(): bool =
    # Date.parse() is allowed to accept an arbitrary number of implementation-defined formats.
    # Milliseconds are parsed slightly different as other engines allow effectively any number of digits here.
    # We require at least one digit and only use the first three.

    var digitsRead = 0
    var res = 0

    while not lexer.eof and lexer.peek().isAlphaAscii():
      let ch = lexer.consume()
      if digitsRead < 3:
        res = 10 * res + int(((uint8) ch) - (uint8) '0')

      inc digitsRead

    if digitsRead == 0:
      return false

    while digitsRead < 3:
      # If we got less than three digits pretend we have trailing zeros.
      res *= 10
      inc digitsRead

    milliseconds = some(res)

  proc lexSecondsMilliseconds(): bool =
    return lexSeconds() and (not lexer.consumeSpecific('.') or lexMilliseconds())

  proc lexTimezone(): bool =
    if lexer.consumeSpecific('+'):
      timezone = some('+')
      return lexHoursMinutes(timezoneHours, timezoneMinutes)

    if lexer.consumeSpecific('-'):
      timezone = some('-')
      return lexHoursMinutes(timezoneHours, timezoneMinutes)

    if lexer.consumeSpecific('Z'):
      timezone = some('Z')

    return true

  proc lexTime(): bool =
    return
      lexHoursMinutes(hours, minutes) and
      (not lexer.consumeSpecific(':') or lexSecondsMilliseconds()) and lexTimezone()

  if not lexDate() or lexer.consumeSpecific('T') and not lexTime() or lexer.eof:
    return

  # We parsed a valid simplified ISO 8601 string
  if !year:
    warn "date: date string has no year component"
    return

  var time = dateTime(
    &year,
    Month(month &| 1),
    day &| 1,
    hours &| 0,
    minutes &| 0,
    seconds &| 0,
    milliseconds &| 0,
  )

  # "When the UTC offset representation is absent, date-only forms are interpreted as a UTC time and date-time forms are interpreted as a local time."
  if !timezone and *hours:
    time = time.inZone(utc())

  var timeMs = time.toTime().toUnixFloat()

  if *timezone:
    case &timezone
    of '-':
      timeMs += float(&timezoneHours * 3_600_000 + &timezoneMinutes * 60_000)
    of '+':
      timeMs -= float(&timezoneHours * 3_600_000 + &timezoneMinutes * 60_000)
    else:
      unreachable

  some(timeMs)

proc parseDate*(date: string, isLocalTime: bool): float =
  var isLocalTime = true
  var offset = 0
  var dateString = date

  # Trim leading whitespace.
  dateString = dateString.internalTrim(strutils.Whitespace, TrimMode.Left)
