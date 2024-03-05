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

  SeqOrArr[T] = seq[T] or openarray[T]

  UnsafeView[T] = object
    data: ptr UncheckedArray[T]
    len: int

  Encoder*[DataType: SeqOrArr[byte]] = object
    strs: Table[string, int]
    when DataType is seq[byte]:
      strsBuffer*: seq[byte] ## The string section, contains an array of `(len: leb128, data: UncheckedArray[char])`
      dataBuffer*: seq[byte] ##
        ## The data section, first value should be the 'entry' and is a `typeId` that determines how all the data is parsed.
        ## In the future this may be enforced to be a `Struct` or custom type
    else:
      strsBuffer*: UnsafeView[byte] ## The string section, contains an array of `(len: leb128, data: UncheckedArray[char])`
      strsPos*: int
      dataBuffer*: UnsafeView[byte] ##
        ## The data section, first value should be the 'entry' and is a `typeId` that determines how all the data is parsed.
        ## In the future this may be enforced to be a `Struct` or custom type
      dataPos*: int
    storeNames: bool ## Whether we set the first bit to high where applicable (struct fields)

  Decoder*[DataType: SeqOrArr[byte]] = object
    strs*: seq[string] ## List of strings that are indexed by string indexes
    when DataType is seq[byte]:
      stream*: seq[byte]
    else:
      stream*: UnsafeView[byte]
    pos*: int
    useNames: bool
  VsbfError = object of ValueError

static:
  assert sizeof(SerialisationType) == 1 # Types are always 1
  assert SerialisationType.high.ord <= 127

proc write*(stream: Stream, oa: openArray[byte]) =
  for x in oa:
    stream.write(x)

proc toUnsafeView[T](oa: openArray[T]): UnsafeView[T] =
  UnsafeView[T](data: cast[ptr UncheckedArray[T]](oa[0].addr), len: oa.len)

template toOa[T](view: UnsafeView[T]): auto =
  view.data.toOpenArray(0, view.len - 1)

template toOpenArray[T](view: UnsafeView[T], low, high: int): auto =
  view.data.toOpenArray(low, high)

template toOpenArray[T](view: UnsafeView[T], low: int): auto =
  view.data.toOpenArray(low, view.len - 1)

template toOpenArray[T](oa: openArray[T], low: int): auto =
  oa.toOpenArray(low, oa.len - 1)

template offsetStrBuffer*(encoder: Encoder[openArray[byte]]): untyped =
  encoder.strsBuffer.toOpenArray(encoder.strsPos)

template offsetDataBuffer*(encoder: Encoder[openArray[byte]]): untyped =
  encoder.dataBuffer.toOpenArray(encoder.dataPos)

template offsetStream*(decoder: Decoder[openArray[byte]]): untyped =
  decoder.stream.toOpenArray(decoder.pos)

template data*[T](encoder: Encoder[T]): untyped =
  when T is seq:
    encoder.databuffer.toOpenArray(0, encoder.dataBuffer.high)
  else:
    encoder.dataBuffer.toOa.toOpenArray(0, encoder.dataPos - 1)

template stringBuffer*[T](encoder: Encoder[T]): untyped =
  when T is seq:
    encoder.strsBuffer.toOpenArray(0, encoder.strsBuffer.high)
  else:
    encoder.strsBuffer.toOa.toOpenArray(0, encoder.strsPos - 1)

template data*[T](decoder: Decoder[T]): untyped =
  decoder.stream.toOpenArray(decoder.pos, decoder.stream.len - 1)

proc write*(oa: var openArray[byte], toWrite: SomeInteger): int =
  if oa.len > sizeof(toWrite):
    result = sizeof(toWrite)
    for offset in 0..<sizeof(toWrite):
      oa[offset] = byte(toWrite shr (offset * 8) and 0xff)

proc write*(sq: var seq[byte], toWrite: SomeInteger): int =
  result = sizeof(toWrite)
  for offset in 0..<sizeof(toWrite):
    sq.add byte((toWrite shr (offset * 8)) and 0xff)

proc writeToStr*[T](encoder: var Encoder[T], toWrite: SomeInteger) =
  when T is seq:
    discard encoder.strsBuffer.write(toWrite)
  else:
    encoder.strsPos += encoder.offsetStrBuffer().write toWrite

