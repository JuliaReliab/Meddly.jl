# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Test

### First-time setup (builds MEDDLY from source + C shim)
```sh
julia --project=. -e 'using Pkg; Pkg.build("Meddly")'
```
Prerequisites: `git`, `autoconf`, `automake`, `glibtool` (macOS) / `libtool` (Linux), `clang++` or `g++`.

### Run tests
```sh
julia --project=. test/runtests.jl
```
`Pkg.test()` is broken in Julia 1.12 for stdlib deps; use the direct form above.

### Rebuild shim only (after editing `c/meddly_c.cpp`)
```sh
# The built MEDDLY static lib is at deps/usr/lib/libmeddly.a
# and the install prefix is deps/usr/
cd c
make MEDDLY_PREFIX=../deps/usr
```
Or re-run `Pkg.build` which always rebuilds from scratch.

### Verify the built library path
```sh
cat deps/deps.jl
```

## Architecture

The package has three layers:

```
Julia user code
      │
src/highlevel.jl    ← public API: initialize/cleanup, set ops (|, &, setdiff),
                      integer arithmetic (+, -, *, max, min),
                      comparisons (eq, neq, lt, lte, gt, gte),
                      comparison overloads (==, !=, <, <=, >, >=),
                      logical ops (land, lor, lnot),
                      bool_forest, copy_edge, ifthenelse, @match,
                      todot, cardinality, is_empty,
                      traversal (root_node, num_vars, level_size, is_terminal,
                                 node_level, terminal_value, node_children)
src/types.jl        ← abstract type AbstractForest; concrete types
                      MDDForestBool, MDDForestInt, Domain, Edge
                      each holds a Ptr{Cvoid} + a reference to its parent
                      (Edge→AbstractForest→Domain) to prevent premature GC;
                      constructors call C create fns, finalizers call destroy
src/lowlevel.jl     ← raw ccall wrappers (_ll_* functions, _check/_check_ptr)
      │  dlopen(libmeddly_c_path)
      │
c/meddly_c.cpp      ← C ABI shim (extern "C"); catches all C++ exceptions,
                      returns error codes or NULL, exposes meddly_last_error()
c/meddly_c.h        ← shared header; integer constants MUST stay in sync with
                      _FOREST_MDD/MXD, _RANGE_BOOLEAN/INTEGER, _OP_* in types.jl
      │  static link
      │
deps/usr/lib/libmeddly.a  ← MEDDLY 0.18.x built by deps/build.jl
```

### Key types

**Type hierarchy (no `Forest` type — removed as breaking change):**
- `abstract type AbstractForest` — dispatch supertype; all forest pointers are `AbstractForest`
- `mutable struct MDDForestBool <: AbstractForest` — boolean multi-terminal MDD; fields `ptr`, `domain`
- `mutable struct MDDForestInt <: AbstractForest` — integer multi-terminal MDD; fields `ptr`, `domain`, `bool_forest::MDDForestBool` (eagerly created)
- `bool_forest(f::MDDForestBool) = f` / `bool_forest(f::MDDForestInt) = f.bool_forest` — retrieves associated boolean forest

**`Edge`** holds `ptr::Ptr{Cvoid}` and `forest::AbstractForest`. Constructors:
- `Edge(forest)` — empty set / zero function
- `Edge(forest, values::Vector{Int})` — single boolean minterm
- `Edge(forest, value::Integer)` — constant integer edge (all minterms → value)
- `Edge(forest, vars::Vector{Int}, value::Integer)` — single-minterm integer edge (0 elsewhere)

### Traversal API

**`NodeHandle`** = `Int32` type alias. Terminal nodes have handle ≤ 0:
- MT-boolean: false = `0`, true = `-1`.
- MT-integer: zero = `0`, value `v ≠ 0` = `Int32(v) | typemin(Int32)` (sign bit set).
  - Decode with `forest::getIntegerFromHandle(p)`: `(h << 1) >> 1` strips the sign bit.
