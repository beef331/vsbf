## This walks through the VBSF and prints the structure stored inside
import shared, decoders
import std/[options, strutils]

proc indented(amount: int): string = "  ".repeat(amount)


proc dumpInteger(dec: var Decoder, kind: SerialisationType, indent: int): string =
  var val: int
  dec.pos += dec.data.readleb128(val)
  indent.indented() & $kind & ": " & $val

proc dumpFloat(dec: var Decoder, kind: SerialisationType, indent: int): string =
  var val: int
  dec.pos += dec.data.readleb128(val)
  "  ".repeat(indent) & $kind & ": " & $cast[float](val)

proc dumpString(dec: var Decoder, indent: int): string =
  var ind = 0
  dec.pos += dec.data.readLeb128(ind)

  if ind notin 0..dec.strs.high:
    # It has not been read into yet
    dec.readString()

  result = indent.indented()
  result.add '"' & dec.getStr(ind) & '"'


proc dumpStruct(dec: var Decoder, indent: int): string
proc dumpArray(dec: var Decoder, indent: int): string
proc dumpOption(dec: var Decoder, indent: int): string



proc dumpDispatch(dec: var Decoder, kind: SerialisationType, indent: int): string =
  case kind
  of Bool..Int64:
    dec.dumpInteger(kind, indent + 1)
  of Float32, Float64:
    dec.dumpFloat(kind, indent + 1)
  of Struct:
    dec.dumpStruct(indent + 1)
  of Array:
    dec.dumpArray(indent + 1)
  of Option:
    dec.dumpOption(indent + 1)
  of String:
    dec.dumpString(indent + 1)
  else:
    raise (ref VsbfError)(msg: "Cannot dump type of unknown serialisation. " & $kind)

proc dumpStruct(dec: var Decoder, indent: int): string =
  result.add indent.indented() & $Struct & "\n"
  while (var (typ, _) = dec.peekTypeNamePair; typ) != EndStruct:
    var name = none(int)
    (typ, name) = dec.typeNamePair()

    result.add indent.indented()
    if name.isSome:
      result.add dec.strs[name.get]
      result.add " "
    result.add dec.dumpDispatch(typ, 0)
    result.add "\n"

  var (typ, _) = dec.peekTypeNamePair()
  if typ == EndStruct:
    discard dec.typeNamePair()


proc dumpArray(dec: var Decoder, indent: int): string =
  var len: int
  dec.pos += dec.data.readLeb128(len)
  result.add indent.indented() & "["
  for _ in 0..<len:
    let (typ, _) = dec.typeNamePair()
    result.add "\n"
    result.add dec.dumpDispatch(typ, indent + 1)
    result.add ", "
  if result.endsWith(", "):
    result.setLen(result.high - 1)
  result.add  '\n'
  result.add indent.indented()
  result.add ']'


proc dumpOption(dec: var Decoder, indent: int): string =
  let isValNone = dec.data[0] == 0
  inc dec.pos
  result = "  ".repeat(indent)
  if isValNone:
    result.add "None"
  else:
    let (typ, _) = dec.typeNamePair()
    result.add dec.dumpDispatch(typ, indent)

proc dump*(dec: var Decoder): string =
  let (typ, nameInd) = dec.typeNamePair()
  assert typ == Struct
  assert nameInd.isNone()
  dec.dumpDispatch(typ, 0)



