# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Test

### Setup

The shim binary ships prebuilt as `libmeddly_c_jll` (see below), so there is **no
source build** — no autotools, no C++ compiler. `libmeddly_c_jll` lives in the
JuliaReliab registry (not General yet), so add that registry once:

```sh
julia --project=. -e 'using Pkg;
  Pkg.Registry.add(Pkg.RegistrySpec(url="https://github.com/JuliaReliab/Registry.git"));
  Pkg.instantiate()'
```

### Run tests
```sh
julia --project=. test/runtests.jl
```
`Pkg.test()` is broken in Julia 1.12 for stdlib deps; use the direct form above.

### Working on the C shim (`c/meddly_c.cpp`)

`src/Meddly.jl` loads `libmeddly_c_jll.libmeddly_c`, **unless** `LIBMEDDLY_C_PATH`
is set — that env var overrides the JLL with a locally built `.so`/`.dylib`. So the
dev loop for a shim edit is: build the shim locally, point `LIBMEDDLY_C_PATH` at it,
run the tests. Build it with the BinaryBuilder recipe (`build/README.md` — its
`build_tarballs_local.jl` compiles from the working-copy `c/`), or, if you have a
MEDDLY static lib around, directly:

```sh
clang++ -O2 -std=c++14 -fPIC -I<meddly-prefix>/include -shared \
        -o /tmp/libmeddly_c.dylib c/meddly_c.cpp <meddly-prefix>/lib/libmeddly.a
LIBMEDDLY_C_PATH=/tmp/libmeddly_c.dylib julia --compiled-modules=no \
        --project=. test/runtests.jl
```

Use `--compiled-modules=no` (or `touch src/Meddly.jl`) so a stale precompile cache
does not keep a previously baked `libmeddly_c_path`.

**Shipping a shim change to users** means cutting a new `libmeddly_c_jll`: bump the
Meddly.jl tag, update the shim `GitSource` SHA in `build/build_tarballs.jl`,
`--deploy` it, and register the new JLL version. See `build/README.md`.

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
                                 node_level, terminal_value, node_children),
                      construction (create_node, edge_from_node),
                      forest stats (current_num_nodes, peak_num_nodes,
                                    reset_peak_num_nodes!)
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
      │  ships prebuilt in
      │
libmeddly_c_jll     ← libmeddly_c with MEDDLY 0.18.x statically linked inside
                      (built by build/build_tarballs.jl; see build/README.md)