proc read[T: SomeInteger](oa: openArray[byte], res: var T): bool =
  if sizeof(T) < oa.len:
    res = T(0)
    for i in T(0)..<sizeof(T):
      res = res or (T(oa[int i]) shl (i * 8))

    true
  else:
    false

proc read(frm: openArray[byte], to: var openArray[byte or char]): int =
  if to.len > frm.len:
    -1
  else:
    for i in 0..to.high:
      to[i] = typeof(to[0])(frm[i])
    to.len

proc read[T](dec: var Decoder[T], data: typedesc): Option[data] =
  var val = default data
  if dec.data.read(val) > 0:
    some(val)
  else:
    none(data)

proc writeToData*[T](encoder: var Encoder[T], toWrite: SomeInteger) =
  when T is seq:
    discard encoder.dataBuffer.write(toWrite)
  else:
    encoder.dataPos += encoder.offsetDataBuffer().write toWrite

proc writeToStr*[T](encoder: var Encoder[T], toWrite: openArray[byte]) =
  when T is seq:
    encoder.strsBuffer.add toWrite
  else:
    for i, x in toWrite:
      encoder.offsetStrBuffer()[i] = x
    encoder.strsPos += toWrite.len

proc writeToData*[T](encoder: var Encoder[T], toWrite: openArray[byte]) =
  when T is seq:
    encoder.dataBuffer.add toWrite
  else:
    for i, x in toWrite:
      encoder.offsetDataBuffer()[i] = x
    encoder.dataPos += toWrite.len



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

proc writeLeb128*(buffer: var openArray[byte], i: SomeUnsignedInt): int =
  var
    val = ord(i)
    ranOnce = false

  while val != 0 or not ranOnce:
    var data = byte(val and 0b0111_1111)
    val = val shr 7
    if val != 0:
      data = 0b1000_0000 or data
    buffer[result] = data
    ranOnce = true
    inc result
    if result > buffer.len:
      return -1

proc writeLeb128*(buffer: var openArray[byte], i: SomeSignedInt): int =
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
    buffer[result] = data
    inc result
    if result > buffer.len:
      return -1

proc readLeb128*[T: SomeUnsignedInt](data: openArray[byte], val: var T): int =
  var
    shift = 0
    pos = 0

  while true:
    if pos > data.len:
      raise (ref VsbfError)(msg: "Attempting to read a too large integer")
    let ind = pos
    inc pos
    let theByte = data[pos]
    val = val or (T(0b0111_1111u8 and theByte) shl T(shift))
    inc result

    if (0b1000_0000u8 and theByte) == 0:
      break
    shift += 7

  if shift > sizeof(T) * 8:
    raise (ref VsbfError)(msg: "Got incorrect sized integer for given field type.")

proc readLeb128[T: SomeSignedInt](data: openArray[byte], val: var T): int =
  var
    shift = 0
    theByte: byte
    pos = 0

  template whileBody =
    let ind = pos
    inc pos
    theByte = data[ind]
    val = val or T((0b0111_1111 and theByte) shl shift)
    shift += 7
    inc result

  whileBody()

  while (0b1000_0000 and theByte) != 0:
    whileBody()

  if shift > sizeof(T) * 8:
    raise (ref VsbfError)(msg: "Got incorrect sized integer for given field type.")

  if (theByte and 0b0100_0000) == 0b0100_0000:
    val = val or (not(T(1)) shl shift)

proc leb128(i: SomeInteger): (array[10, byte], int) =
  var data: array[10, byte]
  let len = data.writeLeb128(i)
  (data, len)

proc typeNamePair*(dec: var Decoder): tuple[typ: SerialisationType, nameInd: options.Option[int]] =
  ## reads the type and name's string index if it has it
  var encodedType = 0u8
  if not dec.data.read(encodedType):
    raise newException(VsbfError, "Failed to read type info")
  dec.pos += 1

  var hasName: bool
  (result.typ, hasName) = encodedType.decodeType()

  if hasName:
    var ind = 0
    dec.pos += dec.data.readLeb128(ind)
    result.nameInd = some(ind)

