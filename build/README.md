# Building the `libmeddly_c_jll` binary (Route B: local + self-host)

`build_tarballs.jl` is a [BinaryBuilder](https://docs.binarybuilder.org) recipe
that produces prebuilt `libmeddly_c` binaries (the C ABI shim with MEDDLY
statically linked inside). Once published as `libmeddly_c_jll`, Meddly.jl needs
no source build, autotools, or C++ compiler at install time.

This directory is **not** part of the Meddly.jl package — it is tooling for
producing the JLL. Requires Docker (BinaryBuilder runs its build sandbox in a
Linux container on macOS).

## Prerequisites

- Docker running (macOS: Docker Desktop or colima).
- A GitHub token with repo scope (for `--deploy`).

## Validation status (2026-07-18)

Validated locally with `build_tarballs_local.jl` (which takes the shim from the
working copy via `DirectorySource`, so no tag/sha256 is needed). **Three of four
platforms built clean; the macOS binary was additionally run end-to-end.**

- **`x86_64-linux-gnu-cxx11`** — builds clean, audit passes.
- **`aarch64-linux-gnu-cxx11`** — builds clean, audit passes.
- **`aarch64-apple-darwin`** — builds clean, audit passes, **and all 219
  Meddly.jl tests pass natively** against the cross-built `.dylib` on an Apple
  Silicon Mac (see "Verifying macOS" below).
- **`x86_64-apple-darwin`** — not built here, but shares the recipe and both
  macOS fixes with the aarch64 build; expected to build identically.

Two things were needed to make the build correct, both discovered by actually
building rather than by inspection:

1. **`CompilerSupportLibraries_jll` dependency** — added to both recipes. Without
   it the Linux audit warns that `libgcc_s.so.1` cannot be auto-mapped. (On
   macOS the shim links the system `/usr/lib/libc++`, so CSL is harmless there.)
2. **`ac_cv_func_{malloc,realloc}_0_nonnull=yes`** on `./configure` — added to
   both recipes. Cross-compiling, autoconf's `AC_FUNC_MALLOC/REALLOC` can't run
   their probe, assume the functions are broken, and substitute `rpl_malloc` /
   `rpl_realloc` (undefined) → MEDDLY fails to compile (`unpacked_node.lo`). The
   cache variables tell configure the functions are fine.

The `-shared` flag is fine on macOS (BB's clang wrapper emits a valid `.dylib`);
no `-dynamiclib` branch is needed.

### Verifying macOS

macOS verification has two layers, and both now pass:

- **Functionality** was already proven before JLL-ization: the current native
  arm64 build (`deps/usr/lib/libmeddly_c.dylib`) runs the 219 tests on this Mac.
- **The cross-built binary** was verified end-to-end: build the macOS target with
  the Apple-SDK license accepted, then run the suite natively against the
  produced `.dylib`.

```sh
# 1. Build the macOS target (Apple SDK license must be accepted):
export BINARYBUILDER_AUTOMATIC_APPLE=true
julia --project=build build/build_tarballs_local.jl --verbose --deploy=local aarch64-apple-darwin
# → products/libmeddly_c.v0.5.0.aarch64-apple-darwin.tar.gz and a dev JLL in
#   ~/.julia/dev/libmeddly_c_jll (its artifact dylib is under ~/.julia/artifacts/)

# 2. Run the suite natively against that dylib. Force a fresh compile
#    (--compiled-modules=no) so a previously baked libmeddly_c_path is not reused,
#    and bypass deps/deps.jl so the ENV override wins:
REAL=$(julia -e 'using Pkg; Pkg.activate(temp=true);
  Pkg.develop(path=expanduser("~/.julia/dev/libmeddly_c_jll"));
  import libmeddly_c_jll; print(libmeddly_c_jll.libmeddly_c)')
mv deps/deps.jl deps/deps.jl.bak
LIBMEDDLY_C_PATH="$REAL" julia --compiled-modules=no --project=. test/runtests.jl
mv -f deps/deps.jl.bak deps/deps.jl
```

Result here: **219 pass, 0 fail**. (Gotcha: without `--compiled-modules=no`, a
stale precompile cache can bake an old `libmeddly_c_path` and dlsym then fails on
`meddly_edge_from_node` etc. — that is a caching artifact, not a binary defect.)

## Step 0 — tag Meddly.jl and fix the shim source hash

`build_tarballs.jl` fetches the shim (`c/meddly_c.cpp`) from the Meddly.jl git
tag matching the recipe `version` (currently `v0.5.0`). So first:

```sh
git tag v0.5.0 && git push origin v0.5.0
```

Then get the archive's sha256 and paste it over the zero placeholder in
`build_tarballs.jl` (the `ArchiveSource` for Meddly.jl):

```sh
curl -sL https://github.com/JuliaReliab/Meddly.jl/archive/refs/tags/v0.5.0.tar.gz \
  | shasum -a 256
```

(If you skip this, the first build run errors and prints the correct hash — you
can copy it from there.)

MEDDLY is already pinned by commit SHA (`f8a89d0…`), no tag needed.

## Step 1 — build

```sh
julia --project=build -e 'using Pkg; Pkg.add("BinaryBuilder")'

# Smoke-test one platform first (drops you into a debug shell on failure):
julia --project=build build/build_tarballs.jl --verbose --debug x86_64-linux-gnu-cxx11

# Then all Linux+macOS targets:
julia --project=build build/build_tarballs.jl --verbose
```

In the `--debug` shell on failure, check the shim's symbols:

```sh
nm -D $libdir/libmeddly_c.$dlext | grep -E 'meddly_(initialize|create_node|edge_from_node)'
```

## Step 2 — deploy (GitHub release + JLL wrapper repo)

`--deploy` uploads the tarballs to a GitHub release and pushes the generated
`libmeddly_c_jll` wrapper package in one go:

```sh
export GITHUB_TOKEN=...        # repo scope
julia --project=build build/build_tarballs.jl --verbose \
      --deploy="JuliaReliab/libmeddly_c_jll.jl"
```

## Step 3 — register in a private registry

Route B does not go through General. Register the wrapper in your own registry
so `Pkg` can resolve it:

```sh
julia -e 'using LocalRegistry; register("libmeddly_c_jll"; registry="<your registry>")'
```

Consumers then `Pkg.Registry.add("<your registry URL>")` once, after which
`Pkg.add("Meddly")` pulls the JLL automatically.

## Step 4 — switch Meddly.jl to the JLL

Apply once `libmeddly_c_jll` is published (it must exist for `Pkg` to resolve
its UUID). The binding name `libmeddly_c_path` is kept, so **`src/lowlevel.jl`
needs no change** — only its source of truth moves from `deps/deps.jl` to the JLL.

1. **`Project.toml`** — add the dep (fill the UUID `Pkg` records when you
   `add` the published JLL) and a compat bound:
   ```toml
   [deps]
   libmeddly_c_jll = "<uuid-from-the-published-JLL>"

   [compat]
   libmeddly_c_jll = "0.5"
   ```

2. **`src/Meddly.jl`** — replace the `deps/deps.jl` lookup (currently lines
   ~22–27) with the JLL, keeping the dev fallback:
   ```julia
   using libmeddly_c_jll
   const libmeddly_c_path = libmeddly_c_jll.libmeddly_c   # dlopen-able path
   # dev override still honoured:
   # const libmeddly_c_path = get(ENV, "LIBMEDDLY_C_PATH", libmeddly_c_jll.libmeddly_c)
   ```
   `src/lowlevel.jl`'s `const libmeddly_c = libmeddly_c_path` is unchanged.

3. **`test/runtests.jl`** — replace its `deps/deps.jl` lookup (lines ~5–9) the
   same way: `using libmeddly_c_jll; const libmeddly_c_path = libmeddly_c_jll.libmeddly_c`.
   The `_lib_available` dlopen guard can stay (now always true).

4. **Delete** `deps/build.jl` (and the now-unused `deps/deps.jl` generation).
   The `.gitignore` entries for `deps/usr/`, `deps/meddly-src/`, `deps/deps.jl`,
   `c/*.dylib` become dead — remove them.

5. **Docs** — update the "Pkg.build" / `deps/usr/lib/libmeddly.a` mentions in
   `README.md` (Architecture diagram), `CHANGELOG.md` (new entry), and
   `CLAUDE.md` (Build section, which currently documents the source-build) to
   "binary shipped via `libmeddly_c_jll`".

Verify: `julia --project=. -e 'using Pkg; Pkg.test()'` passes the 219 tests
**without** a source build, and `../MDDMinsol` still passes its 2605 tests.

## Route A (later)

For the General-registered version, submit essentially this recipe to
[Yggdrasil](https://github.com/JuliaPackaging/Yggdrasil). The LGPL v3 license is
already handled (`install_license COPYING.LESSER COPYING`).
