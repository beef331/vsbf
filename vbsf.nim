## This is a very simple binary format, aimed at game save serialisation.
## By using type information encoded we can catch decode errors and optionally invoke converters
## Say data was saved as a `Float32` but now is an `Int32` we can know this and do `int32(floatVal)`

import std/[streams, tables, typetraits, options]

const
  version = "\1\0"
  header = ['v', 's', 'b', 'f', version[0], version[1]]

type
  SerialisationType = enum
    CustomStart = 0 # 0..99 are reserved custom types
    CustomEnd = 99
    Bool = 100 ## Should always be 0 or 1
    Int8
    Int16
    Int32
    Int64
    Float32 ## Floats do not use `Int` types to allow transitioning to and from floats
    Float64
    String ## Strings are stored in a 'String section'
    Array
    Struct
    Option ## If the next byte is 0x1 you parse the internal otherwise you skip
    Reserved = 127 ## Highest number of builtin types, going past this will cause issues with how name tagging works.

  Encoder* = object
    strs: Table[string, int]
    strsBuffer*: Stream ## The string section, contains an array of `(len: leb128, data: UncheckedArray[char])`
    dataBuffer*: Stream ##
      ## The data section, first value should be the 'entry' and is a `typeId` that determines how all the data is parsed.
      ## In the future this may be enforced to be a `Struct` or custom type
    storeNames: bool ## Whether we set the first bit to high where applicable (struct fields)

  Decoder* = object
    strs*: seq[string] ## List of strings that are indexed by string indexes
    stream*: Stream
    useNames: bool
  VbsfError = object of ValueError

static:
  assert sizeof(SerialisationType) == 1 # Types are always 1
  assert SerialisationType.high.ord <= 127

proc `=destroy`(encoder: var Encoder) =
  try:
    encoder.strsBuffer.close()
    encoder.dataBuffer.close()
  except:
    discard
  `=destroy`(encoder.strs)
  `=destroy`(encoder.strsBuffer)
  `=destroy`(encoder.dataBuffer)

proc `=destroy`(decoder: var Decoder) =
  try:
    decoder.stream.close()
  except:
    discard
  `=destroy`(decoder.strs)
  `=destroy`(decoder.stream)



proc vsbfId*(_: typedesc[bool]): SerialisationType = Bool
proc vsbfId*(_: typedesc[int8 or uint8 or char]): SerialisationType = Int8
proc vsbfId*(_: typedesc[int16 or uint16]): SerialisationType = Int16
proc vsbfId*(_: typedesc[int32 or uint32]): SerialisationType = Int32
proc vsbfId*(_: typedesc[int64 or uint64]): SerialisationType = Int64
proc vsbfId*(_: typedesc[int or uint]): SerialisationType = Int64 # Always 64 bits to ensure compatibillity

proc vsbfId*(_: typedesc[float32]): SerialisationType = Float32
proc vsbfId*(_: typedesc[float64]): SerialisationType = Float64


proc vsbfId*(_: typedesc[string]): SerialisationType = String
proc vsbfId*(_: typedesc[openArray]): SerialisationType = Array
proc vsbfId*(_: typedesc[object or tuple]): SerialisationType = Struct
proc vsbfId*(_: typedesc[ref]): SerialisationType = Option

proc encoded*(serType: SerialisationType, storeName: bool): byte =
  if storeName: # las bit reserved for 'hasName'
    0b1000_0000u8 or byte(serType)
  else:
    byte(serType)

proc decodeType*(data: byte): tuple[typ: SerialisationType, hasName: bool] =
  result.hasName = (0b1000_0000u8 and data) > 0 # Extract whether the lastbit is set
  result.typ = cast[SerialisationType](data and 0b0111_1111)

proc writeLeb128*(stream: Stream, i: SomeUnsignedInt) =
  var
    val = ord(i)
    ranOnce = false
  while val != 0 or not ranOnce:
    var data = byte(val and 0b0111_1111)
    val = val shr 7
    if val != 0:
      data = 0b1000_0000 or data
    stream.write(data)
    ranOnce = true