- Two handles are equal iff they encode the same value (MDDs share terminals globally).

`node_children(f, node)` uses `MEDDLY::unpacked_node::newFromNode(f, node, MEDDLY::FULL_ONLY)`
to obtain a dense (full) child array, normalising both FULL and SPARSE stored nodes.
Always use `MEDDLY::FULL_ONLY` (namespace-qualified) — bare `FULL_ONLY` is not in scope.
Pattern: `newFromNode` → iterate `un->down(i)` → `unpacked_node::Recycle(un)`.

In a fully-reduced MDD, a child's level may be lower than `parent_level - 1`.
Skipped levels act as redundant nodes; `evaluate`-style algorithms must use
`node_level(f, child)` rather than assuming `parent_level - 1`.

### `ifthenelse` design
`ifthenelse(c, t, e)` dispatches on the type of `c.forest`:
- **`MDDForestBool` condition**: calls `meddly_edge_ifthenelse` in C++ via `_ll_edge_ifthenelse`.
  This is the `ite_mt` ternary operation implemented as a `MEDDLY::ternary_operation` subclass
  in `c/meddly_c.cpp`, with compute-table memoization (`ct_entry_type("NNN:N")`).
  DD traversal: terminal case dispatches on boolean handle → links `t` or `e` node;
  internal case builds level = max(level(c), level(t), level(e)), iterates children,
  then calls `forest::createReducedNode`.
- **`MDDForestInt` condition** (values in {0,1}): arithmetic fallback
  `c * t + (one_e - c) * e` where `one_e = Edge(t.forest, 1)`.

### Library path resolution (module load order)
`src/Meddly.jl` includes `deps/deps.jl` (auto-generated by `Pkg.build`) to get
`libmeddly_c_path`, then includes `lowlevel.jl` which binds the constant
`libmeddly_c = libmeddly_c_path`. If `deps/deps.jl` is absent it falls back to
`ENV["LIBMEDDLY_C_PATH"]` or the bare string `"libmeddly_c"`.

### MEDDLY 0.18.x API notes (relevant to `meddly_c.cpp`)
- Include: `<meddly/meddly.h>` (headers install under a `meddly/` subdirectory)
- Domain: `MEDDLY::domain::createBottomUp(int*, unsigned)` / `domain::destroy(domain*&)`
- Forest: `MEDDLY::forest::create(domain*, set_or_rel, range_type, edge_labeling)` / `forest::destroy(forest*&)` — both are static methods
- `set_or_rel` is a `bool` alias: `MEDDLY::SET` (false) / `MEDDLY::RELATION` (true)
- `range_type` and `edge_labeling` are scoped enums: `MEDDLY::range_type::BOOLEAN`, `MEDDLY::edge_labeling::MULTI_TERMINAL`, etc.
- **Empty edge**: `new MEDDLY::dd_edge(forest*)` — default node=0 is correct for all forest types
  (false terminal for MT-boolean, integer-0 for MT-integer). Do NOT call `createConstant(false, e)` for non-boolean forests — it causes TYPE_MISMATCH.