```

### Key types

**Type hierarchy (no `Forest` type — removed as breaking change):**
- `abstract type AbstractForest` — dispatch supertype; all forest pointers are `AbstractForest`
- `mutable struct MDDForestBool <: AbstractForest` — boolean multi-terminal MDD; fields `ptr`, `domain`
- `mutable struct MDDForestBoolMxD <: AbstractForest` — boolean MxD relation forest; created by `MDDForestBoolMxD(dom)`
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

### Node construction API (v0.5.0)

The construction counterpart of the traversal API. Together they let an algorithm assemble
a **result diagram bottom-up** instead of enumerating minterms and rebuilding from them —
which is what makes an output-compressed Rauzy `minsol` (rims Algorithm 3) possible.

- `create_node(f, level, children::Vector{NodeHandle})` → `Edge`. Wraps
  `unpacked_node::newWritable(f, level, FULL_ONLY)` → `setFull(i, …)` →
  `forest::createReducedNode(nb, ev, node)`, the same sequence `ite_mt` runs internally.
  `length(children)` must equal `level_size(f, level)`.
- `edge_from_node(f, node)` → `Edge`. The inverse of `root_node`: hands a subgraph reached
  by traversal back to the edge-level ops (`setdiff`, `|`, `cardinality`, …).

**Ownership is the thing to get right here.** `unpacked_node::setFull(n, h)` is just
`_down[n] = h` — it stores the handle raw and does **not** link it, so it must be handed an
*owned* reference. `ite_mt` satisfies that naturally (its children come from recursive calls
that already carry a reference), but handles crossing the C boundary from Julia are
**borrowed** (`node_children`, `root_node`). So `meddly_create_node` calls `f->linkNode(child)`
on each, and `meddly_edge_from_node` uses `dd_edge::set_and_link` rather than `set`
(`set` takes ownership, `set_and_link` borrows — both exist for this distinction).
Getting this wrong does not fail loudly: refcounts drift and nodes are freed while still
referenced.

`createReducedNode`'s 4th argument `in` is the incoming-edge index used for **identity
reduction** (MxD). It defaults to `-1` = do not attempt identity reduction, which is what
SET forests want; `meddly_create_node` relies on that default.

Results pass through the forest's reduction rules, so `create_node` may return one of the
children (redundant node) or a terminal.

### Forest statistics (v0.5.0)

`current_num_nodes(f)` / `peak_num_nodes(f)` / `reset_peak_num_nodes!(f)` wrap
`forest::getCurrentNumNodes` / `getPeakNumNodes` / `resetPeakNumNodes`.

These exist because **the node count of a result edge cannot compare two algorithms**: a
fully-reduced diagram is canonical for a given variable order, and MEDDLY hash-conses, so
two methods computing the same set in the same forest return *literally the same node
handle*. The result's size is a property of the answer, not of the method. What separates
methods is how many nodes they build on the way:

```julia
reset_peak_num_nodes!(f)
before = current_num_nodes(f)
result = my_algorithm(...)
peak_num_nodes(f) - before      # nodes this computation needed at once
```

Measure on a **fresh forest** per method — hash-consing means a warm forest lets whichever
method runs second reuse the first one's nodes, which shows up as an implausibly low peak.

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
`src/Meddly.jl` sets `libmeddly_c_path` from `libmeddly_c_jll.libmeddly_c` (the
prebuilt shim), unless `ENV["LIBMEDDLY_C_PATH"]` is set (dev override for a
locally built shim). It then includes `lowlevel.jl`, which binds the constant
`libmeddly_c = libmeddly_c_path`.

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

### Binary build (`build/build_tarballs.jl`, BinaryBuilder → `libmeddly_c_jll`)
The shim + MEDDLY are no longer built at install time (`deps/build.jl` is gone).
They ship as `libmeddly_c_jll`, built by the BinaryBuilder recipe in `build/`.
Recipe details worth knowing (see `build/README.md` for the full runbook):
- Builds only `src/` of MEDDLY (`make -C src`) because `examples/` unconditionally `#include <gmp.h>` even with `--without-gmp`.
- Cross-compiling needs `ac_cv_func_{malloc,realloc}_0_nonnull=yes` on `configure` (autoconf otherwise substitutes undefined `rpl_malloc`/`rpl_realloc`).
- `CompilerSupportLibraries_jll` is a declared dependency (Linux `libgcc_s`).
- macOS targets need `BINARYBUILDER_AUTOMATIC_APPLE=true` (Apple SDK license).
- The shim **statically links** MEDDLY, so `libmeddly_c.{dylib,so}` is the only runtime file.
- Both MEDDLY and the shim are pinned by commit SHA (`GitSource`), not GitHub's tag archive (which BinaryBuilder rejects as non-reproducible).

### MxD relation API (v0.4.0)

`MDDForestBoolMxD` holds a MEDDLY RELATION boolean forest. Three operations:

- `mxd_singleton(forest, unprimed, primed)` — builds a single-pair MxD edge.
  Both arrays are length K (number of variables, 1-indexed at the Julia level).
  `-1` entries in `unprimed` = DONT_CARE (match any pre-state value).
  `-1` entries in `primed` = DONT_CHANGE (keep the variable unchanged).
  Uses `meddly_edge_create_from_minterm_pair` in the C shim, which calls
  `m.setVars(i+1, unp_val, pri_val)` for each variable level.

- `post_image(set::Edge, rel::Edge)` — forward image; wraps `meddly_edge_post_image`
  which calls `MEDDLY::apply(POST_IMAGE, set, rel, result)`.

- `reachable_bfs(initial::Edge, rel::Edge)` — BFS fixed-point loop in C shim:
  `frontier = POST_IMAGE(current, rel)`, `new = DIFFERENCE(frontier, current)`,
  loop until `new` is empty. Wraps `meddly_edge_reachable_bfs`.

