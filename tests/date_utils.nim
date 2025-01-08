import std/times
import bali/stdlib/date

float(
  cast[Duration](
    getTime().inZone(
      utc()
    ).toTime()
  ).inMilliseconds()
).toDateString.echo
