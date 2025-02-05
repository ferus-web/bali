## Small wrapper over ICU's `TimeZone` class
## Author: Trayambak Rai (xtrayambak at disroot dot org)
import std/[options, logging]
import pkg/icu4nim
import bali/internal/sugar

when defined(baliStaticallyLinkLibICU):
  {.passC: "-static".}

var cachedSystemTimeZone: Option[string]

proc getCurrentTimeZone*(): string =
  debug "getCurrentTimeZone: returning system timezone"
  if *cachedSystemTimeZone:
    debug "getCurrentTimeZone: hit cache, returning cached timezone"
    return &cachedSystemTimeZone

  var status = ZeroError

  var tz = detectHostTimeZone()
  if tz == nil:
    warn "getCurrentTimeZone: `icu::TimeZone::detectHostTimeZone()` returned NULL!"
    warn "getCurrentTimeZone: returning \"UTC\" as timezone."
    return "UTC"

  var timeZoneId: UnicodeString
  tz.getID(timeZoneId)
  debug "getCurrentTimeZone: timeZoneId = " & $timeZoneId

  var timeZoneName: UnicodeString
  tz.getCanonicalID(timeZoneId, timeZoneName, status)
  debug "getCurrentTimeZone: timeZoneName = " & $timeZoneName

  if status != ZeroError:
    warn "getCurrentTimeZone: ICU returned error code: " & $status
    warn "getCurrentTimeZone: returning \"UTC\" as timezone."
    return "UTC"

  cachedSystemTimeZone = some($timeZoneName)
  $timeZoneName

proc clearSystemTimeZoneCache*() {.sideEffect.} =
  debug "timezone: cleared system timezone cache"
  cachedSystemTimeZone.reset()