proc writeLeb128*(stream: Stream, i: SomeSignedInt) =
  const size = sizeof(i)
  let isNegative = i < 0
  var
    val = i
    more = true
  while more:
    var data = byte(val and 0b0111_1111)
    val = val shr 7
    if isNegative:
      val = val or (not (0 shl (size - 7)))

    let isSignSet = (0x40 and data) != 0
    if (val == 0 and not isSignSet) or (val == -1 and isSignSet):
      more = false
    else:
      data = 0b1000_0000 or data
    stream.write(data)

type
  Leb128Operation = enum
    Read
    Peek

proc readLeb128*(stream: Stream, T: typedesc[SomeUnsignedInt], op: static Leb128Operation = Read): T =
  var shift = 0
  when op == Peek:
    var
      chars: array[10, char]
      pos = 0
    let theLen = stream.peekData(chars.addr, chars.len)

  while true:
    let theByte =
      when op == Read:
        stream.readUint8()
      else:
        if pos > theLen:
          raise (ref VbsfError)(msg: "Attempting to read a too large integer")
        let ind = pos
        inc pos
        byte chars[ind]
    result = result or (T(0b0111_1111u8 and theByte) shl T(shift))

    if (0b1000_0000u8 and theByte) == 0:
      break
    shift += 7

  if shift > sizeof(T) * 8:
    raise (ref VbsfError)(msg: "Got incorrect sized integer for given field type.")

proc readLeb128(stream: Stream, T: typedesc[SomeSignedInt], op: static Leb128Operation = Read): T =
  var shift = 0
  var theByte: byte
  when op == Peek:
    var
      chars: array[10, char]
      pos = 0
    discard stream.peekData(chars.addr, chars.len)

  template whileBody =
    theByte =
      when op == Read:
        stream.readUint8()
      else:
        let ind = pos
        inc pos
        byte chars[ind]
    result = result or T((0b0111_1111 and theByte) shl shift)
    shift += 7

  whileBody()

  while (0b1000_0000 and theByte) != 0:
    whileBody()

  if shift > sizeof(T) * 8:
    raise (ref VbsfError)(msg: "Got incorrect sized integer for given field type.")

  if (theByte and 0b0100_0000) == 0b0100_0000:
    result = result or (not(T(1)) shl shift)

proc typeNamePair*(dec: var Decoder): tuple[typ: SerialisationType, nameInd: options.Option[int]] =
  ## reads the type and name's string index if it has it
  let encodedType = dec.stream.readUint8()
  var hasName: bool
  (result.typ, hasName) = encodedType.decodeType()

  if hasName:
    result.nameInd = some(dec.stream.readLeb128(int))

proc peekTypeNamePair*(dec: var Decoder): tuple[typ: SerialisationType, nameInd: options.Option[int]] =
  ## peek the type and name's string index if it has it
  let encodedType = dec.stream.peekUint8()
  var hasName: bool
  (result.typ, hasName) = encodedType.decodeType()

  if hasName:
    let pos = dec.stream.getPosition()
    dec.stream.setPosition(pos + 1)
    result.nameInd = some(dec.stream.readLeb128(int, Peek))
    dec.stream.setPosition(pos)

proc getStr(dec: Decoder, ind: int): lent string =
  dec.strs[ind]

proc canConvertFrom(typ: SerialisationType, val: auto) =
  const expected = typeof(val).vsbfId()
  if typ != expected:
    raise (ref VbsfError)(msg: "Expected: " & $expected & " but got " & $typ)

proc cacheStr(encoder: var Encoder, str: sink string): int =
  withValue encoder.strs, str, val:
    result = val[]
  do:
    result = encoder.strs.len
    encoder.strsBuffer.writeLeb128 str.len
    encoder.strsBuffer.write str
    encoder.strs[str] = result

proc serialiseTypeInfo[T](encoder: var Encoder, val: T, name: sink string) =
  ## Stores the typeID and name if it's required(0b1xxx_xxxx if there is a name)
  encoder.dataBuffer.write T.vsbfId.encoded(encoder.storeNames and name.len > 0)
  if encoder.storeNames and name.len > 0:
    encoder.dataBuffer.writeLeb128 encoder.cacheStr(name)

proc serialise*(encoder: var Encoder, i: SomeInteger, name: string) =
  serialiseTypeInfo(encoder, i, name)
  encoder.dataBuffer.writeLeb128 i

