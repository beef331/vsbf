# vsbf
A very simple binary format. Practically a not invented here messagepack!


## Specification
As the name implies it's a simple binary format.

Every entry is prefixed with a type, the most significant bit of this type id is whether this is a 'field' value.
All non 8 bit integers are encoded using leb128 encoding.

### Header
```
00000000  76 73 62 66 01 00
```

`76 73 62 66` is `vsbf` which every file requires.

`01 00` is the version of 1.0 which is also required.

### Bool
TypeId - byte

```
00000000  76 73 62 66 01 00 00 00                           |vsbf....|
```

`00` indicates a `Bool`.
The following byte is the bool's raw value.

### Int16, Int32, Int64
TypeId - data(leb128)

Example:
```
00000000  76 73 62 66 01 00 04 e4 00                       |vsbf.....|
```

`04` is the typeId with the most significant bit being set to 0.

In this case it an `Int64` typed integer with no name.

`e4 00` is `100` in leb128 encoding.

### Float32
TypeId - byte[4]

```
00000000  76 73 62 66 01 00 05 db  0f 49 40                 |vsbf.....I@|
```

`05` indicates `Float32`.
The next 4 bytes are the float's raw value.

### Float64
TypeId - byte[8]

```
00000000  76 73 62 66 01 00 05 db  0f 49 40                 |vsbf.....I@|
```

`06` indicates `Float64`.
The next 8 bytes are the float's raw value.

### String
TypeId - index(leb128) - ?(len(leb128) - char[?])

```
00000000  76 73 62 66 01 00 07 00  05 68 65 6c 6c 6f        |vsbf.....hello|
```

`07` indicates `String`.

The index of the string follows the type `00` in this case.

Following that if the string was not already encoded the string data must follow the index.

`05` is the leb128 encoded length of `5`, the raw data `hello` follows that.

Strings have no encoding and are expected to store `len` before as number of bytes .


### Arrays
TypeId - len(leb128) - ?entries

```
00000000  76 73 62 66 01 00 08 03  04 e4 00 04 c8 01 04 ac  |vsbf............|
00000010  02                                                |.|
```

Skipping over the header to `08` one can see an `Array` that has no name.

Following that `03` which is the number of elements this array has (again leb128 encoded).

Finally there are 3 integers ` 04 e4 00 04 c8 01 04 ac 01` which are `Int64 100, Int64 200, Int64 300`.


### Structs
TypeId - ?fields - EndStruct

```
00000000  76 73 62 66 01 00 09 84  00 05 63 68 69 6c 64 e4  |vsbf......child.|
00000010  00 89 01 0a 6f 74 68 65  72 43 68 69 6c 64 84 00  |....otherChild..|
00000020  e4 00 0a 0a                                       |....|
```


`09` indicates an unamed `Struct` typed block.

`84` is an named `Int64` typed block.

After that the string name index is `00`, as this string has not yet been printed one can see the length and string stored. The value of which is `child`

With further parsing the string `otherChild` will be parsed and stored at index `01`.

Important to note that VSBF only stores the first instance of a string which is why in the final integer `84 00 e4 00` there is no length or string data.

Finally there are two `0a` which are the end struct indication, these are required for navigation over the data without specification of the fields.

In Nim that means this struct can be represented by `((child: 100), otherChild: (child: 100))`.


### Option
TypeId - byte - ?VSBFEntry

```
00000000  76 73 62 66 01 00 0b 01  04 00                    |vsbf......|
```

`0b` indicates an unnamed `Option` block, the next byte indicates whether there is a value.

`01` means there is a value and `00` means there is not one.

Following a `01` there must be a valid VSBF tag and entry.

In this case it is `04` which is an `Int64` with the value `0`



## Dumper

Along with this package is `vsbfdumper` which will print a vsbf buffer in a human readable format akin to JSON.


Using the following Nim object

```nim

type
  MyObject = object
    x, y: int
    name: string
    age: int
    talents: array[6, string]
    children: seq[MyObject]
    pets: seq[string]
    letters: set[range['a'..'z']]
    dontSave {.skipSerialization.}: ref int

var
  obj =
    MyObject(
      x: 100,
      y: 0,
      age: 42,
      name: "Jimbo",
      talents: ["Jumping", "Running", "", "", "pets", "age"],
      pets: @["Sam", "Diesel"],
      letters: {'a'..'z'},
      children: newSeq[MyObject](5),
      dontSave: new int
    )

```