**Per-variable intersection of MxD edges is NOT valid**: if two edges each use
`DONT_CHANGE` for different variables, MEDDLY's INTERSECTION treats them as
compatible constraints and intersects — yielding wrong results. Always union
singleton edges per transition (one singleton per combination of changed-variable
values) rather than intersecting per-variable edges.

### `var!` construction (v0.4.0 fix)

`var!(b, :x)` now uses DONT_CARE (`-1`) for all variables except the target:

```julia
vars_vec = fill(-1, K)       # DONT_CARE everywhere
for (x_idx, x_val) in enumerate(dom)
    x_val == 0 && continue
    vars_vec[lv] = x_idx - 1  # 0-based MEDDLY index for target variable
    result = result + Edge(int_f, vars_vec, x_val)
    vars_vec[lv] = -1
end
```

This is O(domain_size) instead of O(∏ domain_sizes). MEDDLY's full-reduction
collapses the result to a compact single-level node. DONT_CARE = -1 is confirmed
in `meddly/minterms.h`: `const int DONT_CARE = -1`.

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

### 2026-05-11

**Done:**
- Fixed `var!` exponential construction cost: replaced `Iterators.product` over all other
  variable combinations with DONT_CARE (`-1`) approach — O(domain_size) iterations instead
  of O(∏ domain_sizes). Confirmed `DONT_CARE = -1` from `meddly/minterms.h`.
- Added MxD relation API (carried over from PS4GSPN.jl `MeddlySetEngine` work):
  - `MDDForestBoolMxD` type in `src/types.jl` (boolean RELATION forest with finalizer)
  - C shim (`c/meddly_c.cpp`): `meddly_edge_create_from_minterm_pair` (builds MxD singleton),
    `meddly_edge_post_image` (POST_IMAGE apply), `meddly_edge_reachable_bfs` (BFS fixed-point)
  - `src/lowlevel.jl`: three ccall wrappers
  - `src/highlevel.jl`: `mxd_singleton`, `post_image`, `reachable_bfs`; `initialize()` made
    idempotent; `is_initialized()` added
  - `src/Meddly.jl`: exports `MDDForestBoolMxD`, `mxd_singleton`, `post_image`,
    `reachable_bfs`, `is_initialized`
- Bumped version to 0.4.0 in `Project.toml`
- Updated `README.md`, `CHANGELOG.md`, `TODO.md`, `CLAUDE.md` with v0.4.0 additions

**Notes for next session:**
- `mxd_singleton` uses `setVars(i+1, unp, pri)` (1-indexed in MEDDLY); Julia arrays are
  length K (number of variables) with entry `k` corresponding to MEDDLY level `k`
- MxD and MDD edges must share the same `Domain` — checked by `MEDDLY::apply` at call time
- DONT_CARE = -1 works for both primed and unprimed positions in `setVars` (MEDDLY uses
  the same sentinel for both); confirmed in MEDDLY 0.18.x `minterms.h`

### 2026-07-17 — node construction + forest stats（`create_node` 露出）

**Done（すべて未コミット）:**
- **`create_node` を C 関数として露出**（MDDMinsol の宿題「能力は `ite_mt` にあり 1 C 関数で
  露出」の実行）。`c/meddly_c.cpp` に `meddly_create_node`、`c/meddly_c.h` に宣言、
  `src/lowlevel.jl` に `_ll_create_node`、`src/highlevel.jl` に `create_node`。
  - `setFull` は `_down[n]=h` の代入のみで link しないことをソースで確認（`unpacked_node.h:652`）。
    Julia から渡るハンドルは借用なので `f->linkNode(child)` を内部で行う。
  - `createReducedNode` の `in` は identity reduction 用で既定 `-1`（`forest.h:214`）。SET forest
    にはこれが正しい。
- **`edge_from_node` を追加**（`root_node` の逆）。`dd_edge::set_and_link` を使用（`set` は所有権を
  取る／`set_and_link` は借用、両方が存在するのはこの区別のため）。`setdiff` に走査で到達した
  部分グラフを渡すのに必要だった。
