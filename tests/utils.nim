import vsbf/shared

template leb*(val: SomeInteger): untyped =
  var buffer = default array[10, byte]
  let len = buffer.writeLeb128(val)
  buffer.toOpenArray(0, len - 1)

proc `&`*(a, b: static openarray[char]): array[a.len + b.len, byte] =
  result = default typeof(result)
  for i, x in a.pairs:
    result[i] = byte x

  for i, x in b.pairs:
    result[i + a.len] = byte x

proc `&`*(a, b: static openarray[byte]): array[a.len + b.len, byte] =
  result = default typeof(result)
  for i, x in a.pairs:
    result[i] = x

  for i, x in b.pairs:
    result[i + a.len] = x

proc `&`*[IDX; T: char | byte](a: static openarray[char], b: array[IDX, T]): array[a.len + IDX, byte] =
  result = default typeof(result)
  for i, x in a.pairs:
    result[i] = byte x

  for i, x in b.pairs:
    result[i + b.len] = byte x

proc `&`*[T: char | byte](a: static openArray[T], b: byte | char): array[a.len + 1, byte] =
  result = default typeof(result)
  for i, x in a.pairs:
    result[i] = byte x

  result[^1] = byte b

proc `&`*[IDX; T](a: array[IDX, T], b: static openArray[byte]): array[a.len + b.len, byte] =
  result = default typeof(result)
  for i, x in a.pairs:
    result[i] = byte x

  for i, x in b.pairs:
    result[i + a.len] = byte x


proc `&`*[IDX](a: array[IDX, byte], b: byte): array[a.len + 1, byte] =
  result = default typeof(result)
  for i, x in a.pairs:
    result[i] = byte x

  result[^1] = byte b



proc `&`*[IDX, IDY; T, Y: byte | char](a: array[IDX, T], b: array[IDY, Y]): array[a.len + b.len, byte] =
  result = default typeof(result)
  for i, x in a.pairs:
    result[i] = byte x

  for i, x in b.pairs:
    result[a.len + i] = byte(x)


proc `&`*[IDX, IDY; T: byte | char](a: array[IDX, T], b: array[IDY, byte]): array[a.len + b.len, byte] =
  result = default typeof(result)
  for i, x in a.pairs:
    result[i] = byte x

  for i, x in b.pairs:
    result[a.len + i] = byte(x)



proc `&`*[IDX](a: array[IDX, byte], b: static string): array[a.len + b.len, byte] =
  result = default typeof(result)
  for i, x in a.pairs:
    result[i] = byte x

  for i, x in b.pairs:
    result[a.len + i] = byte(x)