- **Empty check**: use `e->getNode() == 0` — works for all quasi-reduced forest types (node=0 means false/0/absent)
- Single-element edge: `MEDDLY::minterm m(forest*); m.setVar(i+1, val); m.buildFunction(default, edge)` — `setVar` is 1-indexed
- Operations: `MEDDLY::apply(MEDDLY::UNION, a, b, c)` where `UNION` / `INTERSECTION` / `DIFFERENCE` are functions returning `binary_factory&`
- Arithmetic: `MEDDLY::apply(MEDDLY::PLUS, a, b, c)` etc. for integer MT forests
- Comparison: `MEDDLY::apply(MEDDLY::GREATER_THAN, a, b, c)` where `c` is in a different (boolean) forest
- Cross-forest copy: `MEDDLY::apply(MEDDLY::COPY, src, dst)` — boolean→integer maps false→0, true→1
- Complement: `MEDDLY::apply(MEDDLY::COMPLEMENT, a, c)` — boolean forests only
- Cardinality: `MEDDLY::apply(MEDDLY::CARDINALITY, edge, double&)`
- **Traversal**:
  - `dd_edge::getNode()` → root `node_handle` (int)
  - `forest::isTerminalNode(p)` → true when `p < 1` (i.e. `p <= 0`)
  - `forest::getNodeLevel(p)` → 0 for terminals, 1..K for internal
  - `forest::getNumVariables()` → K (unsigned)
  - `forest::getLevelSize(k)` → domain size at level k
  - `forest::getBooleanFromHandle(p)` / `getIntegerFromHandle(p)` → terminal value
  - `unpacked_node::newFromNode(f, node, MEDDLY::FULL_ONLY)` → dense child array
  - `un->getSize()` → number of children; `un->down(i)` → i-th child handle
  - `unpacked_node::Recycle(un)` → release (must always be called)

### `deps/build.jl` quirks
- Builds only `src/` of MEDDLY (`make -C src`) because `examples/` unconditionally `#include <gmp.h>` even when `--without-gmp` is passed to configure.
- On macOS, sets `LIBTOOLIZE=glibtoolize` for `autoreconf`.
- `libmeddly_c` is a shared library that **statically links** `libmeddly.a`, so only `libmeddly_c.dylib/.so` needs to be present at runtime.
- `deps/meddly-src/` and `deps/usr/` are git-ignored generated artifacts.

### Known limitations (see TODO.md for details)
- **EV+MDD (EVPLUS)** forests: edge/arithmetic creation works, but `ifthenelse` is broken.
  MEDDLY treats OMEGA_INFINITY as absorbing in all arithmetic ops — `0 * ∞ = ∞` at
  non-terminal nodes — so the `c * t + (1-c) * e` formula always returns OMEGA_INFINITY.
  A dedicated C++-level ifthenelse traversal for EV+MDD is needed (see TODO.md §2).
- **EV×MDD (EVTIMES)**: MEDDLY only supports EVTIMES for REAL range + RELATION (MXD).
  INTEGER + MDD throws TYPE_MISMATCH.
- `meddly_forest_create_ev` and related EV constants are present in `c/meddly_c.h` and `.cpp`
  but are **not exposed in the Julia API** (no `MDDForestEVPlus` type yet).
- **MT-integer `ifthenelse`** with boolean condition: resolved — uses C++ `ite_mt` ternary op.

---

## Session Log

### 2026-04-26
**Done:**
- Investigated EV+MDD `ifthenelse` failure: `cardinality(result) = 0.0` instead of 2.0.
- Root-caused the issue: MEDDLY's `evplus_mult::simplifiesToSecondArg` fires when
  B=OMEGA_INFINITY at any non-terminal level, regardless of A's edge value. This means
  `0 * OMEGA_INFINITY = OMEGA_INFINITY` (not OMEGA_NORMAL(0)), so the mixing of dense
  (copied boolean condition) and sparse (OMEGA_INFINITY background) EV+MDD operands in
  `c_int * t + nc_int * e` causes the entire result to be OMEGA_INFINITY.
- Tried `lnot`-based approach (avoid MINUS); same failure — the multiplication/plus
  still propagates OMEGA_INFINITY.
- **Decision:** Revert EV+MDD support from Julia layer; document root cause in TODO.md.
- Created `TODO.md` with detailed problem description and future implementation paths.
- Reverted `src/types.jl`: removed `ev::Symbol` field and EV constants from `Forest`.
- Reverted `src/highlevel.jl`: `ifthenelse` back to simple `c * t + (1-c) * e` formula.
- Reverted `test/runtests.jl`: removed 3 EV+MDD test sections (forest creation, arithmetic, ifthenelse).
- All 83 tests pass.

