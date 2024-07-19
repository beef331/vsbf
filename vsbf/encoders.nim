import std/[options, typetraits, tables, streams]
import shared

type
  Encoder*[DataType: SeqOrArr[byte]] = object
    strs: Table[string, int]
    when DataType is seq[byte]:
      strsBuffer*: seq[byte]
        ## The string section, contains an array of `(len: leb128, data: UncheckedArray[char])`
      dataBuffer*: seq[byte]
        ##
        ## The data section, first value should be the 'entry' and is a `typeId` that determines how all the data is parsed.
        ## In the future this may be enforced to be a `Struct` or custom type
    else:
      strsBuffer*: UnsafeView[byte]
        ## The string section, contains an array of `(len: leb128, data: UncheckedArray[char])`
      strsPos*: int
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
    strsBuffer: strsBuffer.toUnsafeView(),
    dataBuffer: dataBuffer.toUnsafeView(),
    storeNames: storeNames,
  )

proc init*(_: typedesc[Encoder], storeNames: bool): Encoder[seq[byte]] =
  Encoder[seq[byte]](
    strsBuffer: newSeqOfCap[byte](256),
    dataBuffer: newSeqOfCap[byte](256),
    storeNames: storeNames,
  )

template offsetStrBuffer*(encoder: Encoder[openArray[byte]]): untyped =
  encoder.strsBuffer.toOpenArray(encoder.strsPos)

template offsetDataBuffer*(encoder: Encoder[openArray[byte]]): untyped =
  encoder.dataBuffer.toOpenArray(encoder.dataPos)

template data*[T](encoder: Encoder[T]): untyped =
  when T is seq:
    encoder.databuffer.toOpenArray(0, encoder.dataBuffer.high)
  else:
    encoder.dataBuffer.toOpenArray(0, encoder.dataPos - 1)

template stringBuffer*[T](encoder: Encoder[T]): untyped =
  when T is seq:
    encoder.strsBuffer.toOpenArray(0, encoder.strsBuffer.high)
  else:
    encoder.strsBuffer.toOa.toOpenArray(0, encoder.strsPos - 1)

proc writeToStr*[T](encoder: var Encoder[T], toWrite: SomeInteger) =
  when T is seq:
    discard encoder.strsBuffer.write(toWrite)
  else:
    encoder.strsPos += encoder.offsetStrBuffer().write toWrite

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

proc cacheStr*(encoder: var Encoder, str: sink string): int =
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

proc serialise*(encoder: var Encoder, f: SomeFloat, name: string) =
  serialiseTypeInfo(encoder, f, name)
  encoder.writeToData f

proc serialise*(encoder: var Encoder, str: sink string, name: string) =
  serialiseTypeInfo(encoder, str, name)
  let (data, len) = leb128 encoder.cacheStr(str)
  encoder.writeToData data.toOpenArray(0, len - 1)

proc serialise*[Idx, T](encoder: var Encoder, arr: sink array[Idx, T], name: string) =
  serialiseTypeInfo(encoder, arr, name)
  let (data, len) = leb128 arr.len
  encoder.writeToData data.toOpenArray(0, len - 1)
  for val in arr.mitems:
    encoder.serialise(val, "")

proc serialise*[T](encoder: var Encoder, arr: sink seq[T], name: string) =
  serialiseTypeInfo(encoder, arr, name)
  let (data, len) = leb128 arr.len
  encoder.writeToData data.toOpenArray(0, len - 1)
  for val in arr.mitems:
    encoder.serialise(val, "")
  wasMoved(arr)

proc serialise*(encoder: var Encoder, obj: sink (object or tuple), name: string) =
  mixin serialise
  serialiseTypeInfo(encoder, obj, name)
  for name, field in obj.fieldPairs:
    encoder.serialise(field, name)

proc serialise*(encoder: var Encoder, data: sink(ref), name: string) =
  serialiseTypeInfo(encoder, data, name)
  encoder.writeToData byte(data != nil)
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
  fs.write encoder.stringBuffer
  fs.write encoder.data
