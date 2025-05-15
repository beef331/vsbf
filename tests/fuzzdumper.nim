import
  pkg/bear,
  vsbf,
  vsbf/dumper,
  std/[unittest, random]


proc main() =
  fuzzy(100):
    var a: ref It
    new a
    var rand = initRand()
    a[].fillit(rand)
    var encoder = Encoder.init()
    encoder.serialize(a[], "")
    var decoder = Decoder.init(encoder.close())
    try:
      {.cast(gcSafe).}:
        echo decoder.dump()
    except:
      assert false
main()

