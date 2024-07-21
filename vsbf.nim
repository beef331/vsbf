## This is a very simple binary format, aimed at game save serialisation.
## By using type information encoded we can catch decode errors and optionally invoke converters
## Say data was saved as a `Float32` but now is an `Int32` we can know this and do `int32(floatVal)`

import vsbf/[shared, decoders, encoders]

type
  MyObject = object
    x, y: int
    name: string
    age: int
    talents: array[4, string]
    children: seq[MyObject]
    pets: seq[string]
    letters: set[range['a'..'z']]

proc `==`(a, b: MyObject): bool {.noSideEffect.} =
  system.`==`(a, b)

let
  obj =
    MyObject(
      x: 0,
      y: 0,
      age: 42,
      name: "Jimbo",
      talents: ["Jumping", "Running", "", ""],
      pets: @["Sam", "Diesel"],
      letters: {'a'..'z'},
      children: newSeq[MyObject](5),
    )

proc main() =
  var encoder = Encoder.init(true)
  encoder.serialiseRoot(obj)
  encoder.save "/tmp/test.vsbf"
  encoder = Encoder.init(false)
  encoder.serialiseRoot(obj)
  encoder.save "/tmp/test1.vsbf"

  var
    fileData = readFile("/tmp/test.vsbf")
    theFile = @(fileData.toOpenArrayByte(0, fileData.high))
  let dataAddr = theFile[0].addr

  var decoder = Decoder.init(true, theFile)

  assert decoder.deserialiseRoot(MyObject) == obj
  var buff = decoder.close()
  assert buff[0].addr == dataAddr # We are reusing the buffer!

  fileData = readFile("/tmp/test1.vsbf")
  var buffer: array[1024, byte]

  buffer[0..fileData.high] = (fileData.toOpenArrayByte(0, fileData.high))
  var oaDecoder = Decoder.init(false, buffer)
  assert oaDecoder.deserialiseRoot(MyObject) == obj

main()
