# build_tarballs.jl — BinaryBuilder recipe for libmeddly_c
#
# libmeddly_c is the C ABI shim (c/meddly_c.cpp) that Meddly.jl dlopens.  It
# statically links MEDDLY (the C++ decision-diagram library) inside itself, so
# this single JLL is all Meddly.jl needs at runtime — no source build, no
# autotools, no C++ compiler on the user's machine.
#
# Route B (local build + self-host) first; the same recipe is later reusable for
# a Yggdrasil PR (Route A).  Platforms: Linux + macOS only (see plan).
#
# Run:
#   julia --project=build build/build_tarballs.jl --verbose --debug x86_64-linux-gnu-cxx11
#   julia --project=build build/build_tarballs.jl --verbose      # all platforms
#   julia --project=build build/build_tarballs.jl --verbose --deploy="JuliaReliab/libmeddly_c_jll.jl"

using BinaryBuilder

name    = "libmeddly_c"
version = v"0.5.0"          # follows the Meddly.jl release the shim comes from

# --- Sources -------------------------------------------------------------
# MEDDLY is pinned to an exact commit: it publishes no release tags, and this
# is the revision the shim is written against.  This also removes the current
# unpinned-`master` reproducibility risk.
#
# The shim itself lives in the Meddly.jl repo under c/.  It is fetched from the
# git tag that matches `version` — TAG Meddly.jl v0.5.0 first, then fill in the
# archive's sha256 below (the build errors and prints the real hash if wrong).
sources = [
    GitSource("https://github.com/asminer/meddly.git",
              "f8a89d0f83987c88c66ee3a6623e08757debb435"),
    ArchiveSource("https://github.com/JuliaReliab/Meddly.jl/archive/refs/tags/v0.5.0.tar.gz",
                  "0000000000000000000000000000000000000000000000000000000000000000"),
]

# --- Build script (runs in the BB sandbox, one target at a time) ---------
script = raw"""
# 1. Build MEDDLY as a static, PIC library.
cd $WORKSPACE/srcdir/meddly*
autoreconf --force --install
# ac_cv_func_*_0_nonnull=yes: when cross-compiling, AC_FUNC_MALLOC/REALLOC can't
# run their probe and assume malloc/realloc are broken, substituting rpl_malloc/
# rpl_realloc (undefined here) -> compile errors. Tell configure they are fine.
./configure --prefix=$prefix --build=${MACHTYPE} --host=${target} \
    --disable-shared --enable-static --without-gmp CXXFLAGS="-O3 -fPIC" \
    ac_cv_func_malloc_0_nonnull=yes ac_cv_func_realloc_0_nonnull=yes
# examples/ #include <gmp.h> unconditionally even with --without-gmp, so build
# and install only the library subdirectory.
make -C src -j${nproc}
make install SUBDIRS=src

# 2. Build the C ABI shim, statically linking libmeddly.a into it.
cd $WORKSPACE/srcdir/Meddly.jl*/c
$CXX -O2 -std=c++14 -fPIC -I$prefix/include -shared \
    -o $libdir/libmeddly_c.$dlext meddly_c.cpp $prefix/lib/libmeddly.a

# 3. Ship MEDDLY's license (LGPL v3, with its GPL base).
install_license $WORKSPACE/srcdir/meddly*/COPYING.LESSER $WORKSPACE/srcdir/meddly*/COPYING
"""

# --- Platforms: Linux + macOS only ---------------------------------------
# expand_cxxstring_abis handles the libstdc++ cxx11 string ABI split on Linux.
platforms = expand_cxxstring_abis([
    Platform("x86_64",  "linux"),
    Platform("aarch64", "linux"),
    Platform("x86_64",  "macos"),
    Platform("aarch64", "macos"),
])

# --- Products ------------------------------------------------------------
products = [
    LibraryProduct("libmeddly_c", :libmeddly_c),
]

# --- Dependencies --------------------------------------------------------
# GMP is disabled (--without-gmp).  The shim links libstdc++ and libgcc_s;
# declare CompilerSupportLibraries_jll so those resolve to a JLL instead of the
# host's system libraries (otherwise the auditor warns that libgcc_s.so.1 can't
# be auto-mapped).
dependencies = [
    Dependency("CompilerSupportLibraries_jll"),
]

# MEDDLY is C++14; BinaryBuilder's default GCC (4.8.5) predates full C++14, so
# require a newer compiler.
build_tarballs(ARGS, name, version, sources, script, platforms, products, dependencies;
               julia_compat = "1.6",
               preferred_gcc_version = v"8")
