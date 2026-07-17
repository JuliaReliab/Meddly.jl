# Changelog

All notable changes to Meddly.jl are documented here.
Versions follow [Semantic Versioning](https://semver.org/).

---

## [0.5.0] — 2026-07-18

### Added

- **Node construction API** — the inverse direction of the traversal primitives, letting an algorithm assemble a result diagram bottom-up instead of enumerating minterms and rebuilding from them:
  - `create_node(f, level, children::Vector{NodeHandle})` — build a reduced node at `level` from a dense child array and return it as an `Edge`. Wraps the `newWritable → setFull → createReducedNode` sequence (the same MEDDLY calls `ite_mt` uses). Borrowed child handles are linked internally.
  - `edge_from_node(f, node)` — the inverse of `root_node`: wrap a node handle reached by traversal back into an `Edge` so it can feed the edge-level operations (`setdiff`, `|`, `cardinality`, …).
  - C shim additions: `meddly_create_node`, `meddly_edge_from_node`.

- **Forest node-count statistics** — `current_num_nodes(f)`, `peak_num_nodes(f)`, `reset_peak_num_nodes!(f)` (wrapping `forest::getCurrentNumNodes` / `getPeakNumNodes` / `resetPeakNumNodes`). The peak measures what a *computation* costs the forest; the node count of a result edge cannot, since a fully-reduced diagram is canonical for a given variable order (hash-consed), so two algorithms returning the same set share the same nodes. C shim additions: `meddly_forest_current_num_nodes`, `meddly_forest_peak_num_nodes`, `meddly_forest_reset_peak_num_nodes`.

### Fixed

- **Segfault when a domain and its forests are garbage-collected together.** MEDDLY's `~domain` deletes every forest registered to it ("a domain owns its forests"), but the Julia forest finalizer also called `forest::destroy` (= `delete`). When the whole object graph became unreachable at once, Julia's unspecified finalizer order let `~domain` run first and free the forests, after which the forest finalizer double-freed them. Fixed by (a) guarding the forest finalizers so `forest::destroy` runs only while the domain is still alive (`domain.ptr != C_NULL`), and (b) an initialization-generation guard on all finalizers so a finalizer that runs after `cleanup()` — or after a `cleanup()`/`initialize()` cycle that invalidated its pointer — skips the C++ destroy instead of touching torn-down MEDDLY state. Edge-vs-forest order was already safe (`dd_edge` resolves its forest by id, null after the forest is gone).

---

## [0.4.0] — 2026-05-11

### Added

- **MxD relation API** — boolean relation forest for symbolic reachability:
  - `MDDForestBoolMxD` type (`kind = :mxd` boolean forest with GC finalizer)
  - `mxd_singleton(forest, unprimed, primed)` — construct a single-pair MxD edge from two minterm arrays (unprimed = pre-state, primed = post-state); DONT_CARE (`-1`) entries accepted in either array
  - `post_image(set::Edge, rel::Edge)` — compute the image of a set under a relation (`POST_IMAGE apply` in MEDDLY)
  - `reachable_bfs(initial::Edge, rel::Edge)` — compute the full reachable state set by BFS fixed-point (`POST_IMAGE + DIFFERENCE + UNION` loop)
  - C shim additions: `meddly_edge_create_from_minterm_pair`, `meddly_edge_post_image`, `meddly_edge_reachable_bfs`

- `is_initialized()` — returns `true` if `initialize()` has been called and `cleanup()` has not been called since; `initialize()` made idempotent (no-op on second call)

### Fixed

- **`var!` exponential construction cost** — previously iterated all combinations of other variables (O(∏ domain_sizes)), hanging on models with many variables or large domains. Fixed by using MEDDLY's DONT_CARE sentinel (`-1`) for all non-target variables so only O(domain_size) single-minterm `Edge` objects are needed. MEDDLY's full-reduction policy collapses the result to a compact single-level node.

---

## [0.3.1] — 2026-04-26

### Added
- `compile!(b::MDDSession)` — explicit step to fix the variable configuration
  and create the underlying MEDDLY `Domain` and forests.  After `compile!`,
  `defvar!` is no longer accepted.  `var!` still calls `compile!` automatically
  when it has not been called yet, so the implicit usage pattern still works.
  `compile!` is idempotent and returns `b` for method chaining.

---

## [0.3.0] — 2026-04-26

### Added
- **Session API** — high-level reference-style interface:
  - `mdd()` creates an `MDDSession`; MEDDLY is auto-initialised on first call.
  - `defvar!(b, name, level, domain)` registers a variable by name and level.
  - `var!(b, name)` returns an integer-forest `Edge` representing the identity
    projection onto that variable (value at any point = domain value of the
    variable at that point).
- **Scalar arithmetic overloads** — `Edge ± n`, `n ± Edge`, `Edge * n`,
  `n * Edge`, unary `-Edge`; a constant integer edge is created automatically.
- **Scalar comparison overloads** — `Edge == n`, `Edge < n`, etc. (and
  reversed); returns a boolean `Edge`.
- `and(a, b)` / `or(a, b)` — named aliases for `land` / `lor`.
- `Base.:(!)(e::Edge)` — complement via `!e` (alias for `lnot`).
- `ifthenelse(c, t::Integer, e::Integer)`, `ifthenelse(c, t::Edge, e::Integer)`,
  `ifthenelse(c, t::Integer, e::Edge)` — scalar arms accepted; constant edges
  are created in the integer forest paired with `c` (or `t`/`e`'s own forest).
- `@match` now accepts integer literal arm values in addition to `Edge` values.
- `MDDForestBool._int_forest::WeakRef` back-reference set by `MDDForestInt`
  constructor, enabling `ifthenelse(bool_edge, 5, 10)` without an explicit
  integer forest argument.

### Changed
- `todot` rewritten as pure Julia BFS; removed the unused `_ll_edge_todot`
  C binding.
- `_meddly_initialized` flag added: `initialize()` sets it, `cleanup()` clears
  it, `mdd()` auto-initialises when the flag is false.

---

## [0.2.0] — 2026-04-26

**Breaking changes** — `Forest` is removed; update call sites as follows:

| Before | After |
|--------|-------|
| `Forest(dom)` | `MDDForestBool(dom)` |
| `Forest(dom; range = :integer)` | `MDDForestInt(dom)` |

### Added
- `abstract type AbstractForest` — dispatch supertype for all forest kinds.
- `MDDForestBool <: AbstractForest` — boolean multi-terminal MDD forest.
- `MDDForestInt <: AbstractForest` — integer multi-terminal MDD forest;
  eagerly creates a paired `bool_forest::MDDForestBool`.
- `bool_forest(f)` — returns the boolean forest associated with `f`.
- **C++ `ite_mt` ternary operation** (`meddly_edge_ifthenelse`) implemented
  as a `MEDDLY::ternary_operation` subclass with compute-table memoisation;
  used when the `ifthenelse` condition is a `MDDForestBool` edge.
- `@match` macro — expands `condition => value` arms into nested `ifthenelse`
  calls; `&&` / `||` in conditions are rewritten to `land` / `lor`.
- Comparison operator overloads (`==`, `!=`, `<`, `<=`, `>`, `>=`) infer the
  result boolean forest from the operand, so no explicit `bool_f` argument is
  needed.
- `terminal_value` split into typed methods: returns `Bool` for
  `MDDForestBool`, `Int` for `MDDForestInt`.
- Test suite split into 8 feature files (164 tests total, including
  `test_match.jl` with 34 tests).

### Removed
- `Forest` struct and its constructor — replaced by `MDDForestBool` /
  `MDDForestInt`.
- `range::Symbol` field — type dispatch replaces runtime symbol checks.

---

## [0.1.1] — 2026-04-26

### Added
- **MDD traversal API** for writing custom algorithms directly in Julia:
  - `NodeHandle` (`Int32`) — opaque node identifier; ≤ 0 for terminals.
  - `root_node(e)` — root handle of an edge.
  - `num_vars(f)` — number of variables K in the forest's domain.
  - `level_size(f, k)` — domain size at level k.
  - `is_terminal(node)` — true for handles ≤ 0 (no forest pointer needed).
  - `node_level(f, node)` — 0 for terminals, 1..K for internal nodes.
  - `terminal_value(f, node)` — decoded terminal value (`Bool` or `Int`).
  - `node_children(f, node)` — dense `Vector{NodeHandle}` of all children.
- C shim additions: `meddly_edge_get_node`, `meddly_forest_num_vars`,
  `meddly_forest_level_size`, `meddly_node_is_terminal`, `meddly_node_level`,
  `meddly_node_bool_value`, `meddly_node_int_value`, `meddly_node_get_children`.
- `test/test_traverse.jl` — 47 tests covering evaluation, cardinality,
  minterm collection, and level-skip handling.
- README: traversal section with 4 worked examples.

---

## [0.1.0] — 2026-04-26

Initial release.

### Added
- Boolean MDD forest (`MDDForestBool`) with set operations: `|`, `&`,
  `setdiff`, `lnot`.
- Integer MDD forest (`MDDForestInt`) with pointwise arithmetic: `+`, `-`,
  `*`, `max`, `min`.
- Comparison functions returning boolean edges: `eq`, `neq`, `lt`, `lte`,
  `gt`, `gte`.
- Logical operators: `land`, `lor`, `lnot`.
- Cross-forest copy (`copy_edge`) and conditional selection (`ifthenelse`).
- DOT visualisation (`todot`).
- Automatic library lifecycle: `initialize()` / `cleanup()`.
- C ABI shim (`c/meddly_c.cpp` / `c/meddly_c.h`) wrapping MEDDLY 0.18.x.
- Build system (`deps/build.jl`) that fetches and compiles MEDDLY from source.
- Test suite: 83 tests across 6 feature files.
