LIB_SUFFIX=.so
OBJ_SUFFIX=.o
PYTHON_CXXFLAGS=$(shell python-config --cflags)
PYTHON_LDFLAGS=$(shell python-config --ldflags)
PYTHON_LIB_LDFLAGS=
LIB_CXXFLAGS=-fPIC
LIB_LDFLAGS=-shared
STRIP=strip

TARGETS=cyprotobuf$(LIB_SUFFIX)

ifdef CONFIG
	include $(CONFIG)
endif


all: $(TARGETS)

strip: all
	$(STRIP) $(TARGETS)

clean:
	-rm *.c *.o *.so *.obj *.pyd

%$(LIB_SUFFIX): %$(OBJ_SUFFIX)
	$(CC) -o $@ $< $(LIB_LDFLAGS) $(PYTHON_LIB_LDFLAGS) $(EXTRA_LDFLAGS)

%$(OBJ_SUFFIX): %.c
	$(CC) -c -o $@ $^ $(LIB_CXXFLAGS) $(PYTHON_CXXFLAGS) $(EXTRA_CXXFLAGS)

%.c: %.pyx
	cython $<

%.c: %.py
	cython $<
