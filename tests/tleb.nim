import vsbf/shared
import std/unittest

suite "Leb128 testing":
  var buffer: array[16, byte]
  test "16bit unsigned check":
    for i in 0u16..uint16.high:
      let wrote = buffer.writeLeb128(i)
      var test = default uint16
      check buffer.readLeb128(test) == wrote
      check test == i


  test "16bit signed check":
    for i in int16.low..int16.high:
      let wrote = buffer.writeLeb128(i)
      var test = default int16
      check buffer.readLeb128(test) == wrote
      check test == i
