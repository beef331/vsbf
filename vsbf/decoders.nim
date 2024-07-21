import std/[options, typetraits, tables]
import shared

type
  Decoder*[DataType: SeqOrArr[byte]] = object
    strs*: seq[string] ## List of strings that are indexed by string indexes
    when DataType is seq[byte]:
      stream*: seq[byte]
    else:
      stream*: UnsafeView[byte]
    pos*: int
    useNames: bool

template data*[T](decoder: Decoder[T]): untyped =
  decoder.stream.toOpenArray(decoder.pos, decoder.stream.len - 1)

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

proc typeNamePair*(
    dec: var Decoder
): tuple[typ: SerialisationType, nameInd: options.Option[int]] =
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

proc peekTypeNamePair*(
    dec: var Decoder
): tuple[typ: SerialisationType, nameInd: options.Option[int]] =
  ## peek the type and name's string index if it has it
  let encodedType = dec.data[0]
  var hasName: bool
  (result.typ, hasName) = encodedType.decodeType()

  if hasName:
    var val = 0
    if dec.data.toOpenArray(1).readLeb128(val) > 0:
      result.nameInd = some(val)
    else:
      raise (ref VsbfError)(msg: "No name following a declaration.")

proc getStr*(dec: Decoder, ind: int): lent string =
  dec.strs[ind]

proc readHeaderAndExtractStrings(dec: var Decoder) =
  var ext = dec.read(array[4, char])
  if ext.isNone or ext.unsafeGet != "vsbf":
    raise (ref VsbfError)(msg: "Not a VSBF stream, missing the header")
  dec.pos += 4

  let ver = dec.read(array[2, byte])

  if ver.isNone:
    raise (ref VsbfError)(msg: "Cannot read, missing version")

  dec.pos += 2

  var len = 0
  let read = dec.data.readLeb128(len)
  if read == 0:
    raise (ref VsbfError)(msg: "Not enough data.")

  dec.pos += read
  for _ in 0..<len:
    var len = 0
    let read = dec.data.readLeb128(len)
    if read == 0:
      raise (ref VsbfError)(msg: "Not enough data.")
    dec.pos += read
    var str = newString(len)
    for i, x in dec.data.toOpenArray(0, len - 1):
      str[i] = char(x)
    dec.strs.add ensureMove str
    dec.pos += len

proc init*(
    _: typedesc[Decoder], useNames: bool, data: sink seq[byte]
): Decoder[seq[byte]] =
  ## Heap allocated version, it manages it's own buffer you give it and reads from this.
  ## Can recover the buffer using `close` after parsin
  result = Decoder[seq[byte]](stream: data, useNames: useNames)
  result.readHeaderAndExtractStrings()
  # We now should be sitting right on the root entry's typeId

proc close*(decoder: sink Decoder[seq[byte]]): seq[byte] =
  ensureMove(decoder.stream)

proc init*(
    _: typedesc[Decoder], useNames: bool, data: openArray[byte]
): Decoder[openArray[byte]] =
  ## Non heap allocating version of the decoder uses preallocated memory that must outlive the structure
  result = Decoder[openArray[byte]](stream: toUnsafeView data, useNames: useNames)
  result.readHeaderAndExtractStrings()
  # We now should be sitting right on the root entry's typeId

proc deserialise*(dec: var Decoder, i: var SomeInteger) =
  let (typ, _) = dec.typeNamePair()
  canConvertFrom(typ, i)
  dec.pos += dec.data.readLeb128(i)

proc deserialise*(dec: var Decoder, f: var SomeFloat) =
  let (typ, _) = dec.typeNamePair()
  canConvertFrom(typ, f)
  dec.data.read(f)

proc deserialise*(dec: var Decoder, str: var string) =
  let (typ, _) = dec.typeNamePair()
  canConvertFrom(typ, str)
  var ind = 0
  dec.pos += dec.data.readLeb128(ind)

  str = dec.getStr(ind)

proc deserialise*[Idx, T](dec: var Decoder, arr: var array[Idx, T]) =
  let (typ, _) = dec.typeNamePair()
  canConvertFrom(typ, arr)
  var len = 0
  dec.pos += dec.data.readLeb128(len)
  if len > arr.len:
    raise (ref VsbfError)(
        msg:
          "Expected an array with a length equal to or less than '" & $arr.len &
          "', but got length of '" & $len & "'."
      )
  for i in 0..<len:
    dec.deserialise(arr[i])

proc deserialise*[T](dec: var Decoder, arr: var seq[T]) =
  let (typ, _) = dec.typeNamePair()
  canConvertFrom(typ, arr)
  var len = 0
  dec.pos += dec.data.readLeb128(len)
  arr = newSeq[T](len)
  for i in 0..<len:
    dec.deserialise(arr[i])

proc fieldCount(T: typedesc): int =
  for _ in default(T).fields:
    inc result

proc deserialise*(dec: var Decoder, obj: var (object or tuple)) =
  mixin deserialise
  let (typ, _) = dec.typeNamePair()
  canConvertFrom(typ, obj)
  if dec.useNames:
    var parsed = 0
    while parsed < fieldCount(typeof obj):
      ## Does not work for object variants... need a think
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

proc deserialise*(dec: var Decoder, data: var (distinct)) =
  dec.deserialise(distinctBase(data))

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

proc deserialise*(dec: var Decoder, data: var ref) =
  let (typ, nameInd) = dec.typeNamePair()
  canConvertFrom(typ, data)
  let isRefNil = dec.data[0]
  dec.pos += 1
  if not isRefNil:
    new data
  dec.deserialise(data[])

proc deserialiseRoot*(dec: var Decoder, T: typedesc[object or tuple]): T =
  let (typ, nameInd) = dec.peekTypeNamePair()
  canConvertFrom(typ, result)
  if nameInd.isSome():
    raise (ref VsbfError)(
        msg:
          "Expected a nameless root, but it was named: " & dec.getStr(nameInd.unsafeGet)
      )
  dec.deserialise(result)
