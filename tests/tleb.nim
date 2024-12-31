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


  test "32bit unsigned values":
    const vals =
      [
        (wrote: 1, val: 0xfu32),
        (2, 0xffu32),
        (2, 0xfffu32),
        (3, 0xffffu32),
        (4, 0xffffffu32),
        (4, 0xffffffu32),
        (4, 0xfffffffu32),
        (5, 0xffffffffu32)
      ]

    for (expectedWrite, i) in vals:
      let wrote = buffer.writeLeb128(i)
      var test = default uint32
      check buffer.readLeb128(test) == wrote
      check i == test
      check expectedWrite == wrote


  test "32bit signed values":
    const vals =
      [
        (wrote: 1, val: 0xfi32),
        (2, 0xffi32),
        (2, 0xfffi32),
        (3, 0xffffi32),
        (4, 0xffffffi32),
        (4, 0xffffffi32),
        (5, 0xfffffffi32),
        (5, 0x7fffffffi32)
      ]

    for (expectedWrite, i) in vals:
      let wrote = buffer.writeLeb128(i)
      var test = default int32
      check buffer.readLeb128(test) == wrote
      check i == test
      check expectedWrite == wrote


  test "64bit unsigned values":
    const vals =
      [
        (wrote: 1, val: 0xfu64),
        (2, 0xffu64),
        (2, 0xfffu64),
        (3, 0xffffu64),
        (4, 0xffffffu64),
        (4, 0xffffffu64),
        (4, 0xfffffffu64),
        (5, 0xffffffffu64),
        (6, 0xf_ffffffffu64),
        (6, 0xff_ffffffffu64),
        (7, 0xfff_ffffffffu64),
        (7, 0xffff_ffffffffu64),
        (8, 0xfffff_ffffffffu64),
        (8, 0xffffff_ffffffffu64),
        (9, 0xfffffff_ffffffffu64),
        (10, 0xffffffff_ffffffffu64),
      ]

    for (expectedWrite, i) in vals:
      let wrote = buffer.writeLeb128(i)
      var test = default uint64
      check buffer.readLeb128(test) == wrote
      check i == test
      check expectedWrite == wrote


  test "64bit signed values":
    const vals =
      [
        (wrote: 1, val: 0xfi64),
        (2, 0xffi64),
        (2, 0xfffi64),
        (3, 0xffffi64),
        (4, 0xffffffi64),
        (4, 0xffffffi64),
        (5, 0xfffffffi64),
        (5, 0xffffffffi64),
        (6, 0xf_ffffffffi64),
        (6, 0xff_ffffffffi64),
        (7, 0xfff_ffffffffi64),
        (7, 0xffff_ffffffffi64),
        (8, 0xfffff_ffffffffi64),
        (9, 0xffffff_ffffffffi64),
        (9, 0xfffffff_ffffffffi64),
        (10, 0x7fffffff_ffffffffi64),
      ]

    for (expectedWrite, i) in vals:
      let wrote = buffer.writeLeb128(i)
      var test = default int64
      check buffer.readLeb128(test) == wrote
      check i == test
      check expectedWrite == wrote