- **forest 統計 3 関数**（`current_num_nodes` / `peak_num_nodes` / `reset_peak_num_nodes!`）。
  動機は下記の「標準形」の発見。
- `test/test_traverse.jl` に 5 testset 追加（round-trip が**同一ハンドル**を返すこと、簡約規則の
  発火、借用ハンドルの健全性、引数チェック、統計）。**193 → 216 tests**。
- 実運用上の修正: `deps/deps.jl` が `/Users/okamu/Documents/ORSJ202609テスト/...`（存在しない
  パス）を指しており、この配置では `using Meddly` が失敗する状態だった。書き換え済み（生成物・
  git 管理外）。

**発見（記録の価値が高い）:**
- **結果 MDD の節点数は手法の比較軸にならない。** 同じ集合・同じ変数順序・同じ forest なら
  完全簡約 MDD は標準形で、hash-consing により両手法が **literally 同一の節点ハンドル**を返す
  （MDDMinsol の 108 ケース全部で確認）。結果サイズは「答え」の性質。手法を分けるのは
  **計算途中の peak** → forest 統計を追加した理由。
- **`cd c && make` は Julia が読む dylib を更新しない**（Makefile に install ターゲットが無く、
  `c/libmeddly_c.dylib` は誰も読まない）。CLAUDE.md の該当手順を修正済み。
- **`Pkg.build` は安全な再ビルド手段ではない**: `MEDDLY_REF = "master"` を削除・再クローンする。
  シムは現 checkout（`f8a89d0`）向けに書かれている。

**Pending（次エントリで解消）:**
- **GC ファイナライザ由来の segfault は未修正**（Known limitations 参照）。計測は回避策で凌いだ。
- `Project.toml` は 0.4.0 のまま。今回の 3 API はバージョン未確定・CHANGELOG 未記載。
- README の API 表に新 3 API 未反映。

### 2026-07-18 — GC ファイナライザ segfault 修正 ＋ v0.5.0 リリース整備

**Done:**
- **前エントリ Pending の segfault を修正。** 根本原因は**二重 delete**（ダングリング参照ではない）。
  MEDDLY の `~domain` は自分に登録された forest を `delete` する（`domain.cc:437`、"domain owns
  its forests"）。Julia の forest ファイナライザも `forest::destroy`（= `delete`）を呼ぶため、
  domain とその forest が同時回収され、domain ファイナライザが先に走ると forest を二重解放していた。
  ファイナライザ順序が非決定的なのでクラッシュも非決定的だった。
  - **順序ガード**: forest ファイナライザ（`types.jl` の 3 forest 型）は `x.domain.ptr != C_NULL`
    のときだけ `forest::destroy` を呼ぶ。domain 破棄済みなら skip（二重 delete 回避）。
  - **世代ガード**: `highlevel.jl` に `_meddly_generation`（`initialize` の実初期化で +1）。全
    ファイナライザは「初期化中かつ世代一致」のときだけ C++ destroy を呼ぶ。cleanup 後・
    cleanup→reinit 後の解放済み状態アクセスを防ぐ。各構造体に `gen::Int` フィールド追加。
  - edge 方向は元々安全（`dd_edge` は id 参照、forest 消滅後は no-op）なので順序ガード不要。
  - 回帰テスト: `test/test_misc.jl`（全体同時回収）、`test/test_cleanup_safety.jl`（新規・cleanup /
    reinit、runtests の最後で cleanup/initialize を切り替える）。**216 → 219 tests**。
    再現スクリプトは修正前 3/3 crash → 修正後 3/3 SURVIVED、スイート 5 連続通過。
- **v0.5.0 リリース整備**: `Project.toml` 0.4.0 → 0.5.0、`CHANGELOG.md` に 0.5.0（Added: ノード
  構築・forest 統計 / Fixed: GC segfault）、`README.md` に Construction・Forest statistics 表 ＋
  「Memory ownership」段落を書き直し（ガード付きファイナライザ）。CLAUDE.md の `(unreleased)`
  ラベル → `(v0.5.0)`、Known limitations の segfault 項を削除。

