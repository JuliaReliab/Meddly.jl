# Meddly.jl

Julia wrapper for the [MEDDLY](https://github.com/asminer/meddly) C++ library
(Multi-terminal and Edge-valued Decision Diagram LibrarY).

The package communicates with MEDDLY through a thin C ABI shim (`libmeddly_c`)
so that no C++ symbols cross the Julia boundary.  MEDDLY and the shim are
built automatically by `Pkg.build`.

---

## Installation

Prerequisites: `git`, `autoconf`, `automake`, `glibtool` (macOS) / `libtool`
(Linux), and a C++ compiler (`clang++` or `g++`).

```julia
using Pkg
Pkg.develop(path = "/path/to/Meddly.jl")
Pkg.build("Meddly")          # downloads MEDDLY source and builds everything
```

---

## Quick start — Boolean MDD (set of assignments)

```julia
using Meddly

initialize()   # must be called once per process before anything else

# Domain: 3 variables, each taking values 0 or 1
dom = Domain([2, 2, 2])

# Boolean MDD forest
f = Forest(dom)

# Single-minterm edges
a = Edge(f, [0, 0, 1])   # {(0,0,1)}
b = Edge(f, [1, 0, 1])   # {(1,0,1)}

# Set operations
u = a | b           # union          → {(0,0,1),(1,0,1)}
i = a & a           # intersection   → {(0,0,1)}
d = setdiff(u, b)   # difference     → {(0,0,1)}

cardinality(u)   # → 2.0
is_empty(d)      # → false

cleanup()   # release global MEDDLY state
```

---

## Integer forest — pointwise functions

Pass `range = :integer` to `Forest` to build an integer-valued MDD where each
minterm maps to an integer instead of a boolean flag.

```julia
using Meddly
initialize()

dom = Domain([4, 4])   # 2 variables, each 0..3 (16 minterms total)
f   = Forest(dom; range = :integer)

# Constant edge: every minterm → 5
c5 = Edge(f, 5)
cardinality(c5)   # → 16.0   (16 non-zero minterms)

# Constant 0 edge: every minterm → 0  (equivalent to the empty function)
c0 = Edge(f, 0)
is_empty(c0)      # → true

# Single-minterm edge: (x1=1, x2=2) → 7, all others → 0
e7 = Edge(f, [1, 2], 7)
cardinality(e7)   # → 1.0
```

### Arithmetic operations

Integer-forest edges support pointwise arithmetic.

```julia
ea = Edge(f, [1, 2], 5)   # (1,2) → 5
eb = Edge(f, [1, 2], 3)   # (1,2) → 3

ea + eb       # (1,2) → 8
ea - eb       # (1,2) → 2
ea * eb       # (1,2) → 15
max(ea, eb)   # (1,2) → 5
min(ea, eb)   # (1,2) → 3

is_empty(ea - ea)   # → true  (zero function)
```

---

## Comparisons and logical operators

Comparison operators take two integer-forest edges and a boolean-forest target,
and return a boolean-forest edge that is `true` wherever the comparison holds.

```julia
bool_f = Forest(dom)
int_f  = Forest(dom; range = :integer)

ea = Edge(int_f, [1, 2], 5)
eb = Edge(int_f, [1, 2], 3)

c_gt  = gt(ea, eb, bool_f)    # true at (1,2); false elsewhere  → card = 1
c_lt  = lt(ea, eb, bool_f)    # false everywhere                → card = 0
c_eq  = eq(ea, eb, bool_f)    # true at the other 15 minterms   → card = 15
c_neq = neq(ea, eb, bool_f)   # true at (1,2)                   → card = 1
c_gte = gte(ea, eb, bool_f)   # (1,2) and 15 others             → card = 16
c_lte = lte(ea, eb, bool_f)   # false at (1,2), true elsewhere  → card = 15

cardinality(c_gt)    # → 1.0
```

### Logical operators on boolean edges

```julia
c1 = gt(ea, eb, bool_f)           # true at (1,2)
ec = Edge(int_f, [2, 3], 7)
c2 = gt(ec, ea, bool_f)           # true at (2,3)

c_and = land(c1, c2)              # true nowhere (no minterm satisfies both)
c_or  = lor(c1, c2)               # true at (1,2) and (2,3)
c_not = lnot(c1)                  # true everywhere except (1,2)

is_empty(c_and)           # → true
cardinality(c_or)         # → 2.0
cardinality(c_not)        # → 15.0
```

---

## Cross-forest copy and conditional selection

### `copy_edge` — cast a boolean edge to an integer forest

```julia
c_bool = gt(ea, eb, bool_f)          # boolean: true at (1,2)
c_int  = copy_edge(c_bool, int_f)    # integer: 1 at (1,2), 0 elsewhere
cardinality(c_int)   # → 1.0
```

### `ifthenelse` — pointwise conditional

```julia
ea = Edge(int_f, [1, 2], 5)
eb = Edge(int_f, [1, 2], 3)
ec = Edge(int_f, [2, 3], 7)

# Boolean condition (auto-converted; no manual copy_edge needed)
cond   = gt(ea, eb, bool_f)       # true at (1,2)
result = ifthenelse(cond, ea, ec)
# At (1,2): cond=true  → ea = 5
# At (2,3): cond=false → ec = 7
# Elsewhere: both ea=0, ec=0
cardinality(result)   # → 2.0
```

The condition can also be a compound boolean expression:

```julia
one_e = Edge(int_f, 1)
ten_e = Edge(int_f, 10)
# x in (1, 10]: gt(x, 1) AND lte(x, 10)
cond2 = land(gt(x_edge, one_e, bool_f), lte(x_edge, ten_e, bool_f))
result2 = ifthenelse(cond2, x_edge, three_e)
```

---

## MDD traversal — writing your own algorithms

The traversal API exposes the raw node structure of any MDD so you can
implement arbitrary algorithms in pure Julia.

### Key concepts

- **`NodeHandle`** (`Int32`) — an integer that identifies a node.
  Terminal nodes have handle ≤ 0; internal nodes have handle > 0.
- Internal nodes sit at a level `1..K` and have one child per variable
  value (0-indexed).  Children may skip levels in a fully-reduced MDD.
- Terminal nodes encode a value:
  - Boolean false → handle `0`; true → handle `-1`.
  - Integer zero  → handle `0`; value `v ≠ 0` → handle with sign bit set.

### Primitives

```julia
root_node(e)              # NodeHandle — root of edge e
num_vars(f)               # Int        — number of variables K
level_size(f, k)          # Int        — domain size at level k (1..K)

is_terminal(node)         # Bool       — no forest pointer needed
node_level(f, node)       # Int        — 0 for terminals, 1..K for internal
terminal_value(f, node)   # Bool or Int depending on f.range
node_children(f, node)    # Vector{NodeHandle}, length = level_size(f, level)
                          # children[i+1] is the child for variable value i
```

### Example 1 — evaluate at a single variable assignment

```julia
# var_values[level] = 0-indexed value for the variable at that level
function evaluate(f, node::NodeHandle, var_values)
    while !is_terminal(node)
        lv   = node_level(f, node)
        node = node_children(f, node)[var_values[lv] + 1]
    end
    terminal_value(f, node)
end

dom   = Domain([4, 4])
int_f = Forest(dom; range = :integer)
ea    = Edge(int_f, [1, 2], 5)   # (1,2) → 5, else 0

evaluate(int_f, root_node(ea), [1, 2])   # → 5
evaluate(int_f, root_node(ea), [0, 0])   # → 0
```

### Example 2 — cardinality via memoized traversal

The standard `cardinality` function is built into the library, but this
example shows how to reproduce it with the traversal API, including the
correct handling of skipped levels in a fully-reduced MDD.

```julia
function my_cardinality(f, node::NodeHandle,
                        cache = Dict{NodeHandle, Float64}())
    haskey(cache, node) && return cache[node]
    v = if is_terminal(node)
        terminal_value(f, node) ? 1.0 : 0.0   # boolean forest
    else
        lv = node_level(f, node)
        total = 0.0
        for child in node_children(f, node)
            # Each skipped level contributes a multiplicative factor
            child_lv   = is_terminal(child) ? 0 : node_level(f, child)
            gap_factor = prod(Float64(level_size(f, k))
                              for k in (child_lv + 1):(lv - 1); init = 1.0)
            total += gap_factor * my_cardinality(f, child, cache)
        end
        total
    end
    cache[node] = v
end

dom = Domain([4, 4])
f   = Forest(dom)
e   = Edge(f, [0, 0]) | Edge(f, [1, 1]) | Edge(f, [2, 2])

my_cardinality(f, root_node(e))   # → 3.0
cardinality(e)                    # → 3.0  (same result)
```

### Example 3 — collect all minterms in a boolean MDD

```julia
function collect_minterms(f, node::NodeHandle, path, results)
    if is_terminal(node)
        terminal_value(f, node) && push!(results, copy(path))
        return
    end
    lv = node_level(f, node)
    for (i, child) in enumerate(node_children(f, node))
        path[lv] = i - 1   # variable at level lv takes value i-1
        collect_minterms(f, child, path, results)
    end
end

dom = Domain([3, 3])
f   = Forest(dom)
e   = Edge(f, [0, 1]) | Edge(f, [2, 0])

path    = zeros(Int, num_vars(f))
results = Vector{Vector{Int}}()
collect_minterms(f, root_node(e), path, results)
# results == [[0, 1], [2, 0]]  (or in some order)
```

### Example 4 — sum of all integer values

```julia
function sum_values(f, node::NodeHandle, cache = Dict{NodeHandle, Float64}())
    haskey(cache, node) && return cache[node]
    v = if is_terminal(node)
        Float64(terminal_value(f, node))
    else
        lv = node_level(f, node)
        total = 0.0
        for child in node_children(f, node)
            child_lv   = is_terminal(child) ? 0 : node_level(f, child)
            gap_factor = prod(Float64(level_size(f, k))
                              for k in (child_lv + 1):(lv - 1); init = 1.0)
            total += gap_factor * sum_values(f, child, cache)
        end
        total
    end
    cache[node] = v
end

dom   = Domain([4, 4])
int_f = Forest(dom; range = :integer)
# Build the identity function: minterm (v1, v2) → v1 + v2
e = sum(Edge(int_f, [v1, v2], v1 + v2)
        for v1 in 0:3, v2 in 0:3)

sum_values(int_f, root_node(e))   # → sum of all v1+v2 = 2 * 4 * (0+1+2+3) * 4 = 192.0
```

---

## Visualization

`todot` serializes any edge as a Graphviz DOT string.

```julia
dom = Domain([2, 2, 2])
f   = Forest(dom)
e   = Edge(f, [0, 1, 0])

dot_str = todot(e)   # String containing "digraph { … }"
```

Pipe it to Graphviz to render:

```sh
julia -e '
using Meddly; initialize()
dom = Domain([2,2,2]); f = Forest(dom); e = Edge(f, [0,1,0])
write(stdout, todot(e)); cleanup()
' | dot -Tpng -o edge.png
```

---

## API reference

| Function | Description |
|---|---|
| `initialize()` | Initialize the MEDDLY library (once per process) |
| `cleanup()` | Release MEDDLY global state |
| `Domain(sizes)` | Domain with `sizes[i]` values for variable `i` |
| `Forest(dom; kind, range)` | Forest in `dom`; `kind ∈ {:mdd,:mxd}`, `range ∈ {:boolean,:integer}` |
| `Edge(f)` | Empty boolean edge |
| `Edge(f, values)` | Single-minterm boolean edge |
| `Edge(f, const_val)` | Constant integer edge (all minterms → `const_val`) |
| `Edge(f, values, val)` | Single-minterm integer edge |
| `a \| b` | Boolean union |
| `a & b` | Boolean intersection |
| `setdiff(a, b)` | Boolean set difference |
| `a + b` | Integer pointwise addition |
| `a - b` | Integer pointwise subtraction |
| `a * b` | Integer pointwise multiplication |
| `max(a, b)` | Integer pointwise maximum |
| `min(a, b)` | Integer pointwise minimum |
| `eq(a, b, bool_f)` | Boolean: `a == b` |
| `neq(a, b, bool_f)` | Boolean: `a != b` |
| `lt(a, b, bool_f)` | Boolean: `a < b` |
| `lte(a, b, bool_f)` | Boolean: `a <= b` |
| `gt(a, b, bool_f)` | Boolean: `a > b` |
| `gte(a, b, bool_f)` | Boolean: `a >= b` |
| `land(a, b)` | Logical AND of two boolean edges |
| `lor(a, b)` | Logical OR of two boolean edges |
| `lnot(a)` | Logical complement of a boolean edge |
| `copy_edge(e, target_f)` | Copy edge into another forest (e.g., boolean → integer) |
| `ifthenelse(cond, t, e)` | Pointwise `cond ? t : e`; boolean `cond` is auto-converted |
| `cardinality(e)` | Number of non-zero minterms (Float64) |
| `is_empty(e)` | True iff the edge represents the all-zero / empty function |
| `todot(e)` | Graphviz DOT string for the decision diagram |
| **Traversal** | |
| `NodeHandle` | Type alias for `Int32`; identifies a node (≤ 0 = terminal) |
| `root_node(e)` | Root `NodeHandle` of an edge |
| `num_vars(f)` | Number of variables K in the forest's domain |
| `level_size(f, k)` | Domain size (number of values) for the variable at level k |
| `is_terminal(node)` | True if handle ≤ 0 (no forest pointer required) |
| `node_level(f, node)` | Level: 0 for terminals, 1..K for internal nodes |
| `terminal_value(f, node)` | Decoded terminal value: `Bool` or `Int` |
| `node_children(f, node)` | Dense `Vector{NodeHandle}` of all children |

---

## Architecture

```
Julia user code
      │
      │  (Julia structs: Domain, Forest, Edge)
      │
src/highlevel.jl   ← public API
src/types.jl       ← mutable structs + GC finalizers
src/lowlevel.jl    ← ccall wrappers (_ll_* functions)
      │
      │  dlopen("libmeddly_c")
      │
c/meddly_c.cpp     ← C ABI shim (extern "C"; all C++ exceptions caught)
      │
      │  static link
      │
deps/usr/lib/libmeddly.a   ← MEDDLY 0.18.x built by Pkg.build
```

Memory ownership: each Julia struct holds a `Ptr{Cvoid}` to a C++-heap object;
its finalizer calls the matching `meddly_*_destroy` function.  Each child also
holds a reference to its parent (`Edge → Forest → Domain`) so the parent cannot
be GC'd while the child is alive.

---

## Running tests

```sh
julia --project=. test/runtests.jl
```

(`Pkg.test()` is broken for stdlib dependencies in Julia 1.12; use the direct
form above.)

---

## Known limitations

- EV+MDD (edge-valued decision diagrams with `EVPLUS`/`EVTIMES`) are not yet
  supported.  The `ifthenelse` formula relies on integer arithmetic, which
  is incompatible with MEDDLY's OMEGA_INFINITY absorption semantics for EV+MDD.
  See `TODO.md` for details and planned approaches.
- No iteration over individual minterms yet.
- Relation forests (`kind = :mxd`) are wired up but minimally tested.
- `libmeddly_c` is built locally; there is no JLL artifact yet.