**Pending:**
- Implement `meddly_edge_ifthenelse` in C++ via direct DD traversal (see TODO.md §2).
- EV+MDD arithmetic tests (PLUS, MULTIPLY, MAX, MIN between same-support sparse edges) pass — only `ifthenelse` is broken. If EV+MDD is re-exposed, these can be re-added.

**Notes for next session:**
- The C++ shim (`c/meddly_c.cpp`) still contains the EV+MDD helper code (`meddly_forest_create_ev`, `meddly_edge_create_from_minterm_int` with PLUS_INFINITY branch, etc.) — these are unused from Julia but harmless.
- The fixes for `meddly_edge_create` (no `createConstant` call) and `meddly_edge_is_empty` (use `getNode()==0`) are **intentional** and fix bugs for MT-integer forests too. Do not revert them.
- `c/libmeddly_c.dylib` in the repo root is a stale artifact from early development; the authoritative build output is `deps/usr/lib/libmeddly_c.dylib`.

### 2026-04-26 (session 2)
**Done:**
- Rewrote `README.md` with complete English documentation: boolean MDD, integer forest,
  arithmetic, comparisons, logical ops, `ifthenelse`, `todot`, full API table,
  corrected test command (`julia --project=. test/runtests.jl`), updated known limitations.
- Split `test/runtests.jl` into 6 feature files (`test_lifecycle`, `test_boolean`,
  `test_integer`, `test_comparison`, `test_ifthenelse`, `test_misc`); 83 tests total.
- Initialized git repository and created initial commit (22 files).
- Added MDD traversal API (C shim + Julia bindings + tests):
  - New C functions: `meddly_edge_get_node`, `meddly_forest_num_vars`,
    `meddly_forest_level_size`, `meddly_node_is_terminal`, `meddly_node_level`,
    `meddly_node_bool_value`, `meddly_node_int_value`, `meddly_node_get_children`.
  - New Julia exports: `NodeHandle` (= `Int32`), `root_node`, `num_vars`, `level_size`,
    `is_terminal`, `node_level`, `terminal_value`, `node_children`.
  - `test/test_traverse.jl`: 47 tests; total test count now 130.
- Updated README.md with traversal section (4 worked examples: evaluate, cardinality,
  collect minterms, sum of values) and extended API table.
- Three git commits on branch `main`.

**Pending:**
- Implement `meddly_edge_ifthenelse` in C++ via direct DD traversal for EV+MDD support
  (see TODO.md §2).
- Minterm iteration API (iterate without building the full explicit list).
- More thorough MxD (relation forest) testing.

**Notes for next session:**
- `terminal_value(f, node)` dispatches on `f.range` (`:boolean` → `Bool`, `:integer` → `Int`).
  For MT-integer, terminal encoding is `Int32(v) | typemin(Int32)` for v≠0, decoded by
  `forest::getIntegerFromHandle` via `(h << 1) >> 1`.
- In fully-reduced MDDs, `node_children(f, n)` may return children at levels lower than
  `node_level(f, n) - 1`. Algorithms must use `node_level(f, child)` — never assume
  consecutive levels.
- `meddly_node_get_children` uses `MEDDLY::FULL_ONLY` (namespace-qualified; bare
  `FULL_ONLY` is not in scope in `meddly_c.cpp`).

### 2026-04-26 (session 3)
**Done:**
- Implemented C++ `ite_mt` ternary operation in `c/meddly_c.cpp`:
  - `MEDDLY::ternary_operation` subclass with compute table (`ct_entry_type("NNN:N")`).
  - Terminal case: `getBooleanFromHandle(c_node)` → link `t` or `e` child.
  - Internal case: level = max of all three forests; `unpacked_node::newWritable` /
    `newRedundant` / `newFromNode`; `forest::createReducedNode`.
  - `meddly_edge_ifthenelse` C ABI wrapper added to `meddly_c.h` and `meddly_c.cpp`.
  - `_ll_edge_ifthenelse` ccall wrapper added to `src/lowlevel.jl`.