proc peekTypeNamePair*(dec: var Decoder): tuple[typ: SerialisationType, nameInd: options.Option[int]] =
  ## peek the type and name's string index if it has it
  let encodedType = dec.data[0]
  var hasName: bool
  (result.typ, hasName) = encodedType.decodeType()

  if hasName:
    var val = 0
    let read = dec.data.toOpenArray(1).readLeb128(val)
    result.nameInd = some(read)

proc getStr(dec: Decoder, ind: int): lent string =
  dec.strs[ind]

proc canConvertFrom(typ: SerialisationType, val: auto) =
  const expected = typeof(val).vsbfId()
  if typ != expected:
    raise (ref VsbfError)(msg: "Expected: " & $expected.ord & " but got " & $typ.ord)

proc cacheStr(encoder: var Encoder, str: sink string): int =
  withValue encoder.strs, str, val:
    result = val[]
  do:
    result = encoder.strs.len
    let (data, len) = leb128 str.len
    encoder.writeToStr(data.toOpenArray(0, len - 1))
    encoder.writeToStr(str.toOpenArrayByte(0, str.high))
    encoder.strs[str] = result

proc serialiseTypeInfo[T](encoder: var Encoder, val: T, name: sink string) =
  ## Stores the typeID and name if it's required(0b1xxx_xxxx if there is a name)
  encoder.writeToData T.vsbfId.encoded(encoder.storeNames and name.len > 0)
  if encoder.storeNames and name.len > 0:
    let (data, len) = leb128 encoder.cacheStr(name)
    encoder.writeToData data.toOpenArray(0, len - 1)

proc serialise*(encoder: var Encoder, i: SomeInteger, name: string) =
  serialiseTypeInfo(encoder, i, name)
  let (data, len) = leb128 i
  encoder.writeToData data.toOpenArray(0, len - 1)

proc deserialise*(dec: var Decoder, i: var SomeInteger) =
  let (typ, _) = dec.typeNamePair()
  canConvertFrom(typ, i)
  dec.pos += dec.stream.readLeb128(i)

proc serialise*(encoder: var Encoder, f: SomeFloat, name: string) =
  serialiseTypeInfo(encoder, f, name)
  encoder.writeToData f

proc deserialise*(dec: var Decoder, f: var SomeFloat) =
  let (typ, _) = dec.typeNamePair()
  canConvertFrom(typ, f)
  dec.stream.read(f)

proc serialise*(encoder: var Encoder, str: sink string, name: string) =
  serialiseTypeInfo(encoder, str, name)
  let (data, len) = leb128 encoder.cacheStr(str)
  encoder.writeToData data.toOpenArray(0, len - 1)

proc deserialise*(dec: var Decoder, str: var string) =
  let (typ, _) = dec.typeNamePair()
  canConvertFrom(typ, str)
  var ind = 0
  dec.pos += dec.stream.readLeb128(ind)
  str = dec.getStr(ind)

proc serialise*[Idx, T](encoder: var Encoder, arr: sink array[Idx, T], name: string) =
  serialiseTypeInfo(encoder, arr, name)
  let (data, len) = leb128 arr.len
  encoder.writeToData data.toOpenArray(0, len - 1)
  for val in arr.mitems:
    encoder.serialise(val, "")

proc deserialise*[Idx, T](dec: var Decoder, arr: var array[Idx, T]) =
  let (typ, _) = dec.typeNamePair()
  canConvertFrom(typ, arr)
  var len = 0
  dec.pos += dec.stream.readLeb128(len)
  if len > arr.len:
    raise (ref VsbfError)(msg: "Expected an array with a length equal to or less than '" & $arr.len & "', but got length of '" & $len & "'.")
  for i in 0..<len:
    dec.deserialise(arr[i])

proc serialise*[T](encoder: var Encoder, arr: sink seq[T], name: string) =
  serialiseTypeInfo(encoder, arr, name)
  let (data, len) = leb128 arr.len
  encoder.writeToData data.toOpenArray(0, len - 1)
  for val in arr.mitems:
    encoder.serialise(val, "")

