import vsbf/[shared, decoders, encoders]
import std/unittest
import utils

var buffer = newSeq[byte]()
var decoder = default Decoder[seq[byte]]

const headerArr = @(header.toOpenArrayByte(0, headerSize - 1))

suite "Incorrectly Formatted Data":
  test "Missing Bool Data":
    decoder = Decoder.init(headerArr & Bool.byte)
    try:
      var b = default bool
      decoder.deserialize(b)
      doAssert false
    except VsbfError as e:
      check e.kind == InsufficientData
      check e.position == 7

  buffer = headerArr & Array.byte & leb(4i64)
  decoder = Decoder.init(buffer)

  test "Lacking array elements":
    try:
      var arr = default array[3, int]
      decoder.deserialize(arr)
      doAssert false
    except VsbfError as e:
      check e.kind == IncorrectData
      check e.position == 8

  buffer = headerArr & Array.byte & leb(3i64) & leb(100i64) & leb(100i64) & leb(100i64)

  decoder = Decoder.init(buffer)

  test "Missing type id":
    try:
      var arr = default array[3, int]
      decoder.deserialize(arr)
      doAssert true

    except VsbfError as e:
      check e.kind == IncorrectData
      check e.position == 8

  buffer = headerArr & Array.byte & leb(3i64) & Int64.byte & leb(100i64) &  Int64.byte & leb(100i64) &  Int64.byte & leb(100i64)

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