- Implemented `@match` macro in `src/highlevel.jl`:
  - Arms are `condition => value`; last arm may use `_` as catch-all.
  - Expands to nested `ifthenelse` calls via `_match_build`.
  - `&&` / `||` in conditions rewritten to `land` / `lor` by `_match_cond`.
  - `test/test_match.jl`: 34 tests covering 2/3-arm, `&&`, `||`, overloads, nested.
- Implemented comparison operator overloads (`==`, `!=`, `<`, `<=`, `>`, `>=`) in
  `src/highlevel.jl`: use `bool_forest(a.forest)` so no explicit boolean forest needed.
- Started `AbstractForest` refactor: fully rewrote `src/types.jl` with
  `abstract type AbstractForest`, `MDDForestBool`, `MDDForestInt`; removed `Forest`.

**Pending (carried to session 4):**
- Complete `highlevel.jl` refactor and test/doc updates.

### 2026-04-26 (session 4)
**Done:**
- Completed `src/highlevel.jl` refactor for `AbstractForest`:
  - Replaced `_get_bool_forest` with `bool_forest(f::MDDForestBool)` /
    `bool_forest(f::MDDForestInt)` dispatch pair.
  - `ifthenelse` now dispatches via `_ifthenelse(c, c.forest, t, e)` with methods on
    `MDDForestBool` (C++ ITE) and `MDDForestInt` (arithmetic fallback).
  - `terminal_value` split into two typed methods (Bool for `MDDForestBool`,
    Int for `MDDForestInt`).
  - All traversal and comparison signatures updated: `Forest` → `AbstractForest`.
  - `copy_edge` signature updated: `target::Forest` → `target::AbstractForest`.
- Updated `src/Meddly.jl`: removed `Forest` export; added `AbstractForest`,
  `MDDForestBool`, `MDDForestInt`, `bool_forest`.
- Updated all 8 test files (`test_lifecycle`, `test_boolean`, `test_integer`,
  `test_comparison`, `test_ifthenelse`, `test_misc`, `test_traverse`, `test_match`):
  - `Forest(dom)` → `MDDForestBool(dom)`, `Forest(dom; range=:integer)` → `MDDForestInt(dom)`.
  - `cond.forest.range == :boolean` → `cond.forest isa MDDForestBool`.
  - `int_f._bool_forest` → `int_f.bool_forest`.
  - `int_f._bool_forest !== nothing` → `int_f.bool_forest isa MDDForestBool`.
- Updated `README.md`: new type names throughout; added comparison overloads section and
  `@match` section; updated API table and architecture description.
- Updated `TODO.md`: MT ifthenelse marked resolved; EV+MDD scope clarified;
  added §5 "その他の改善候補".
- All 164 tests pass.

**Pending:**
- EV+MDD `ifthenelse` (C++ traversal, OMEGA_INFINITY-safe merge) — see TODO.md §2.
- Minterm iteration API.
- More thorough MxD (relation forest) testing.

**Notes for next session:**
- `Forest` is fully removed. There is no compatibility shim. Any code that used `Forest()`
  must be updated to `MDDForestBool()` / `MDDForestInt()`.
- `MDDForestInt` always creates a `bool_forest` eagerly — no lazy init, no `nothing` check.
- The `ite_mt` ternary operation in `c/meddly_c.cpp` uses `ALLOW_DEPRECATED_0_17_6`
  (defined in MEDDLY's `defines.h`) to enable the `computeDDEdge` virtual method.
  If upgrading MEDDLY, check whether this macro is still defined.
- `c/libmeddly_c.dylib` in the repo root is a stale artifact; authoritative output is
  `deps/usr/lib/libmeddly_c.dylib`.
