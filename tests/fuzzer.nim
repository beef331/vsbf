import
  pkg/bear,
  vsbf,
  std/[unittest, random]


proc main() =
  fuzzy(100, 0):
    var a: ref It
    new a
    var rand = initRand()
    a[].fillit(rand)
    var encoder = Encoder.init()
    encoder.serialize(a[], "")
    var decoder = Decoder.init(encoder.close())
    var b = new It
    decoder.deserialize(b[])
    test "Compare":
      check b.fuzzCompare(a)

main()

