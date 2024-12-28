import vsbf/[shared, decoders, encoders]
import std/unittest
import utils

suite "Basic types":
  let data = @(
      header &
      Bool.byte & true.byte &
      Int8.byte & cast[byte](int8.high) &
      Int16.byte & leb(int16.high) &
      Int32.byte & leb(int32.high) &
      Int64.byte & leb(int64.high) &
      Float32.byte & cast[array[4, byte]](float32.high) &
      Float64.byte & cast[array[8, byte]](float64.high) &
      String.byte & leb(0i64) & leb("hello world".len.int64) & "hello world"
    )
  var decoder = Decoder.init(data)

  check decoder.deserialize(bool) == true
  check decoder.deserialize(int8) == int8.high
  check decoder.deserialize(int16) == int16.high
  check decoder.deserialize(int32) == int32.high
  check decoder.deserialize(int64) == int64.high
  check decoder.deserialize(float32) == float32.high
  check decoder.deserialize(float64) == float64.high
  check decoder.deserialize(string) == "hello world"
