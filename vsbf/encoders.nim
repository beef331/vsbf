import std/[options, typetraits, tables, streams, macros]
import shared

type
  Encoder*[DataType: SeqOrArr[byte]] = object
    strs: Table[string, int]
    when DataType is seq[byte]:        ## The string section, contains an array of `(len: leb128, data: UncheckedArray[char])`
      dataBuffer*: seq[byte]
        ##
        ## The data section, first value should be the 'entry' and is a `typeId` that determines how all the data is parsed.
        ## In the future this may be enforced to be a `Struct` or custom type
    else:
      dataBuffer*: UnsafeView[byte]
        ##
        ## The data section, first value should be the 'entry' and is a `typeId` that determines how all the data is parsed.
        ## In the future this may be enforced to be a `Struct` or custom type
      dataPos*: int
    storeNames: bool
      ## Whether we set the first bit to high where applicable (struct fields)

proc init*(
    _: typedesc[Encoder], storeNames: bool, strsBuffer, dataBuffer: openArray[byte]
): Encoder =
  Encoder(
    dataBuffer: dataBuffer.toUnsafeView(),
    storeNames: storeNames,
  )

proc init*(_: typedesc[Encoder], storeNames: bool): Encoder[seq[byte]] =
  Encoder[seq[byte]](
    dataBuffer: newSeqOfCap[byte](256),
    storeNames: storeNames,
  )

template offsetDataBuffer*(encoder: Encoder[openArray[byte]]): untyped =
  encoder.dataBuffer.toOpenArray(encoder.dataPos)

template data*[T](encoder: Encoder[T]): untyped =
  when T is seq:
    encoder.databuffer.toOpenArray(0, encoder.dataBuffer.high)
  else:
    encoder.dataBuffer.toOpenArray(0, encoder.dataPos - 1)

proc writeTo*[T](encoder: var Encoder[T], toWrite: SomeInteger) =
  when T is seq:
    discard encoder.dataBuffer.write(toWrite)
  else:
    encoder.dataPos += encoder.offsetDataBuffer().write toWrite

proc writeTo*[T](encoder: var Encoder[T], toWrite: openArray[byte]) =
  when T is seq:
    encoder.dataBuffer.add toWrite
  else:
    for i, x in toWrite:
      encoder.offsetDataBuffer()[i] = x
    encoder.dataPos += toWrite.len

proc cacheStr*(encoder: var Encoder, str: sink string) =
  ## Writes the string to the buffer
  ## If the string has not been seen yet it'll print Index Len StringData to cache it
  withValue encoder.strs, str, val:
    let (data, len) = leb128 val[]
    encoder.writeTo data.toOpenArray(0, len - 1)
  do:
    var (data, len) = leb128 encoder.strs.len
    encoder.writeTo(data.toOpenArray(0, len - 1))
    (data, len) = leb128 str.len
    encoder.writeTo(data.toOpenArray(0, len - 1))
    encoder.writeTo(str.toOpenArrayByte(0, str.high))
    encoder.strs[str] = encoder.strs.len

proc serialiseTypeInfo[T](encoder: var Encoder, val: T, name: sink string) =
  ## Stores the typeID and name if it's required(0b1xxx_xxxx if there is a name)
  encoder.writeTo T.vsbfId.encoded(encoder.storeNames and name.len > 0)
  if encoder.storeNames and name.len > 0:
    encoder.cacheStr(name)

proc serialise*(encoder: var Encoder, i: SomeInteger, name: string) =
  serialiseTypeInfo(encoder, i, name)
  let (data, len) = leb128 i
  encoder.writeTo data.toOpenArray(0, len - 1)

proc serialise*(encoder: var Encoder, i: enum, name: string) =
  serialiseTypeInfo(encoder, i, name)
  let (data, len) = leb128 int64(i)
  encoder.writeTo data.toOpenArray(0, len - 1)

proc serialise*(encoder: var Encoder, f: SomeFloat, name: string) =
  serialiseTypeInfo(encoder, f, name)
  when f is float32:
    encoder.writeTo cast[int32](f)
  else:
    encoder.writeTo cast[int64](f)

proc serialise*(encoder: var Encoder, str: sink string, name: string) =
  serialiseTypeInfo(encoder, str, name)
  encoder.cacheStr(str)

proc serialise*[Idx, T](encoder: var Encoder, arr: sink array[Idx, T], name: string) =
  serialiseTypeInfo(encoder, arr, name)
  let (data, len) = leb128 arr.len
  encoder.writeTo data.toOpenArray(0, len - 1)
  for val in arr.mitems:
    encoder.serialise(val, "")

proc serialise*[T](encoder: var Encoder, arr: sink seq[T], name: string) =
  serialiseTypeInfo(encoder, arr, name)
  let (data, len) = leb128 arr.len
  encoder.writeTo data.toOpenArray(0, len - 1)
  for val in arr.mitems:
    encoder.serialise(val, "")
  wasMoved(arr)

proc serialise*(encoder: var Encoder, obj: sink (object or tuple), name: string) =
  mixin serialise
  serialiseTypeInfo(encoder, obj, name)
  for name, field in obj.fieldPairs:
    when not field.hasCustomPragma(vsbfUnserialized):
      encoder.serialise(field, name)

proc serialise*(encoder: var Encoder, data: sink(ref), name: string) =
  serialiseTypeInfo(encoder, data, name)
  encoder.writeTo byte(data != nil)
  if data != nil:
    encoder.serialise(data[], "")

proc serialise*(encoder: var Encoder, data: sink (distinct), name: string) =
  serialiseTypeInfo(encoder, distinctBase(data), name)
  encoder.serialise(distinctBase(data), "")

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

proc serialiseRoot*(encoder: var Encoder, val: sink (object or tuple)) =
  encoder.serialise(val, "")

proc write(stream: Stream, oa: openArray[byte]) =
  for x in oa:
    stream.write(x)

proc save*(encoder: var Encoder, path: string) =
  ## Writes the data to a file

  # Format is is vsbf, version, strings, firstEntryTypeId, ....
  let fs = newFileStream(path, fmWrite)
  defer:
    fs.close
  fs.write header
  let (data, len) = leb128 encoder.strs.len
  fs.write data.toOpenArray(0, len - 1)
  fs.write encoder.data
