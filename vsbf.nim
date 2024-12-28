## This is a very simple binary format, aimed at game save serialisation.
## By using type information encoded we can catch decode errors and optionally invoke converters
## Say data was saved as a `Float32` but now is an `Int32` we can know this and do `int32(floatVal)`

import vsbf/[shared, decoders, encoders]
export skipSerialization, decoders, encoders

when isMainModule:
  import vsbf/dumper

  type
    MyObject = object
      x, y: int
      name: string
      age: int
      talents: array[6, string]
      children: seq[MyObject]
      pets: seq[string]
      letters: set[range['a'..'z']]
      dontSave {.skipSerialization.}: ref int

  proc `==`(a, b: MyObject): bool {.noSideEffect.} =
    system.`==`(a, b)

  var
    obj =
      MyObject(
        x: 100,
        y: 0,
        age: 42,
        name: "Jimbo",
        talents: ["Jumping", "Running", "", "", "pets", "age"],
        pets: @["Sam", "Diesel"],
        letters: {'a'..'z'},
        children: newSeq[MyObject](5),
        dontSave: new int
      )

  proc main() =
    var encoder = Encoder.init()
    encoder.serializeRoot(obj)
    writeFile("/tmp/test.vsbf", encoder.data)

    var
      fileData = readFile("/tmp/test.vsbf")
      theFile = @(fileData.toOpenArrayByte(0, fileData.high))
    let dataAddr = theFile[0].addr

    var decoder = Decoder.init(theFile)
    obj.dontSave = nil
    assert decoder.deserialize(MyObject) == obj
    decoder = Decoder.init(theFile)
    decoder.pos = headerSize
    echo decoder.dump()

    var buff = decoder.close()
    assert buff[0].addr == dataAddr # We are reusing the buffer!

    var buffer: array[1024, byte]
    buffer[0..fileData.high] = (fileData.toOpenArrayByte(0, fileData.high))
    var oaDecoder = Decoder.init(buffer)
    assert oaDecoder.deserialize(MyObject) == obj
    oaDecoder = Decoder.init(buffer)
    echo oaDecoder.dump()

  main()
