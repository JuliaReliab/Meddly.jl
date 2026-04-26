# Changelog

All notable changes to Meddly.jl are documented here.
Versions follow [Semantic Versioning](https://semver.org/).

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
