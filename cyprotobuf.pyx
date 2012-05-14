# cython: profile=False

from inspect import isclass
from libc.stdlib cimport *
from cpython cimport Py_DECREF, Py_INCREF

cdef extern from "Python.h":
    object PyString_FromStringAndSize(char *v, int len)

cdef extern from *:
    ctypedef int int64 "int64_t"
    ctypedef int uint64 "uint64_t"
    ctypedef int uint8 "uint8_t"

##
## forward declarations
##

cdef struct DataBlock:
    char *data
    int start
    int end

##
## Wire Types
##
## Used to work out a field's length
##
ctypedef int WireTypeLenFn(DataBlock *block) except -1

cdef struct WireType:
    int id
    WireTypeLenFn get_length

# VarInt Wire Type
cdef WireType VarIntWireType

cdef int VarIntWireType_get_length(DataBlock *block) except -1:
    cdef char *data
    cdef int start, end, l, idx
    data = block.data
    start = block.start
    end = block.end
    l = 1
    for idx from start <= idx < end:
        if data[idx] & 0x80:
            l += 1
        else:
            return l
    raise IndexError()

VarIntWireType = WireType(0, VarIntWireType_get_length)

# Fixed32 Wire Type
cdef WireType Fixed32WireType

cdef int Fixed32WireType_get_length(DataBlock *block) except -1:
    return 4

Fixed32WireType = WireType(5, Fixed32WireType_get_length)

# Fixed64 Wire Type
cdef WireType Fixed64WireType

cdef int Fixed64WireType_get_length(DataBlock *block) except -1:
    return 8

Fixed64WireType = WireType(1, Fixed64WireType_get_length)

# LengthDelim Wire Type
cdef WireType LengthDelimWireType

cdef int LengthDelimWireType_get_length(DataBlock *block) except -1:
    # decode the length, then rewind
    cdef int start, l
    start = block.start
    l = decode_straight(block)
    l += block.start - start
    block.start = start
    return l

LengthDelimWireType = WireType(2, LengthDelimWireType_get_length)

cdef WireType InvalidWireType = WireType(-1, NULL, NULL)
cdef WireType wire_types[8]
wire_types[0] = VarIntWireType
wire_types[1] = Fixed64WireType
wire_types[2] = LengthDelimWireType
wire_types[3] = InvalidWireType 
wire_types[4] = InvalidWireType 
wire_types[5] = Fixed32WireType 
wire_types[6] = InvalidWireType 
wire_types[7] = InvalidWireType 

##
## decoding
##

cdef int64 decode_straight(DataBlock *block) except? -1:
    cdef char *data
    cdef int64 c, val
    cdef int start, end, idx, s
    data = block.data
    start = block.start
    end = block.end
    val = 0
    s = 0
    for idx from start <= idx < end:
        c = data[idx]
        val |= (c & 0x7f) << s
        #print '%016x' % val
        if c & 0x80:
            s += 7
        else:
            block.start = idx + 1
            return val
    raise IndexError()

cdef int64 decode_zigzag(DataBlock *block) except? -1:
    cdef int64 val
    val = decode_straight(block)
    return ((val >> 1) ^ (-(val & 1)))

cdef object decode_string(DataBlock *block):
    cdef int l = decode_straight(block)
    cdef int start = block.start
    cdef int end = start + l
    if end > block.end:
        raise IndexError()
    block.start = end
    return block.data[start:end]

##
## encoding
##

cdef object encode_straight(int64 i):
    cdef object res = ''
    cdef uint8 buf[10]
    cdef int idx
    cdef uint64 u
    u = i
    idx = 0
    while u > 0x7f:
        buf[idx]= (0x80 | (u & 0x7f))
        u >>= 7
        idx += 1
    buf[idx] = u
    return PyString_FromStringAndSize(<char *>buf, idx + 1)

cdef object encode_zigzag(int64 i):
    return encode_straight((i << 1) ^ (i < 0 and -1 or 0))

cdef object encode_string(object s):
    return encode_straight(len(s)) + s

##
## Field flags
##

cdef enum Flags:
    REQUIRED = 0
    OPTIONAL
    REPEATED

required = REQUIRED
optional = OPTIONAL
repeated = REPEATED

##
## Field types
##

# 0	Varint	int32, int64, uint32, uint64, sint32, sint64, bool, enum
# 1	64-bit	fixed64, sfixed64, double
# 2	Length-delimited	string, bytes, embedded messages, packed repeated fields
# 3	Start group	groups (deprecated)
# 4	End group	groups (deprecated)
# 5	32-bit	fixed32, sfixed32, float

ctypedef object FieldTypeEncodeFn(object value)
ctypedef object FieldTypeDecodeFn(DataBlock *block)

cdef struct FieldTypeStruct:
    WireType wire_type
    FieldTypeEncodeFn encode
    FieldTypeDecodeFn decode

cdef class FieldType:
    cdef FieldTypeStruct fts

cdef object make_field_type(FieldTypeStruct fts):
    cdef FieldType inst
    inst = FieldType()
    inst.fts = fts
    return inst

# int32 and int64
cdef object FieldTypeStraightEncode(object value):
    return encode_straight(value)

cdef object FieldTypeStraightDecode(DataBlock *block):
    return decode_straight(block)

type_int32 = make_field_type(FieldTypeStruct(VarIntWireType, FieldTypeStraightEncode, FieldTypeStraightDecode))
type_int64 = type_int32

