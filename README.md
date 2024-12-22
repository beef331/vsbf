# vsbf
A very simple binary format


## Specification
As the name implies it's a simple binary format.

Every file starts with `vsbf` followed by two bytes for the version akin to wasm.
All integers are encoded using leb128 encoding.
Every entry is prefixed with a type, the most significant bit of this type id is whether this is a 'field' value.

### Bool
TypeId - byte

### Int(N)
TypeId - data(leb128)

Example:
```
76 73 62 66 01 00 68 e4  00
```

`76 73 62 66` is `vsbf`.
`01 00` is the version of 1.0.
`68` is the typeId with the most significant bit being set to 0.
This indicates it's an `Int64` typed integer with no name.

### Float32
TypeId - byte[4]

### Float64
TypeId - byte[8]

### String
TypeId - index(leb128) - ?(len(leb128) - char[?])

### Arrays
TypeId - len(leb128) - ?entries

```
76 73 62 66 01 00 6c 03 68 e4 00 68 c8 01 68 ac 02
```

Skipping over the header to `6c` one can see an `Array` that has no name.
Following that `03` which is the number of elements this array has (again leb128 encoded).
Finally there are 3 integers `68 e4 00 68 c8 01 68 ac 02 ` which are `Int64 100, Int64 200, Int64 300`.


### Structs
TypeId - ?fields - EndStruct

```
00000000  76 73 62 66 01 00 6d ed  00 05 63 68 69 6c 64 e8  |vsbf..m...child.|
00000010  01 01 61 00 6e ed 02 0a  6f 74 68 65 72 43 68 69  |..a.n...otherChi|
00000020  6c 64 e8 01 00 6e 6e                              |ld...nn|

```


`6d` indicates a `Struct` typed block.
`ed` is an named `Int64` typed block.
After that the string name index is `00`, as this string has not yet been printed one can see the length and string stored. The value of which is `child`
With further parsing the string `otherChild` will be parsed and stored at index `01`.
Important to note that VSBF only stores the first instance of a string which is why in the final integer `e8 01 00 6e 6e` there is no length or string data.


### Option
TypeId - byte - ?VSBFEntry
