#!/usr/bin/env python

# This compiler uses protoc to generate a FileDesciptorSet
# and uses that to generate a wrapper using the cyprotobuf
# library.

import sys
import os
import subprocess
import re
import tempfile

from google.protobuf.descriptor_pb2 import FileDescriptorSet
from google.protobuf.descriptor import FieldDescriptor

TYPEMAP = {
		FieldDescriptor.TYPE_BOOL : 'type_bool',
		FieldDescriptor.TYPE_BYTES : 'type_bytes',
		FieldDescriptor.TYPE_DOUBLE : None,
		FieldDescriptor.TYPE_ENUM : 'type_enum',
		FieldDescriptor.TYPE_FIXED32 : None,
		FieldDescriptor.TYPE_FIXED64 : None,
		FieldDescriptor.TYPE_FLOAT : 'type_float',
		FieldDescriptor.TYPE_GROUP : None,
		FieldDescriptor.TYPE_INT32 : 'type_int32',
		FieldDescriptor.TYPE_INT64 : 'type_int64',
		FieldDescriptor.TYPE_SFIXED32 : None,
		FieldDescriptor.TYPE_SFIXED64 : None,
		FieldDescriptor.TYPE_SINT32 : 'type_sint32',
		FieldDescriptor.TYPE_SINT64 : 'type_sint64',
		FieldDescriptor.TYPE_STRING : 'type_string',
		FieldDescriptor.TYPE_UINT32 : 'type_uint32',
		FieldDescriptor.TYPE_UINT64 : 'type_uint64',
		}

LABELMAP = {
		FieldDescriptor.LABEL_REQUIRED : 'required',
		FieldDescriptor.LABEL_OPTIONAL : 'optional',
		FieldDescriptor.LABEL_REPEATED : 'repeated',
		}

class Writer:
	def __init__(self):
		self.cont = ''
	
	def ln(self, fmt = '', *args):
		if len(args):
			self.cont += fmt % args
		else:
			self.cont += fmt
		self.cont += '\n'

def generate_wrapper(outdir, proto):
	protobase = os.path.basename(proto)[:-len('.proto')]

	def typeof(field):
		if field.type == field.TYPE_MESSAGE:
			return field.type_name[1:] + ' *'
		else:
			return TYPEMAP[field.type]

	def ctypeof(field):
		if field.type == field.TYPE_MESSAGE:
			return '%s_core.%s' % (protobase, typeof(field))
		elif field.type == field.TYPE_BYTES:
			return '%s_core.%s' % (protobase, typeof(field))
		else:
			return typeof(field)

	# generate the descriptor
	tmp = tempfile.mkdtemp()
	tmpfn = os.path.join(tmp, 'tmp')
	file_set_content = ''
	try:
		res = subprocess.Popen(['protoc', '-o', tmpfn, proto]).wait()
		if res != 0:
			return False
		f = open(tmpfn, 'r')
		try:
			file_set_content = f.read()
		finally:
			f.close()
	finally:
		if os.path.exists(tmpfn):
			os.unlink(tmpfn)
		os.rmdir(tmp)

	file_set = FileDescriptorSet()
	file_set.ParseFromString(file_set_content)

	file = file_set.file[0]

	out = Writer()

	out.ln('import cyprotobuf')
	out.ln()
	out.ln()
	
	for msg in file.message_type:
		out.ln('class %s(cyprotobuf.Message):' % msg.name)
		out.ln('    _fields = cyprotobuf.Fields(')
		for field in msg.field:
			out.ln('        (cyprotobuf.%s, %s, %s, %s),',
					LABELMAP[field.label],
					field.type == field.TYPE_MESSAGE and field.type_name[1:] or ('cyprotobuf.' + TYPEMAP[field.type]),
					repr(field.name),
					field.number)
		out.ln('    )')
		out.ln()

		out.ln('    __slots__ = [ %s ]',
				', '.join([ repr(field.name) for field in msg.field ]))
		out.ln()

		out.ln('    def __init__(%s):',
				', '.join(['self'] + ['%s=None' % field.name for field in msg.field]))
		for field in msg.field:
			if field.label == FieldDescriptor.LABEL_REPEATED:
				out.ln('        self.%s = %s or []', field.name, field.name)
			else:
				out.ln('        self.%s = %s', field.name, field.name)
		if not msg.field:
			out.ln('        pass')
		out.ln()

	f = open(os.path.join(outdir, protobase + '.py'), 'w')
	f.write(out.cont)
	f.close()

	return True


if __name__ == '__main__':
	# generate the cython definitions
	outdir = '.'
	for arg in sys.argv[1:]:
		m = re.match('--c_out=(.*)', arg)
		if m:
			outdir = m.group(1)
			break
	
	for arg in sys.argv[1:]:
		if arg.startswith('-'):
			continue
		if not generate_wrapper(outdir, arg):
			break