proc deserialise*[T](dec: var Decoder, arr: var seq[T]) =
  let (typ, _) = dec.typeNamePair()
  canConvertFrom(typ, arr)
  var len = 0
  dec.pos += dec.stream.readLeb128(len)
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
        raise (ref VsbfError)(msg: "Expected name here")

      for name, field in obj.fieldPairs:
        if name == dec.getStr(nameInd.unsafeGet):
          deserialise(dec, field)
          inc parsed

      if parsed == start:
        raise (ref VsbfError)(msg: "Cannot parse the given data to the type")
  else:
    for field in obj.fields:
      let (_, nameInd) = dec.peekTypeNamePair()
      if nameInd.isSome:
        raise (ref VsbfError)(msg: "Has name but expected no name.")
      deserialise(dec, field)


proc serialise*(encoder: var Encoder, data: sink(ref), name: string) =
  serialiseTypeInfo(encoder, data, name)
  encoder.writeToData byte(data != nil)
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
    raise (ref VsbfError)(msg: "Expected a nameless root, but it was named: " & dec.getStr(nameInd.unsafeGet))
  dec.deserialise(result)

proc init*(_: typedesc[Encoder], storeNames: bool, strsBuffer, dataBuffer: openArray[byte]): Encoder =
  Encoder(
    strsBuffer: strsBuffer.toUnsafeView(),
    dataBuffer: dataBuffer.toUnsafeView(),
    storeNames: storeNames
    )

proc init*(_: typedesc[Encoder], storeNames: bool): Encoder[seq[byte]] =
  Encoder[seq[byte]](
    strsBuffer: newSeqOfCap[byte](256),
    dataBuffer: newSeqOfCap[byte](256),
    storeNames: storeNames
    )

proc readHeaderAndExtractStrings(dec: var Decoder) =
  var ext = dec.read(array[4, char])
  if ext.isNone or ext.unsafeGet != "vsbf":
    raise (ref VsbfError)(msg: "Not a VSBF stream, missing the header")

  let ver = dec.read(array[2, byte])

  var len = 0
  let read = dec.stream.readLeb128(len)
  if read == 0:
    raise (ref VsbfError)(msg: "Not enough data.")

  dec.pos += read

  for _ in 0..<len:
    var len = 0
    let read = dec.stream.readLeb128(len)
    if read == 0:
      raise (ref VsbfError)(msg: "Not enough data.")
    dec.pos += read

    var str = newString(len)
    for i, x in dec.data.toOpenArray(0, len):
      str[i] = char(x)
    dec.strs.add str
    dec.pos += len

proc init*(_: typedesc[Decoder], useNames: bool, data: sink seq[byte]): Decoder[seq[byte]] =
  ## Heap allocated version, it manages it's own buffer you give it and reads from this.
  ## Can recover the buffer using `close` after parsin
  result = Decoder[seq[byte]](
    stream: data,
    useNames: useNames)
  result.readHeaderAndExtractStrings()
  # We now should be sitting right on the root entry's typeId

proc close*(decoder: sink Decoder[seq[byte]]): seq[byte] = ensureMove(decoder.stream)

proc init*(_: typedesc[Decoder], useNames: bool, data: openArray[byte]): Decoder[openArray[byte]] =
  ## Non heap allocating version of the decoder uses preallocated memory that must outlive the structure
  result = Decoder[openArray[byte]](
    stream: toUnsafeView data,
    useNames: useNames)
  result.readHeaderAndExtractStrings()
  # We now should be sitting right on the root entry's typeId


proc save*(encoder: var Encoder, path: string) =
  ## Writes the data to a file

  # Format is is vsbf, version, strings, firstEntryTypeId, ....
  let fs = newFileStream(path, fmWrite)
  defer: fs.close
  fs.write header
  let (data, len) = leb128 encoder.strs.len
  fs.write data.toOpenArray(0, data.high)
  fs.write encoder.stringBuffer
  fs.write encoder.data


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

var encoder = Encoder.init(true)
encoder.serialiseRoot(obj)
encoder.save "/tmp/test.vsbf"
encoder = Encoder.init(false)
encoder.serialiseRoot(obj)
encoder.save "/tmp/test1.vsbf"

var
  fileData = readFile("/tmp/test.vsbf")
  theFile = @(fileData.toOpenArrayByte(0, fileData.high))

var decoder = Decoder.init(true, theFile)
assert decoder.deserialiseRoot(MyObject) == obj

#[
decoder = Decoder.init(false, openFileStream("/tmp/test1.vsbf", fmRead))
assert decoder.deserialiseRoot(MyObject) == obj
]#
