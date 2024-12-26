import vsbf/[shared, decoders, encoders]
import std/unittest

proc `&`(a, b: static openarray[char]): array[a.len + b.len, byte] =
  result = default typeof(result)
  for i, x in a.pairs:
    result[i] = byte x

  for i, x in b.pairs:
    result[i + a.len] = byte x

proc `&`(a, b: static openarray[byte]): array[a.len + b.len, byte] =
  result = default typeof(result)
  for i, x in a.pairs:
    result[i] = x

  for i, x in b.pairs:
    result[i + a.len] = x


proc `&`[IDX; T: char | byte](a: static openarray[char], b: array[IDX, T]): array[a.len + IDX, byte] =
  result = default typeof(result)
  for i, x in a.pairs:
    result[i] = byte x

  for i, x in b.pairs:
    result[i + b.len] = byte x

proc `&`[T: char | byte](a: static openArray[T], b: byte | char): array[a.len + 1, byte] =
  result = default typeof(result)
  for i, x in a.pairs:
    result[i] = byte x

  result[^1] = byte b



proc `&`[IDX; T](a: array[IDX, T], b: static openArray[byte]): array[a.len + b.len, byte] =
  result = default typeof(result)
  for i, x in a.pairs:
    result[i] = byte x

  for i, x in b.pairs:
    result[i + a.len] = byte x


proc `&`[IDX](a: array[IDX, byte], b: byte): array[a.len + 1, byte] =
  result = default typeof(result)
  for i, x in a.pairs:
    result[i] = byte x

  result[^1] = byte b

template leb(val: SomeInteger): untyped =
  var buffer = default array[10, byte]
  let len = buffer.writeLeb128(val)
  buffer.toOpenArray(0, len - 1)


var buffer = newSeq[byte]()
var decoder = default Decoder[seq[byte]]

suite "Incorrectly Formatted Data":
  test "Missing Bool Data":
    decoder = Decoder.init(@(header & Bool.byte))
    try:
      var b = default bool
      decoder.deserialize(b)
      doAssert false
    except VsbfError as e:
      check e.kind == InsufficientData
      check e.position == 7

  buffer = @(header & Array.byte & leb(4i64))
  decoder = Decoder.init(buffer)

  test "Lacking array elements":
    try:
      var arr = default array[3, int]
      decoder.deserialize(arr)
      doAssert false
    except VsbfError as e:
      check e.kind == IncorrectData
      check e.position == 8

  buffer = @(header & Array.byte & leb(3i64) & leb(100i64) & leb(100i64) & leb(100i64))

  decoder = Decoder.init(buffer)

  test "Missing type id":
    try:
      var arr = default array[3, int]
      decoder.deserialize(arr)
      doAssert true

    except VsbfError as e:
      check e.kind == IncorrectData
      check e.position == 8

  buffer = @(header & Array.byte & leb(3i64) & Int64.byte & leb(100i64) &  Int64.byte & leb(100i64) &  Int64.byte & leb(100i64))

  decoder = Decoder.init(buffer)

  test "Type mismatch":
    try:
      var arr = default array[3, int]
      decoder.deserialize(arr)
      doAssert true
      decoder = Decoder.init(buffer)

      var arr2 = default array[3, (int,)]
      decoder.deserialize(arr2)
      doAssert false

    except VsbfError as e:
      check e.kind == TypeMismatch
      check e.position == 9



