## This walks through the VBSF and prints the structure stored inside
import shared, decoders
import std/[options, strutils, strformat]

proc indented(amount: int): string = "  ".repeat(amount)


proc dumpInteger(dec: var Decoder, kind: SerialisationType, indent: int): string =
  var val: int
  dec.pos += dec.data.readleb128(val)
  $val

proc dumpFloat(dec: var Decoder, kind: SerialisationType, indent: int): string =
  case kind
  of Float32:
    var val = 0i32
    if not dec.data.read(val):
      raise incorrectData("Could not read a float32", dec.pos)
    dec.pos += sizeof(float32)
    $cast[float32](val)
  of Float64:
    var val = 0i64
    if not dec.data.read(val):
      raise incorrectData("Could not read a float64.", dec.pos)
    dec.pos += sizeof(float64)
    $cast[float](val)
  else:
    doAssert false, "Somehow got into float logic with: " & $kind
    ""

proc dumpString(dec: var Decoder, indent: int): string =
  var ind = 0
  dec.pos += dec.data.readLeb128(ind)

  if ind notin 0..dec.strs.high:
    # It has not been read into yet
    dec.readString()

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
    raise incorrectData(fmt"Cannot dump type of unknown serialisation {$kind}.", dec.pos)

proc dumpStruct(dec: var Decoder, indent: int): string =
  result.add $Struct & "\n"
  while not(dec.atEnd) and (var (typ, _) = dec.peekTypeNamePair(); typ) != EndStruct:
    var name = none(int)
    (typ, name) = dec.typeNamePair()

    result.add indent.indented()
    result.add " "
    result.add $typ
    result.add " "

    if name.isSome:
      result.add dec.strs[name.get]
      result.add ": "
    try:
      result.add dec.dumpDispatch(typ, indent + 1)
      result.add "\n"
    except VsbfError:
      echo "Failed Partial Dump: "
      echo result
      raise


  if (let (typ, _) = dec.typeNamePair(); typ) != EndStruct: # Pops the end and ensures it's correct'
    raise incorrectData("Invalid struct expected EndStruct.", dec.pos)


proc dumpArray(dec: var Decoder, indent: int): string =
  var len: int
  dec.pos += dec.data.readLeb128(len)
  if len > 0:
    result = "["
    for _ in 0..<len:
      let (typ, nameInd) = dec.typeNamePair()
      if nameInd.isSome:
        raise incorrectData("No name expected for array element, but got one.", dec.pos)
      result.add "\n"
      result.add indented(indent + 1)
      result.add dec.dumpDispatch(typ, indent + 1)

    result.add  '\n'
    result.add "  ".repeat(indent - 2) & " ]"
  else:
    result = "[]"

proc dumpOption(dec: var Decoder, indent: int): string =
  let isValNone = dec.data[0] == 0
  inc dec.pos
  result = indented(indent)
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


when isMainModule:
  import std/os
  let file = open(paramStr(1), fmRead)
  var buffer = newSeq[byte](file.getFileSize())
  discard file.readBuffer(buffer[0].addr, buffer.len)
  var decoder = Decoder.init(buffer)
  echo decoder.dump()
  file.close()