proc deserialise*(dec: var Decoder, i: var SomeInteger) =
  let (typ, _) = dec.typeNamePair()
  canConvertFrom(typ, i)
  i = dec.stream.readLeb128(SomeInteger)

proc serialise*(encoder: var Encoder, f: SomeFloat, name: string) =
  serialiseTypeInfo(encoder, f, name)
  encoder.dataBuffer.write f

proc deserialise*(dec: var Decoder, f: var SomeFloat) =
  let (typ, _) = dec.typeNamePair()
  canConvertFrom(typ, f)
  dec.stream.read(f)

proc serialise*(encoder: var Encoder, str: sink string, name: string) =
  serialiseTypeInfo(encoder, str, name)
  encoder.dataBuffer.writeLeb128 encoder.cacheStr(str)

proc deserialise*(dec: var Decoder, str: var string) =
  let (typ, _) = dec.typeNamePair()
  canConvertFrom(typ, str)
  let ind = dec.stream.readLeb128(int)
  str = dec.getStr(ind)

proc serialise*[Idx, T](encoder: var Encoder, arr: sink array[Idx, T], name: string) =
  serialiseTypeInfo(encoder, arr, name)
  encoder.dataBuffer.writeLeb128 arr.len
  for val in arr.mitems:
    encoder.serialise(val, "")

proc deserialise*[Idx, T](dec: var Decoder, arr: var array[Idx, T]) =
  let (typ, _) = dec.typeNamePair()
  canConvertFrom(typ, arr)
  let len = dec.stream.readLeb128(int)
  if len > arr.len:
    raise (ref VbsfError)(msg: "Expected an array with a length equal to or less than '" & $arr.len & "', but got length of '" & $len & "'.")
  for i in 0..<len:
    dec.deserialise(arr[i])

proc serialise*[T](encoder: var Encoder, arr: sink seq[T], name: string) =
  serialiseTypeInfo(encoder, arr, name)
  encoder.dataBuffer.writeLeb128 arr.len
  for val in arr.mitems:
    encoder.serialise(val, "")

proc deserialise*[T](dec: var Decoder, arr: var seq[T]) =
  let (typ, _) = dec.typeNamePair()
  canConvertFrom(typ, arr)
  let len = dec.stream.readLeb128(int)
  arr = newSeq[T](len)
  for i in 0..<len:
    dec.deserialise(arr[i])

proc serialise*(encoder: var Encoder, obj: sink (object or tuple), name: string) =
  mixin serialise
  serialiseTypeInfo(encoder, obj, name)
  for name, field in obj.fieldPairs:
    encoder.serialise(field, name)

proc fieldCount(T: typedesc): int =
  for _ in default(T).fields:
    inc result

proc deserialise*(dec: var Decoder, obj: var (object or tuple)) =
  mixin deserialise
  let (typ, _) = dec.typeNamePair()
  canConvertFrom(typ, obj)
  if dec.useNames:
    var parsed = 0
    while parsed < fieldCount(typeof obj): ## Does not work for object variants... need a think
      let
        start = parsed
        (_, nameInd) = dec.peekTypeNamePair()

      if nameInd.isNone:
        raise (ref VbsfError)(msg: "Expected name here")

      for name, field in obj.fieldPairs:
        if name == dec.getStr(nameInd.unsafeGet):
          deserialise(dec, field)
          inc parsed

      if parsed == start:
        raise (ref VbsfError)(msg: "Cannot parse the given data to the type")
  else:
    for field in obj.fields:
      let (_, nameInd) = dec.peekTypeNamePair()
      if nameInd.isSome:
        raise (ref VbsfError)(msg: "Has name but expected no name.")
      deserialise(dec, field)


proc serialise*(encoder: var Encoder, data: sink(ref), name: string) =
  serialiseTypeInfo(encoder, data, name)
  encoder.write data != nil
  if data != nil:
    encoder.serialise(data[], "")

proc deserialise*(dec: var Decoder, data: var ref) =
  let (typ, nameInd) = dec.typeNamePair()
  canConvertFrom(typ, data)
  let isRefNil = dec.stream.readUint8() == 0
  if not isRefNil:
    new data
  dec.deserialise(data[])