**Notes for next session:**
- ファイナライザは逐次実行（インターリーブしない）前提。`x.domain.ptr` の読み取りは、
  参照先 Julia オブジェクトがファイナライザ完了までメモリ解放されないので安全。
- `MEDDLY::cleanup()` はグローバル全破棄。世代ガードにより cleanup 後の finalizer は C++ destroy を
  skip するため、そのセッションの `dd_edge` ラッパーはリークするが、cleanup は通常プロセス終了時
  なので許容（`_make_edge` のコメント参照）。
- MDDMinsol 側の計測回避策（`compare_edge.jl` の `KEEP` 退避・GC 抑止）は原理的に不要になった
  （撤去は別作業）。

### 2026-07-18 — JLL 化（`libmeddly_c_jll`）＋ソースビルド廃止（v0.6.0）

**Done:**
- **シムをプリコンパイル配布に移行。** `libmeddly_c`（MEDDLY 静的リンク済み）を BinaryBuilder で
  ビルドし `libmeddly_c_jll` として配布。**`deps/build.jl` を削除**（インストール時のソースビルド・
  autotools・C++ コンパイラが不要に）。`src/Meddly.jl` と `test/runtests.jl` は
  `libmeddly_c_jll.libmeddly_c` からライブラリを解決（`LIBMEDDLY_C_PATH` は開発用オーバーライドで存続）。
  `src/lowlevel.jl` は無変更（束縛名 `libmeddly_c_path` を保った）。
- **`deps/` は完全に廃止**。`deps/build.jl` を git から削除、`.gitignore` を `deps/` 全体無視に変更。
  ローカルの `deps/`（旧 MEDDLY クローン＋ビルド成果物、46MB の死んだ残骸）も `rm -rf` で削除済み。
  削除後も 219 tests は JLL 経由で通る（＝ deps/ は完全に非参照だった証明）。
  → **本ファイル内の古い Session Log（2026-04-26）にある「authoritative build output は
  `deps/usr/lib/libmeddly_c.dylib`」等の記述は失効**。現在の真実は「バイナリは `libmeddly_c_jll`」。
- **バージョン 0.6.0**（パッケージング変更・公開 API 不変）。v0.5.0 タグは source-build 版の意味で温存。
- **配布経路（Route B）**: `JuliaReliab/libmeddly_c_jll.jl`（wrapper repo）＋ Release にバイナリ、
  自前レジストリ `JuliaReliab/Registry` に **libmeddly_c_jll と Meddly 本体の両方を登録**。
  利用者は `Pkg.Registry.add(自前) → Pkg.add("Meddly")` の2行で導入（コンパイラ不要、検証済み）。
- ビルドツールは `build/`（`build_tarballs.jl` 本番／`build_tarballs_local.jl` 検証用／runbook）。
  4プラットフォーム（x86_64・aarch64 × Linux・macOS）でビルド実証、macOS はネイティブ 219 tests 通過。

**Notes for next session:**
- **JLL の UUID は名前から決定的** `aa22cf4d-d005-5d21-a85e-c2597cc45fba`。Route A（Yggdrasil→General）
  へ移行しても UUID/名前は不変なので **Meddly.jl のコードと [deps] は無変更**。移行時の作業は
  「自前レジストリの libmeddly_c_jll エントリ退役」だけ（同一 UUID が2 repo を指す衝突回避）。
- シムを直したら新 JLL を切る必要がある: Meddly.jl のタグを上げ、`build/build_tarballs.jl` の
  Meddly.jl `GitSource` SHA を更新し `--deploy` → レジストリに新版登録。`build/README.md` 参照。
- **GitHub の `/archive/refs/tags/*.tar.gz` は BinaryBuilder が拒否**（チェックサム非安定）。
  シムは必ず `GitSource`＋コミット SHA で固定する。
- クロスコンパイルの罠2つ（レシピに対処済み）: `ac_cv_func_{malloc,realloc}_0_nonnull=yes`、
  macOS は `BINARYBUILDER_AUTOMATIC_APPLE=true`。
