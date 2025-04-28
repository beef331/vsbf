import decoders, shared, encoders
import std/strformat
import seeya

type
  SerializerState = ref object
    encoder: Encoder[openArray[byte]]

const nameStr = "vsbf_$1"

static:
  setFormatter(nameStr)
{.pragma: exporter, cdecl, dynlib, exportc: nameStr, raises: [].}


template returnVsbfError(body: untyped): untyped =
  try:
    body
    None
  except VsbfError as e:
    e.kind

proc new_serializer(data: openArray[byte]): SerializerState {.exporter, expose.} =
  ## Allocates a new serializer state and starts decoding `data`
  SerializerState(encoder: Encoder.init(data))

proc delete_serializer(state: SerializerState) =
  ## Deletes the allocated serializer state
  `=destroy`(state)

proc open_struct(state: SerializerState, name: openArray[char]): VsbfErrorKind {.exporter, expose.} =
  ## Starts an structure in the buffer, must be matched with `vsbf_close_struct`.
  returnVsbfError:
    state.encoder.writeTo Struct.encoded(name.len > 0)
    if name.len > 0:
      state.encoder.cacheStr(name.substr)

proc close_struct(state: SerializerState): VsbfErrorKind {.exporter, expose.} =
  ## Closes a structure in the buffer, must be matched with `vsbf_open_struct`.
  returnVsbfError:
    state.encoder.writeTo EndStruct.byte

proc add_array(state: SerializerState, name: openArray[char], len: int): VsbfErrorKind {.exporter, expose.} =
  ## Starts array with `name`.
  ## `len` is the amount of elements in this array.
  ## The following data likely should have an empty string passed along
  returnVsbfError:
    state.encoder.writeTo Array.encoded(name.len > 0)
    if name.len > 0:
      state.encoder.cacheStr(name.substr)

    let (data, len) = leb128 len
    state.encoder.writeTo data.toOpenArray(0, len - 1)

proc add_int8(state: SerializerState, name: openArray[char], i: int8): VsbfErrorKind {.exporter, expose.} =
  ## Adds an int8 to the buffer with `name`
  returnVsbfError:
    state.encoder.serialize(i, substr(name))

proc add_uint8(state: SerializerState, name: openArray[char], i: uint8): VsbfErrorKind {.exporter, expose.} =
  ## Adds a uint8 to the buffer with `name`
  returnVsbfError:
    state.encoder.serialize(i, substr(name))

proc add_int16(state: SerializerState, name: openArray[char], i: int16): VsbfErrorKind {.exporter, expose.} =
  ## Adds an int16 to the buffer with `name`
  returnVsbfError:
    state.encoder.serialize(i, substr(name))

proc add_uint16(state: SerializerState, name: openArray[char], i: uint16): VsbfErrorKind {.exporter, expose.} =
  ## Adds a uint16 to the buffer with `name`
  returnVsbfError:
    state.encoder.serialize(i, substr(name))

proc add_int32(state: SerializerState, name: openArray[char], i: int32): VsbfErrorKind {.exporter, expose.} =
  ## Adds an int32 to the buffer with `name`
  returnVsbfError:
    state.encoder.serialize(i, substr(name))

proc add_uint32(state: SerializerState, name: openArray[char], i: uint32): VsbfErrorKind {.exporter, expose.} =
  ## Adds a uint32 to the buffer with `name`
  returnVsbfError:
    state.encoder.serialize(i, substr(name))

proc add_int64(state: SerializerState, name: openArray[char], i: int64): VsbfErrorKind {.exporter, expose.} =
  ## Adds an int64 to the buffer with `name`
  returnVsbfError:
    state.encoder.serialize(i, substr(name))

proc add_uint64(state: SerializerState, name: openArray[char], i: uint64): VsbfErrorKind {.exporter, expose.} =
  ## Adds a uint64 to the buffer with `name`
  returnVsbfError:
    state.encoder.serialize(i, substr(name))

proc add_float(state: SerializerState, name: openArray[char], f: float32): VsbfErrorKind {.exporter, expose.} =
  ## Adds a float to the buffer with `name`
  returnVsbfError:
    state.encoder.serialize(f, substr(name))

proc add_double(state: SerializerState, name: openArray[char], f: float64): VsbfErrorKind {.exporter, expose.} =
  ## Adds a double to the buffer with `name`
  returnVsbfError:
    state.encoder.serialize(f, substr(name))

type
  DecoderState = ref object
    decoder: Decoder[openArray[byte]]

  DecodedValue = object
    case kind: SerialisationType
    of Bool..Int64:
      i: int
    of Float32, Float64:
      f: float
    of String:
      str: cstring
      str_length: int
    of Array..SerialisationType.high:
      discard


proc new_decoder*(buffer: openArray[byte], decoder: var DecoderState): VsbfErrorKind {.exporter, expose.} =
  try:
    decoder = DecoderState(decoder: Decoder.init(buffer))
    None
  except VsbfError as e:
    e.kind

proc delete_decoder*(decoder: DecoderState) {.exporter, expose.} =
  `=destroy`(decoder)

proc getInt(dec: var Decoder, kind: SerialisationType): DecodedValue =
  var val: int
  dec.pos += dec.data.readleb128(val)
  {.cast(uncheckedAssign).}:
    return DecodedValue(kind: kind, i: val)

proc getByte(dec: var Decoder, kind: SerialisationType): DecodedValue =
  let val = int(dec.data[0])
  inc dec.pos
  {.cast(uncheckedAssign).}:
    return DecodedValue(kind: kind, i: val)

proc getFloat(dec: var Decoder, kind: SerialisationType): DecodedValue =
  case kind
  of Float32:
    var val = 0i32
    if not dec.data.read(val):
      raise incorrectData("Could not read a float32", dec.pos)
    dec.pos += sizeof(float32)
    DecodedValue(kind: Float32, f: cast[float32](val))
  of Float64:
    var val = 0i64
    if not dec.data.read(val):
      raise incorrectData("Could not read a float64.", dec.pos)
    dec.pos += sizeof(float64)
    DecodedValue(kind: Float64, f: cast[float](val))
  else:
    doAssert false, "Somehow got into float logic with: " & $kind
    DecodedValue()

proc getString(dec: var Decoder): DecodedValue=
  var ind = 0
  dec.pos += dec.data.readLeb128(ind)

  if ind notin 0..dec.strs.high:
    # It has not been read into yet
    dec.readString()

  DecodedValue(kind: String, str: dec.getStr(ind).cstring, str_length: dec.getStr(ind).len)


proc getDispatch(dec: var Decoder, kind: SerialisationType): DecodedValue =
  case kind
  of Bool..Int8:
    dec.getByte(kind)
  of Int16..Int64:
    dec.getInt(kind)
  of Float32, Float64:
    dec.getFloat(kind)
  of String:
    dec.getString()
  of Struct:
    DecodedValue(kind: Struct)
  of Array:
    DecodedValue(kind: Array)
  of Option:
    DecodedValue(kind: Option)
  else:
    raise incorrectData(fmt"Cannot dump type of unknown serialisation {$kind}.", dec.pos)


proc decoder_next*(decoder: DecoderState, val: var DecodedValue): VsbfErrorKind {.exporter, expose.} =
  try:
    let (typ, nameInd) = decoder.decoder.typeNamePair()
    val = decoder.decoder.getDispatch(typ)
    None
  except VsbfError as e:
    e.kind



makeHeader("libvsbf.h")
