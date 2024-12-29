import vsbf/shared

template leb*(val: SomeInteger): untyped =
  var (buffer, len) = leb128(val)
  buffer.toOpenArray(0, len - 1)


proc `&`*(bytes: seq[byte], str: openArray[byte]): seq[byte] =
  result = bytes
  result.add @str

proc `&`*(bytes: seq[byte], str: openArray[char]): seq[byte] =
  bytes & str.toOpenArrayByte(0, str.high)

proc `&`*(bytes: seq[byte], byt: byte): seq[byte] =
  result = bytes
  result.add byt
