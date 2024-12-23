# vsbf
A very simple binary format


## Specification
As the name implies it's a simple binary format.

Every file starts with `vsbf` followed by two bytes for the version akin to wasm.
All integers are encoded using leb128 encoding.
Every entry is prefixed with a type, the most significant bit of this type id is whether this is a 'field' value.

### Bool
TypeId - byte

```
00000000  76 73 62 66 01 00 00 00                           |vsbf....|
```

`00` indicates a `Bool`.
The following byte is the bool's raw value.

### Int(N)
TypeId - data(leb128)

Example:
```
00000000  76 73 62 66 01 00 04 e4 00                       |vsbf.....|
```

`76 73 62 66` is `vsbf`.
`01 00` is the version of 1.0.
`04` is the typeId with the most significant bit being set to 0.
This indicates it's an `Int64` typed integer with no name.
`e4 00` is 100 in leb128 encoding.

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