encoded will generate a raw VSBF of

```
00000000  76 73 62 66 01 00 09 84  00 01 78 e4 00 84 01 01  |vsbf......x.....|
00000010  79 00 87 02 04 6e 61 6d  65 03 05 4a 69 6d 62 6f  |y....name..Jimbo|
00000020  84 04 03 61 67 65 2a 88  05 07 74 61 6c 65 6e 74  |...age*...talent|
00000030  73 06 07 06 07 4a 75 6d  70 69 6e 67 07 07 07 52  |s....Jumping...R|
00000040  75 6e 6e 69 6e 67 07 08  00 07 08 07 09 04 70 65  |unning........pe|
00000050  74 73 07 04 88 0a 08 63  68 69 6c 64 72 65 6e 05  |ts.....children.|
00000060  09 84 00 00 84 01 00 87  02 08 84 04 00 88 05 06  |................|
00000070  07 08 07 08 07 08 07 08  07 08 07 08 88 0a 00 88  |................|
00000080  09 00 83 0b 07 6c 65 74  74 65 72 73 00 0a 09 84  |.....letters....|
00000090  00 00 84 01 00 87 02 08  84 04 00 88 05 06 07 08  |................|
000000a0  07 08 07 08 07 08 07 08  07 08 88 0a 00 88 09 00  |................|
000000b0  83 0b 00 0a 09 84 00 00  84 01 00 87 02 08 84 04  |................|
000000c0  00 88 05 06 07 08 07 08  07 08 07 08 07 08 07 08  |................|
000000d0  88 0a 00 88 09 00 83 0b  00 0a 09 84 00 00 84 01  |................|
000000e0  00 87 02 08 84 04 00 88  05 06 07 08 07 08 07 08  |................|
000000f0  07 08 07 08 07 08 88 0a  00 88 09 00 83 0b 00 0a  |................|
00000100  09 84 00 00 84 01 00 87  02 08 84 04 00 88 05 06  |................|
00000110  07 08 07 08 07 08 07 08  07 08 07 08 88 0a 00 88  |................|
00000120  09 00 83 0b 00 0a 88 09  02 07 0c 03 53 61 6d 07  |............Sam.|
00000130  0d 06 44 69 65 73 65 6c  83 0b ff ff ff 1f 0a     |..Diesel.......|
```

using `vsbfdumper` on this emits the following:


```
Struct
   Int64 x: 100
   Int64 y: 0
   String name: "Jimbo"
   Int64 age: 42
   Array talents: [
        "Jumping"
        "Running"
        ""
        ""
        "pets"
        "age"
   ]
   Array children: [
        Struct
           Int64 x: 0
           Int64 y: 0
           String name: ""
           Int64 age: 0
           Array talents: [
                ""
                ""
                ""
                ""
                ""
                ""
           ]
           Array children: []
           Array pets: []
           Int32 letters: 0

        Struct
           Int64 x: 0
           Int64 y: 0
           String name: ""
           Int64 age: 0
           Array talents: [
                ""
                ""
                ""
                ""
                ""
                ""
           ]
           Array children: []
           Array pets: []
           Int32 letters: 0

        Struct
           Int64 x: 0
           Int64 y: 0
           String name: ""
           Int64 age: 0
           Array talents: [
                ""
                ""
                ""
                ""
                ""
                ""
           ]
           Array children: []
           Array pets: []
           Int32 letters: 0

        Struct
           Int64 x: 0
           Int64 y: 0
           String name: ""
           Int64 age: 0
           Array talents: [
                ""
                ""
                ""
                ""
                ""
                ""
           ]
           Array children: []
           Array pets: []
           Int32 letters: 0

        Struct
           Int64 x: 0
           Int64 y: 0
           String name: ""
           Int64 age: 0
           Array talents: [
                ""
                ""
                ""
                ""
                ""
                ""
           ]
           Array children: []
           Array pets: []
           Int32 letters: 0

   ]
   Array pets: [
        "Sam"
        "Diesel"
   ]
   Int32 letters: 67108863
```