# uint32 and uint64 and enum
cdef object FieldTypeStraightEncodeU(object value):
    return encode_straight(value)

cdef object FieldTypeStraightDecodeU(DataBlock *block):
    return <uint64>decode_straight(block)

type_uint32 = make_field_type(FieldTypeStruct(VarIntWireType, FieldTypeStraightEncodeU, FieldTypeStraightDecodeU))
type_uint64 = type_uint32
type_enum = type_uint32

# sint32 and sint64
cdef object FieldTypeZigzagEncode(object value):
    return encode_zigzag(value)

cdef object FieldTypeZigzagDecode(DataBlock *block):
    return decode_zigzag(block)

type_sint32 = make_field_type(FieldTypeStruct(VarIntWireType, FieldTypeZigzagEncode, FieldTypeZigzagDecode))
type_sint64 = type_sint32

# bool
cdef object FieldTypeBoolEncode(object value):
    return encode_straight(value and 1 or 0)

cdef object FieldTypeBoolDecode(DataBlock *block):
    return decode_straight(block) and True or False

type_bool = make_field_type(FieldTypeStruct(VarIntWireType, FieldTypeBoolEncode, FieldTypeBoolDecode))

# string and bytes
cdef object FieldTypeStringEncode(object value):
    return encode_string(value)

cdef object FieldTypeStringDecode(DataBlock *block):
    return decode_string(block)

type_string = make_field_type(FieldTypeStruct(LengthDelimWireType, FieldTypeStringEncode, FieldTypeStringDecode))
type_bytes = type_string

# message
cdef FieldTypeStruct message_field_type_struct = FieldTypeStruct(LengthDelimWireType, NULL, NULL)

# Field class
cdef struct Field:
    int flag
    void *message
    FieldTypeStruct fts
    void *name
    int id

cdef class Fields:
    cdef int n_fields
    cdef Field *fields

    def __init__(self, *field_decls):
        self.n_fields = len(field_decls)
        self.fields = <Field *>malloc(sizeof(Field) * self.n_fields)

        cdef FieldTypeStruct fts
        cdef void *message
        for idx, (flag, type, name, id) in enumerate(field_decls):
            if isclass(type) and issubclass(type, Message):
                message = <void *>type
                Py_INCREF(type)
                fts = message_field_type_struct
            else:
                message = NULL
                fts = (<FieldType>type).fts
            Py_INCREF(name)
            self.fields[idx] = Field(flag, message, fts, <void *>name, id)

    def __dealloc__(self):
        cdef Field *field
        cdef Field *fields = self.fields
        cdef int n_fields =  self.n_fields
        cdef int idx
        for idx from 0 <= idx < n_fields:
            field = &fields[idx]
            if field.message != NULL:
                Py_DECREF(<object>field.message)
            Py_DECREF(<object>field.name)
        free(self.fields)


##
## The Message class
##

class Message(object):
    def dumps(self):
        cdef Field *field
        cdef Field *fields = (<Fields>self._fields).fields
        cdef int n_fields =  (<Fields>self._fields).n_fields
        cdef FieldTypeEncodeFn *encode
        cdef int wire_type_id, idx
        data = ''
        for idx from 0 <= idx < n_fields:
            field = &fields[idx]
            wire_type_id = field.fts.wire_type.id
            if field.message != NULL:
                message = <object>field.message
            else:
                encode = field.fts.encode
            value = getattr(self, <object>field.name)
            if field.flag == REPEATED:
                items = value
            else:
                items = value is not None and (value,) or ()
            for item in items:
                # add the id
                data += encode_straight((field.id << 3) | wire_type_id)
                # add the encoded field
                if field.message != NULL:
                    data += encode_string(item.SerializeToString())
                else:
                    data += encode(item)
        return data

    def loads(self, data, start=0, end=-1):
        if end < 0:
            end += len(data) + 1

        cdef DataBlock block = DataBlock(data, start, end)
        return _ParseFromString(self, &block)


cdef object _ParseFromString(object self, DataBlock *block):
    self.Clear()

    # while we have remaining data, parse a field
    cdef int64 field_info, field_id, wire_type
    cdef int l, idx
    cdef int orig_end = block.end
    cdef Fields _fields = <Fields>self._fields
    cdef Field *field
    cdef Field *fields = _fields.fields
    cdef int n_fields =  _fields.n_fields
    while block.start < orig_end:
        field_info = decode_straight(block)
        field_id = field_info >> 3
        wire_type = field_info & 0x7

        # find the field
        for idx from 0 <= idx < n_fields:
            field = &fields[idx]
            if field.id == field_id:
                if field.message != NULL:
                    # get its end
                    msg_len = decode_straight(block)
                    block.end = block.start + msg_len
                    if block.end > orig_end:
                        raise IndexError()
                    val = (<object>field.message).__new__(<object>field.message)
                    _ParseFromString(val, block)
                    block.end = orig_end
                else:
                    val = field.fts.decode(block)
                if field.flag == REPEATED:
                    getattr(self, <object>field.name).append(val)
                else:
                    setattr(self, <object>field.name, val)
                break
        else:
            # unknown field, skip it
            if (0 <= wire_type < 8) and wire_types[wire_type].get_length != NULL:
                l = wire_types[wire_type].get_length(block)
                block.start += l
            else:
                raise IndexError()

    return True

