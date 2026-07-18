# build_tarballs_local.jl — LOCAL smoke-test variant of build_tarballs.jl.
#
# Same recipe, but the shim is taken from the working copy's c/ directory via
# DirectorySource instead of a published git tag — so it can be built before
# tagging Meddly.jl v0.5.0 / filling the archive sha256.  Use this only for
# local verification; the canonical recipe for --deploy is build_tarballs.jl.
#
# Run one platform (no --debug: this is non-interactive):
#   julia --project=build build/build_tarballs_local.jl --verbose x86_64-linux-gnu-cxx11

using BinaryBuilder

name    = "libmeddly_c"
version = v"0.5.0"

sources = [
    GitSource("https://github.com/asminer/meddly.git",
              "f8a89d0f83987c88c66ee3a6623e08757debb435"),
    # Shim straight from the working copy; lands in $WORKSPACE/srcdir/shim/.
    DirectorySource(joinpath(@__DIR__, "..", "c"); target = "shim"),
]

script = raw"""
cd $WORKSPACE/srcdir/meddly*
autoreconf --force --install
# ac_cv_func_*_0_nonnull=yes: when cross-compiling, AC_FUNC_MALLOC/REALLOC can't
# run their probe and assume malloc/realloc are broken, substituting rpl_malloc/
# rpl_realloc (undefined here) -> compile errors. Tell configure they are fine.
./configure --prefix=$prefix --build=${MACHTYPE} --host=${target} \
    --disable-shared --enable-static --without-gmp CXXFLAGS="-O3 -fPIC" \
    ac_cv_func_malloc_0_nonnull=yes ac_cv_func_realloc_0_nonnull=yes
make -C src -j${nproc}
make install SUBDIRS=src

cd $WORKSPACE/srcdir/shim
$CXX -O2 -std=c++14 -fPIC -I$prefix/include -shared \
    -o $libdir/libmeddly_c.$dlext meddly_c.cpp $prefix/lib/libmeddly.a

install_license $WORKSPACE/srcdir/meddly*/COPYING.LESSER $WORKSPACE/srcdir/meddly*/COPYING
"""

platforms = expand_cxxstring_abis([
    Platform("x86_64",  "linux"),
    Platform("aarch64", "linux"),
    Platform("x86_64",  "macos"),
    Platform("aarch64", "macos"),
])

products     = [ LibraryProduct("libmeddly_c", :libmeddly_c) ]
dependencies = [ Dependency("CompilerSupportLibraries_jll") ]

build_tarballs(ARGS, name, version, sources, script, platforms, products, dependencies;
               julia_compat = "1.6",
               preferred_gcc_version = v"8")