proc serialise*(encoder: var Encoder, data: sink (distinct), name: string) =
  serialiseTypeInfo(encoder, distinctBase(data), name)
  encoder.serialise(distinctBase(data), "")

proc deserialise*(dec: var Encoder, data: var (distinct)) =
  dec.deserialise(distinctBase(data))

proc serialise*[T](encoder: var Encoder, data: sink set[T], name: string) =
  const setSize = sizeof(data)
  when setSize == 1:
    encoder.serialise(cast[uint8](data), name)
  elif setSize == 2:
    encoder.serialise(cast[uint16](data), name)
  elif setSize == 4:
    encoder.serialise(cast[uint32](data), name)
  elif setSize == 8:
    encoder.serialise(cast[uint64](data), name)
  else:
    encoder.serialise(cast[array[setSize, byte]](data), name)

proc deserialise*[T](dec: var Decoder, data: var set[T]) =
  const setSize = sizeof(data)
  when setSize == 1:
    dec.deserialise(cast[ptr uint8](data.addr)[])
  elif setSize == 2:
    dec.deserialise(cast[ptr uint16](data.addr)[])
  elif setSize == 4:
    dec.deserialise(cast[ptr uint32](data.addr)[])
  elif setSize == 8:
    dec.deserialise(cast[ptr uint64](data.addr)[])
  else:
    dec.deserialise(cast[ptr array[setSize, byte]](data.addr)[])

proc serialiseRoot(encoder: var Encoder, val: sink (object or tuple)) =
  encoder.serialise(val, "")

proc deserialiseRoot(dec: var Decoder, T: typedesc[object or tuple]): T =
  let (typ, nameInd) = dec.peekTypeNamePair()
  canConvertFrom(typ, result)
  if nameInd.isSome():
    raise (ref VbsfError)(msg: "Expected a nameless root, but it was named: " & dec.getStr(nameInd.unsafeGet))
  dec.deserialise(result)

proc init*(_: typedesc[Encoder], storeNames: bool): Encoder =
  Encoder(
    strsBuffer: newStringStream(),
    dataBuffer: newStringStream(),
    storeNames: storeNames
    )

proc readHeaderAndExtractStrings(dec: var Decoder) =
  var ext: array[4, char]
  dec.stream.read(ext)
  if ext != "vsbf":
    raise (ref VbsfError)(msg: "Not a VSBF stream, missing the header")
  discard dec.stream.readUint16 # No versioning yet
  for _ in 0..<dec.stream.readLeb128(int):
    let
      len = dec.stream.readLeb128(int)
    dec.strs.add dec.stream.readStr(len)

proc init*(_: typedesc[Decoder], useNames: bool, stream: sink Stream): Decoder =
  result = Decoder(
    stream: stream,
    useNames: useNames)
  result.readHeaderAndExtractStrings()
  # We now should be sitting right on the root entry's typeId

proc save*(encoder: var Encoder, path: string) =
  ## Writes the data to a file

  # Format is is vsbf, version, strings, firstEntryTypeId, ....
  let fs = newFileStream(path, fmWrite)
  defer: fs.close
  fs.write header
  encoder.strsBuffer.setPosition(0)
  encoder.dataBuffer.setPosition(0)
  fs.writeLeb128 encoder.strs.len
  fs.write encoder.strsBuffer.readAll()
  fs.write encoder.dataBuffer.readAll()


var encoder = Encoder.init(true)

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

let obj = MyObject(
  x: 0, y: 0, age: 42,
  name: "Jimbo",
  talents: ["Jumping", "Running", "", ""],
  pets: @["Sam", "Diesel"],
  letters: {'a'..'z'},
  children: newSeq[MyObject](5))

encoder.serialiseRoot(obj)
encoder.save "/tmp/test.vsbf"
encoder = Encoder.init(false)
encoder.serialiseRoot(obj)
encoder.save "/tmp/test1.vsbf"


var decoder = Decoder.init(true, openFileStream("/tmp/test.vsbf", fmRead))
assert decoder.deserialiseRoot(MyObject) == obj

decoder = Decoder.init(false, openFileStream("/tmp/test1.vsbf", fmRead))
assert decoder.deserialiseRoot(MyObject) == obj
