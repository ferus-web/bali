import std/times
import bali/stdlib/date

0.toDateString.echo

float(
  cast[Duration](
    getTime().inZone(
      utc()
    ).toTime()
  ).inMilliseconds()
).toDateString.echo
