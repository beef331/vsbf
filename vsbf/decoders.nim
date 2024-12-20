import std/[options, typetraits, tables, macros, strformat]
import shared

type
  Decoder*[DataType: SeqOrArr[byte]] = object
    strs*: seq[string] ## List of strings that are indexed by string indexes
    when DataType is seq[byte]:
      stream*: seq[byte]
    else:
      stream*: UnsafeView[byte]
    pos*: int

proc len(dec: Decoder): int = dec.stream.len

template data*[T](decoder: Decoder[T]): untyped =
  decoder.stream.toOpenArray(decoder.pos, decoder.stream.len - 1)

proc read[T: SomeInteger](oa: openArray[byte], res: var T): bool =
  if sizeof(T) <= oa.len:
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

proc readString*(dec: var Decoder) =
  var strLen = 0
  dec.pos += dec.data.readLeb128(strLen)
  var buffer = newString(strLen)

  for i in 0..<strLen:
    buffer[i] = char dec.data[i]

  dec.strs.add buffer
  dec.pos += strLen

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
    let indSize = dec.data.readLeb128(ind)
    dec.pos += indSize
    result.nameInd = some(ind)
    if indSize > 0:
      if ind notin 0..dec.strs.high:
        dec.readString()
    else:
      raise (ref VsbfError)(msg: "No name following a declaration.")




proc peekTypeNamePair*(
    dec: var Decoder
): tuple[typ: SerialisationType, name: string] =
  ## peek the type and name's string index if it has it
  let encodedType = dec.data[0]
  var hasName: bool
  (result.typ, hasName) = encodedType.decodeType()

  if hasName:
    var val = 0
    let indSize = dec.data.toOpenArray(1).readLeb128(val)
    if indSize > 0:
      if val notin 0..dec.strs.high:
        var strLen = 0
        let
          strLenBytes = dec.data.toOpenArray(1 + indSize).readLeb128(strLen)
          start = 1 + indSize + strLenBytes
        result.name = newString(strLen)
        for i, x in dec.data.toOpenArray(start, start + strLen - 1):
          result.name[i] = char x
      else:
        result.name = dec.strs[val]
    else:
      raise (ref VsbfError)(msg: "No name following a declaration.")

proc getStr*(dec: Decoder, ind: int): lent string =
  dec.strs[ind]

proc readHeader(dec: var Decoder) =
  var ext = dec.read(array[4, char])
  if ext.isNone or ext.unsafeGet != "vsbf":
    raise (ref VsbfError)(msg: "Not a VSBF stream, missing the header")
  dec.pos += 4

  let ver = dec.read(array[2, byte])

  if ver.isNone:
    raise (ref VsbfError)(msg: "Cannot read, missing version")

  dec.pos += 2

proc init*(
    _: typedesc[Decoder], data: sink seq[byte]
): Decoder[seq[byte]] =
  ## Heap allocated version, it manages it's own buffer you give it and reads from this.
  ## Can recover the buffer using `close` after parsin
  result = Decoder[seq[byte]](stream: data)
  result.readHeader()
  # We now should be sitting right on the root entry's typeId

proc close*(decoder: sink Decoder[seq[byte]]): seq[byte] =
  ensureMove(decoder.stream)

proc init*(
    _: typedesc[Decoder], data: openArray[byte]
): Decoder[openArray[byte]] =
  ## Non heap allocating version of the decoder uses preallocated memory that must outlive the structure
  result = Decoder[openArray[byte]](stream: toUnsafeView data)
  result.readHeader()

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

  if ind notin 0..dec.strs.high:
    # It has not been read into yet
    dec.readString()

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

proc deserialise*[T: object | tuple](dec: var Decoder, obj: var T) =
  mixin deserialise
  let (typ, _) = dec.typeNamePair()
  canConvertFrom(typ, obj)

  while (let (typ, name) = dec.peekTypeNamePair(); typ) != EndStruct:
    if name == "":
      raise (ref VsbfError)(msg: "Expected name at: " & $dec.pos)

    for fieldName, field in obj.fieldPairs:
      const realName =
        when field.hasCustomPragma(vsbfName):
          field.getCustomPragmaVal(vsbfName)
        else:
          fieldName

      when not field.hasCustomPragma(skipSerialisation):
        if realName == name:
          deserialise(dec, field)

  if dec.pos != dec.len - 1 and (let (typ, _) = dec.typeNamePair(); typ) != EndStruct: # Pops the end and ensures it's correct'
    raise (ref VsbfError)(msg: "Invalid struct expected EndStruct at {dec.pos}")


proc deserialise*[T: range](dec: var Decoder, data: var T) =
  var base = T.rangeBase().default()
  dec.deserialise(base)
  if base notin T.low..T.high:
    raise (ref VsbfError)(msg: "Stored value out of range got '" & $base & "' but expected: " & $T)
  data = T(base)

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

proc deserialise*[T: range | enum](dec: var Decoder, data: var T) =
  let
    start = dec.pos
    (typ, nameInd) = dec.typeNamePair()
  canConvertFrom(typ, data)

  var base = default T.rangeBase()
  dec.deserialise(base)
  if base notin T.low..T.high:
    raise (ref VsbfError)(msg: "Cannot convert to range got '{base}', but expected value in '{T}'. At position: '{dec.pos}'")


proc deserialise*(dec: var Decoder, data: var ref) =
  let (typ, nameInd) = dec.typeNamePair()
  canConvertFrom(typ, data)
  let isRefNil = dec.data[0]
  dec.pos += 1
  if not isRefNil:
    new data
  dec.deserialise(data[])

proc deserialiseRoot*(dec: var Decoder, T: typedesc[object or tuple]): T =
  let (typ, name) = dec.peekTypeNamePair()
  canConvertFrom(typ, result)
  if name != "":
    raise (ref VsbfError)(
        msg:
          "Expected a nameless root, but it was named: " & name
      )
  dec.deserialise(result)
