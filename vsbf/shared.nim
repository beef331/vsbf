import std/strutils
const
  version* = "\1\0"
  header* = ['v', 's', 'b', 'f', version[0], version[1]]

template vsbfUnserialized*() {.pragma.}

type
  SerialisationType* = enum
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
    Reserved = 127
      ## Highest number of builtin types, going past this will cause issues with how name tagging works.

  SeqOrArr*[T] = seq[T] or openarray[T]

  UnsafeView*[T] = object
    data*: ptr UncheckedArray[T]
    len*: int

  VsbfError* = object of ValueError

proc `$`*(serType: SerialisationType): string =
  if serType.ord in 0..99:
    "Custom" & $serType.ord
  else:
    system.`$`(serType)

static:
  assert sizeof(SerialisationType) == 1 # Types are always 1
  assert SerialisationType.high.ord <= 127

proc encoded*(serType: SerialisationType, storeName: bool): byte =
  if storeName: # las bit reserved for 'hasName'
    0b1000_0000u8 or byte(serType)
  else:
    byte(serType)

proc decodeType*(data: byte): tuple[typ: SerialisationType, hasName: bool] =
  result.hasName = (0b1000_0000u8 and data) > 0 # Extract whether the lastbit is set
  result.typ = cast[SerialisationType](data and 0b0111_1111)

proc canConvertFrom*(typ: SerialisationType, val: auto) =
  mixin vsbfid
  const expected = typeof(val).vsbfId()
  if typ != expected:
    raise (ref VsbfError)(msg: "Expected: " & $expected & " but got " & $typ)

proc toUnsafeView*[T](oa: openArray[T]): UnsafeView[T] =
  UnsafeView[T](data: cast[ptr UncheckedArray[T]](oa[0].addr), len: oa.len)

template toOa*[T](view: UnsafeView[T]): auto =
  view.data.toOpenArray(0, view.len - 1)

template toOpenArray*[T](view: UnsafeView[T], low, high: int): auto =
  view.data.toOpenArray(low, high)

template toOpenArray*[T](view: UnsafeView[T], low: int): auto =
  view.data.toOpenArray(low, view.len - 1)

template toOpenArray*[T](oa: openArray[T], low: int): auto =
  oa.toOpenArray(low, oa.len - 1)

proc write*(oa: var openArray[byte], toWrite: SomeInteger): int =
  if oa.len > sizeof(toWrite):
    result = sizeof(toWrite)
    for offset in 0..<sizeof(toWrite):
      oa[offset] = byte(toWrite shr (offset * 8) and 0xff)

proc write*(sq: var seq[byte], toWrite: SomeInteger): int =
  result = sizeof(toWrite)
  for offset in 0..<sizeof(toWrite):
    sq.add byte((toWrite shr (offset * 8)) and 0xff)

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
  var shift = 0

  while true:
    if result > data.len:
      raise (ref VsbfError)(msg: "Attempting to read a too large integer")
    let theByte = data[result]
    val = val or (T(0b0111_1111u8 and theByte) shl T(shift))
    inc result

    if (0b1000_0000u8 and theByte) == 0:
      break
    shift += 7

  if shift > sizeof(T) * 8:
    raise (ref VsbfError)(msg: "Got incorrect sized integer for given field type.")

proc readLeb128*[T: SomeSignedInt](data: openArray[byte], val: var T): int =
  var
    shift = 0
    theByte: byte

  template whileBody() =
    theByte = data[result]
    val = val or T(T(0b0111_1111 and theByte) shl T(shift))
    shift += 7
    inc result

  whileBody()

  while (0b1000_0000 and theByte) != 0:
    whileBody()

  if shift > sizeof(T) * 8:
    raise (ref VsbfError)(msg: "Got incorrect sized integer for given field type.")

  if (theByte and 0b0100_0000) == 0b0100_0000:
    val = val or (not (T(1)) shl T(shift))

proc leb128*(i: SomeInteger): (array[10, byte], int) =
  var data: array[10, byte]
  let len = data.writeLeb128(i)
  (data, len)

proc vsbfId*(_: typedesc[bool]): SerialisationType =
  Bool

proc vsbfId*(_: typedesc[int8 or uint8 or char]): SerialisationType =
  Int8

proc vsbfId*(_: typedesc[int16 or uint16]): SerialisationType =
  Int16

proc vsbfId*(_: typedesc[int32 or uint32]): SerialisationType =
  Int32

proc vsbfId*(_: typedesc[int64 or uint64]): SerialisationType =
  Int64

proc vsbfId*(_: typedesc[int or uint]): SerialisationType =
  Int64
  # Always 64 bits to ensure compatibillity

proc vsbfId*(_: typedesc[float32]): SerialisationType =
  Float32

proc vsbfId*(_: typedesc[float64]): SerialisationType =
  Float64

proc vsbfId*(_: typedesc[string]): SerialisationType =
  String

proc vsbfId*(_: typedesc[openArray]): SerialisationType =
  Array

proc vsbfId*(_: typedesc[object or tuple]): SerialisationType =
  Struct

proc vsbfId*(_: typedesc[ref]): SerialisationType =
  Option

proc vsbfId*(_: typedesc[enum]): SerialisationType =
  Int64
