# Makefile for libmeddly_c — C ABI shim around the MEDDLY C++ library.
#
# Usage:
#   make                          # build with default MEDDLY prefix
#   make MEDDLY_PREFIX=/opt/meddly
#
# The resulting libmeddly_c.so (Linux) or libmeddly_c.dylib (macOS)
# must be on the dynamic linker search path (or LD_LIBRARY_PATH /
# DYLD_LIBRARY_PATH) when running Julia.

MEDDLY_PREFIX ?= /usr/local
MEDDLY_INC    ?= $(MEDDLY_PREFIX)/include
MEDDLY_LIB    ?= $(MEDDLY_PREFIX)/lib

CXX      := g++
CXXFLAGS := -O2 -std=c++14 -fPIC -I$(MEDDLY_INC)
LDFLAGS  := -L$(MEDDLY_LIB) -lmeddly

UNAME := $(shell uname)
ifeq ($(UNAME), Darwin)
    EXT    := dylib
    SHARED := -dynamiclib -install_name @rpath/libmeddly_c.$(EXT)
    RPATH  :=
else
    EXT    := so
    SHARED := -shared
    RPATH  := -Wl,-rpath,$(MEDDLY_LIB)
endif

TARGET := libmeddly_c.$(EXT)

all: $(TARGET)

$(TARGET): meddly_c.cpp meddly_c.h
	$(CXX) $(CXXFLAGS) $(SHARED) -o $@ meddly_c.cpp $(LDFLAGS) $(RPATH)

clean:
	rm -f $(TARGET)

.PHONY: all clean
