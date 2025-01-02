import std/[strutils]
import bali/internal/date/types
import bali/internal/trim_string

const
  WeekdayName* = [
    "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"
  ]

  MonthName* = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
  ]

  MonthFullName* = [
    "January", "February", "March", "April", "May", "June", 
    "July", "August", "September", "October", "November", "December"
  ]

  firstDayOfMonth* = (
    common: [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334],
    leap:   [0, 31, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335]
  )
  
  daysInMonths* = [
    31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31
  ]

proc parseDate*(date: string, isLocalTime: bool): Date =
  var isLocalTime = true
  var offset = 0
  var dateString = date

  # Trim leading whitespace.
  dateString = dateString.internalTrim(strutils.Whitespace, TrimMode.Left)
