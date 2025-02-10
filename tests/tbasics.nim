import vsbf/[shared, decoders, encoders]
import std/[unittest, options]
import utils

let data = @(
    @(header.toOpenArrayByte(0, headerSize - 1)) &
    Bool.byte & true.byte &
    Int8.byte & cast[byte](int8.high) &
    Int16.byte & leb(int16.high) &
    Int32.byte & leb(int32.high) &
    Int64.byte & leb(int64.high) &
    Float32.byte & cast[array[4, byte]](float32.high) &
    Float64.byte & cast[array[8, byte]](float64.high) &
    String.byte & leb(0i64) & leb("hello world".len.int64) & "hello world" &
    Option.byte & 0u8 &
    Option.byte & 1u8 & Int8.byte & cast[byte](int8.high) &
    Option.byte & 1u8 & Int16.byte & leb(int16.high) &
    Option.byte & 1u8 & Int32.byte & leb(int32.high) &
    Option.byte & 1u8 & Int64.byte & leb(int64.high) &
    Struct.byte & Int32.encoded(true) & leb(1i64) & leb("test".len.int64) & "test" & leb(int32.low.int64) &
    Int64.encoded(true) & leb(2i64) & leb("other".len.int64) & "other" & leb(int64.low.int64) & EndStruct.byte

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
check decoder.deserialize(options.Option[int]) == none(int)
check decoder.deserialize(options.Option[int8]) == some int8.high
check decoder.deserialize(options.Option[int16]) == some int16.high
check decoder.deserialize(options.Option[int32]) == some int32.high
check decoder.deserialize(options.Option[int64]) == some int64.high
check decoder.deserialize(tuple[test: int32, other: int64]) == (int32.low.int32, int64.low.int64)


type 
  MyTypeA = object
    a, b: int
  MyTypeB = object
    a, b: int
    c: string = "hello travellers"

var encoder = Encoder.init()
encoder.serializeRoot(MyTypeA(a: 100, b: 200))

decoder = Decoder.init(encoder.dataBuffer)

suite "Defaults":
  check decoder.deserialize(MyTypeB) == MyTypeB(a: 100, b: 200)
