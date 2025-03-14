import decoders, shared, encoders
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

makeHeader("libvsbf.h")
