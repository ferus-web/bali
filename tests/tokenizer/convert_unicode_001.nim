import std/[unicode, unittest]
import unicodedb/casing
import simdutf/unicode

let rune = Rune(23)
echo rune.toUtf8().repr
echo "#".runeAt(0).toUtf8()
