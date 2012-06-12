from inspect import isclass
from struct import pack, unpack
import encodings


##
## Wire types
##

# wire_types[0] = VarIntWireType
# wire_types[1] = Fixed64WireType
# wire_types[2] = LengthDelimWireType
# wire_types[3] = InvalidWireType 
# wire_types[4] = InvalidWireType 
# wire_types[5] = Fixed32WireType 
# wire_types[6] = InvalidWireType 
# wire_types[7] = InvalidWireType 

##
## encoding
##

def encode_straight(i):
    res = bytes()
    u = i
    while u > 0x7f:
        res += pack('B', (0x80 | (u & 0x7f)))
        u >>= 7
    res += pack('B', u)
    return res

def encode_zigzag(i):
    return encode_straight((i << 1) ^ (i < 0 and -1 or 0))

def encode_string(s):
    data = encode_straight(len(s))
    if isinstance(s, bytes):
        data += s
    else:
        data += encodings.utf_8.encode(s)[0]
    return data

##
## Field flags
##

required = 0
optional = 1
repeated = 2

##
## Field types
##

# 0	Varint	int32, int64, uint32, uint64, sint32, sint64, bool, enum
# 1	64-bit	fixed64, sfixed64, double
# 2	Length-delimited	string, bytes, embedded messages, packed repeated fields
# 3	Start group	groups (deprecated)
# 4	End group	groups (deprecated)
# 5	32-bit	fixed32, sfixed32, float

# ints

type_int32 = dict(
    wire_type = 0,
    encode = encode_straight,
)

type_int64 = type_int32

# bool

type_bool = dict(
    wire_type = 0,
    encode = lambda x: encode_straight(1 if x else 0),
)

# string and bytes

type_string = dict(
    wire_type = 2,
    encode = encode_string,
)
type_bytes = type_string

# float

def encode_float32(value):
    tmp = pack('f', value)
    i = unpack('=i', tmp)
    return pack('>i', i[0])

type_float = dict(
    wire_type = 5,
    encode = encode_float32,
)

# message
type_message = dict(
    wire_type = 2,
    encode = lambda x: encode_string(x.dumps()),
)


# Field class
class Field(object):
    def __init__(self, flag, type, name, id):
        self.flag = flag
        self.type = type_message if isclass(type) and issubclass(type, Message) else type
        self.name = name
        self.id = id

def Fields(*field_decls):
    return [Field(*args) for args in field_decls]

##
## The Message class
##

class Message(object):
    def clear(self):
        for field in self._fields:
            setattr(self, field.name, [] if field.flag == repeated else None)

    def dumps(self):
        data = bytes()
        for field in self._fields:
            wire_type_id = field.type['wire_type']
            value = getattr(self, field.name)
            if field.flag == repeated:
                items = value
            else:
                items = value is not None and (value,) or ()
            for item in items:
                # add the id
                data += encode_straight((field.id << 3) | wire_type_id)
                # add the encoded field
                data += field.type['encode'](item)
        return data
