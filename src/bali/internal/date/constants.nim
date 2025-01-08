## These constants are referenced by algorithms in the following sections.
## HoursPerDay = 24
## MinutesPerHour = 60
## SecondsPerMinute = 60
## msPerSecond = 1000𝔽
## msPerMinute = 60000𝔽 = msPerSecond × 𝔽(SecondsPerMinute)
## msPerHour = 3600000𝔽 = msPerMinute × 𝔽(MinutesPerHour)
## msPerDay = 86400000𝔽 = msPerHour × 𝔽(HoursPerDay)

const
  HoursPerDay* = 24f
  MinutesPerHour* = 60f
  SecondsPerMinute* = 60f
  msPerSecond* = 1000f
  msPerMinute* = 60000f
  msPerHour* = 3600000f
  msPerDay* = 86400000f

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

