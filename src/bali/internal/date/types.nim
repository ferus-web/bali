import std/[options]

type
  Date* = object
    ## Bali's internal representation of a Date.
    year*: uint16
    month*: uint8
    day*: uint8
    hour*: uint8
    minute*: uint8
    second*: uint8
    millisecond*: uint32
    offset*: Option[uint16]

func date*(
  year: uint16,
  month, day, hour, minute, second: uint8,
  millisecond: uint32, offset: Option[uint16] = none(uint16)
): Date {.inline.} =
  Date(
    year: year,
    month: month, day: day, hour: hour, minute: minute,
    second: second, millisecond: millisecond, offset: offset
  )
