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

## Quick start — session API

The easiest way to use Meddly.jl is through the **session API**.  Create a
session with `mdd()`, register variables with `defvar!`, and build projection
edges with `var!`.  MEDDLY is initialised automatically.

```julia
using Meddly

b = mdd()                          # create a session
defvar!(b, :x, 3, [0, 1])         # variable :x at level 3, domain {0,1}
defvar!(b, :y, 2, [0, 1, 2])      # variable :y at level 2, domain {0,1,2}
defvar!(b, :z, 1, [0, 1, 2])      # variable :z at level 1, domain {0,1,2}

x = var!(b, :x)    # Edge: f(x,y,z) = x
y = var!(b, :y)    # Edge: f(x,y,z) = y
z = var!(b, :z)    # Edge: f(x,y,z) = z

# Arithmetic with scalars
f = 3*x + y - 2*z

# Comparisons → boolean Edge
result = f >= 0

# Logical operators
cond = and(f >= 0, f < 2)   # 0 ≤ f < 2
neg  = !cond                 # complement

# ifthenelse with scalar arms
g = ifthenelse(result, 5, 10)   # 5 where f≥0, 10 elsewhere

# @match with integer arm values
label = @match(
    x == 0        => 0,
    y == 0 && z == 0 => 0,
    y == 0 || z == 0 => 1,
    y == 2 || z == 2 => 3,
    _             => 2)

cleanup()   # release MEDDLY global state when done
```

`defvar!` arguments: `name::Symbol`, `level::Int` (1 = closest to terminals,
higher = closer to root), `domain::Vector{Int}` (the values taken by that
variable).

---

## Low-level API — Boolean MDD (set of assignments)

```julia
using Meddly

initialize()   # must be called once per process before anything else

# Domain: 3 variables, each taking values 0 or 1
dom = Domain([2, 2, 2])

# Boolean MDD forest
f = MDDForestBool(dom)

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

## Low-level API — Integer forest (pointwise functions)

Use `MDDForestInt` to build an integer-valued MDD where each minterm maps to
an integer.

```julia
using Meddly
initialize()

dom   = Domain([4, 4])   # 2 variables, each 0..3 (16 minterms total)
int_f = MDDForestInt(dom)

# Constant edge: every minterm → 5
c5 = Edge(int_f, 5)
cardinality(c5)   # → 16.0   (16 non-zero minterms)

# Single-minterm edge: (x1=1, x2=2) → 7, all others → 0
e7 = Edge(int_f, [1, 2], 7)
cardinality(e7)   # → 1.0
```

### Arithmetic operations

```julia
ea = Edge(int_f, [1, 2], 5)   # (1,2) → 5
eb = Edge(int_f, [1, 2], 3)   # (1,2) → 3

ea + eb       # (1,2) → 8
ea - eb       # (1,2) → 2
ea * eb       # (1,2) → 15
max(ea, eb)   # (1,2) → 5
min(ea, eb)   # (1,2) → 3
```

---

## Scalar overloads (Edge ↔ integer literal)

Arithmetic and comparison operators accept an integer literal on either side.
A constant integer edge is created automatically.

```julia
# Arithmetic
ea + 10        # each minterm value + 10
2 * ea         # each minterm value × 2
-ea            # negate each minterm value

# Comparison → boolean Edge
ea == 5        # true where ea's value equals 5
ea >= 3        # true where ea's value is ≥ 3
0 < ea         # true where ea's value is positive
```

---

## Comparisons and logical operators

### Operator overloads — Edge vs Edge

`MDDForestInt` eagerly creates a paired `bool_forest`, enabling the standard
Julia comparison operators directly on any pair of integer-forest edges.

```julia
int_f = MDDForestInt(dom)
ea    = Edge(int_f, [1, 2], 5)
eb    = Edge(int_f, [1, 2], 3)

ea > eb    # → boolean edge, true at (1,2)
ea < eb    # → boolean edge, empty
ea == eb   # → boolean edge, true at the other 15 minterms
ea != eb   # → boolean edge, true at (1,2)
ea >= eb   # → boolean edge, card = 16
ea <= eb   # → boolean edge, card = 15
```

### Explicit comparison functions

```julia
bool_f = MDDForestBool(dom)
c_gt   = gt(ea, eb, bool_f)    # true at (1,2)
c_lte  = lte(ea, eb, bool_f)   # true at 15 minterms
```

### Logical operators

```julia
c1 = ea > eb               # boolean edge

# Named functions (recommended with session API)
and(c1, c2)     # logical AND  (= land)
or(c1, c2)      # logical OR   (= lor)
!c1             # complement   (= lnot)

# Original names
land(c1, c2)
lor(c1, c2)
lnot(c1)
```

---

## Cross-forest copy and conditional selection

### `copy_edge` — cast a boolean edge to an integer forest

```julia
c_bool = ea > eb                  # boolean: true at (1,2)
c_int  = copy_edge(c_bool, int_f) # integer: 1 at (1,2), 0 elsewhere
```

### `ifthenelse` — pointwise conditional

`ifthenelse(c, t, e)` accepts `t` and `e` as `Edge` objects or as integer
scalar literals.  When the condition is a `MDDForestBool` edge, the efficient
C++ `ite_mt` ternary operation (with compute-table memoisation) is used.

```julia
cond = ea > eb          # boolean condition, true at (1,2)

# Edge arms
ifthenelse(cond, ea, ec)   # ea at (1,2), ec elsewhere

# Integer scalar arms (constant edges created automatically)
ifthenelse(cond, 5, 10)    # 5 at (1,2), 10 elsewhere

# Mixed
ifthenelse(cond, ea, 0)    # ea where true, 0 elsewhere
```

---

## `@match` macro — multi-arm conditional

`@match` expands a sequence of `condition => value` arms into nested
`ifthenelse` calls.  The last arm should use `_` as the catch-all.
`&&` and `||` in conditions are automatically rewritten to `land` and `lor`.
Both `Edge` and integer literal values are accepted as arm values.

```julia
# With Edge arms
ea = Edge(int_f, [1, 2], 5)
result = @match(
    ea > eb => ea,
    ec > ea => ec,
    _       => ed
)

# With integer scalar arms (session API style)
b = mdd()
defvar!(b, :x, 2, [0, 1])
defvar!(b, :y, 1, [0, 1, 2])
x = var!(b, :x)
y = var!(b, :y)

label = @match(
    x == 0 && y == 0 => 0,
    x == 0           => 1,
    y == 2           => 3,
    _                => 2
)
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
terminal_value(f, node)   # Bool (MDDForestBool) or Int (MDDForestInt)
node_children(f, node)    # Vector{NodeHandle}, length = level_size(f, level)
                          # children[i+1] is the child for variable value i
```

### Example 1 — evaluate at a single variable assignment

```julia
function evaluate(f, node::NodeHandle, var_values)
    while !is_terminal(node)
        lv   = node_level(f, node)
        node = node_children(f, node)[var_values[lv] + 1]
    end
    terminal_value(f, node)
end

dom   = Domain([4, 4])
int_f = MDDForestInt(dom)
ea    = Edge(int_f, [1, 2], 5)   # (1,2) → 5, else 0

evaluate(int_f, root_node(ea), [1, 2])   # → 5
evaluate(int_f, root_node(ea), [0, 0])   # → 0
```

### Example 2 — cardinality via memoized traversal

```julia
function my_cardinality(f, node::NodeHandle,
                        cache = Dict{NodeHandle, Float64}())
    haskey(cache, node) && return cache[node]
    v = if is_terminal(node)
        terminal_value(f, node) ? 1.0 : 0.0
    else
        lv = node_level(f, node)
        total = 0.0
        for child in node_children(f, node)
            child_lv   = is_terminal(child) ? 0 : node_level(f, child)
            gap_factor = prod(Float64(level_size(f, k))
                              for k in (child_lv + 1):(lv - 1); init = 1.0)
            total += gap_factor * my_cardinality(f, child, cache)
        end
        total
    end
    cache[node] = v
end
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
        path[lv] = i - 1
        collect_minterms(f, child, path, results)
    end
end
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
```

---

## Visualization

`todot` serializes any edge as a Graphviz DOT string (implemented as a pure
Julia BFS; no temporary files).  If `Domain` was constructed with `labels`,
variable names are used as node labels.

```julia
dom = Domain([2, 2, 2]; labels = ["z", "y", "x"])
f   = MDDForestBool(dom)
e   = Edge(f, [0, 1, 0])

dot_str = todot(e)   # String containing "digraph { … }"
write("edge.dot", dot_str)
run(`dot -Tpng edge.dot -o edge.png`)
```

---

## API reference

### Session API

| Function | Description |
|---|---|
| `mdd()` | Create a new `MDDSession`; auto-initialises MEDDLY |
| `defvar!(b, name, level, domain)` | Register variable `name` at `level` with integer `domain` |
| `var!(b, name)` | Integer-forest `Edge` for the projection onto `name` |

### Lifecycle

| Function | Description |
|---|---|
| `initialize()` | Initialize the MEDDLY library (once per process) |
| `cleanup()` | Release MEDDLY global state |

### Types and constructors

| Function / Type | Description |
|---|---|
| `Domain(sizes; labels)` | Domain with `sizes[i]` values for variable at level `i`; optional `labels` used by `todot` |
| `MDDForestBool(dom; kind)` | Boolean MDD forest; `kind ∈ {:mdd, :mxd}` (default `:mdd`) |
| `MDDForestInt(dom; kind)` | Integer MDD forest; eagerly creates a paired `bool_forest` |
| `bool_forest(f)` | Return the `MDDForestBool` associated with `f` |
| `Edge(f)` | Empty boolean edge / zero integer function |
| `Edge(f, values)` | Single-minterm boolean edge |
| `Edge(f, const_val)` | Constant integer edge (all minterms → `const_val`) |
| `Edge(f, values, val)` | Single-minterm integer edge |

### Set operations (boolean forests)

| Expression | Description |
|---|---|
| `a \| b` | Union |
| `a & b` | Intersection |
| `setdiff(a, b)` | Set difference |

### Integer arithmetic

| Expression | Description |
|---|---|
| `a + b`, `a - b`, `a * b` | Pointwise arithmetic (Edge–Edge) |
| `a + n`, `n + a`, `a - n`, `n - a`, `a * n`, `n * a` | Same with integer scalar |
| `-a` | Unary negation |
| `max(a, b)`, `min(a, b)` | Pointwise max / min |

### Comparisons (→ boolean Edge)

| Expression | Description |
|---|---|
| `eq(a,b,f)`, `neq`, `lt`, `lte`, `gt`, `gte` | Explicit boolean forest |
| `a==b`, `a!=b`, `a<b`, `a<=b`, `a>b`, `a>=b` | Edge–Edge (boolean forest inferred) |
| `a==n`, `n==a`, `a<n`, … | Edge–scalar and scalar–Edge |

### Logical operators (boolean edges)

| Expression | Description |
|---|---|
| `and(a, b)` / `land(a, b)` | Logical AND |
| `or(a, b)` / `lor(a, b)` | Logical OR |
| `!a` / `lnot(a)` | Logical complement |

### Conditional selection

| Expression | Description |
|---|---|
| `copy_edge(e, f)` | Copy edge into another forest (e.g., boolean → integer) |
| `ifthenelse(c, t, e)` | Pointwise `c ? t : e`; `t` and `e` may be `Edge` or `Integer` |
| `@match(c1=>v1, …, _=>vd)` | Nested `ifthenelse`; `&&`/`\|\|` → `land`/`lor`; values may be `Edge` or `Integer` |

### Queries

| Expression | Description |
|---|---|
| `cardinality(e)` | Number of non-zero minterms (Float64) |
| `is_empty(e)` | True iff the edge is the all-zero / empty function |
| `todot(e)` | Graphviz DOT string for the decision diagram |

### Traversal

| Expression | Description |
|---|---|
| `NodeHandle` | Type alias for `Int32`; ≤ 0 = terminal |
| `root_node(e)` | Root `NodeHandle` of an edge |
| `num_vars(f)` | Number of variables K |
| `level_size(f, k)` | Domain size for the variable at level k |
| `is_terminal(node)` | True if handle ≤ 0 |
| `node_level(f, node)` | Level: 0 for terminals, 1..K for internal |
| `terminal_value(f, node)` | Decoded terminal: `Bool` or `Int` |
| `node_children(f, node)` | Dense `Vector{NodeHandle}` of all children |

---

## Architecture

```
Julia user code
      │
      │  MDDSession / mdd() / defvar! / var!     ← session API
      │  AbstractForest / MDDForestBool / MDDForestInt / Domain / Edge
      │
src/highlevel.jl   ← public API (operators, ifthenelse, @match, session, todot)
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

**Type hierarchy:**
- `abstract type AbstractForest` — dispatch supertype
- `MDDForestBool <: AbstractForest` — boolean multi-terminal MDD; holds a
  `WeakRef` to its paired `MDDForestInt` (set when one is created), enabling
  `ifthenelse(bool_edge, 5, 10)` without an explicit integer forest argument
- `MDDForestInt <: AbstractForest` — integer multi-terminal MDD; owns an
  eagerly created `bool_forest::MDDForestBool`

**`var!` projection construction:** MEDDLY has no "project onto variable k"
primitive, so `var!(b, :x)` sums single-minterm `Edge` objects over all
combinations of other variables.  MEDDLY's full-reduction policy collapses the
result to a compact single-level node automatically.

**Memory ownership:** each Julia struct holds a `Ptr{Cvoid}` to a C++-heap
object; its finalizer calls the matching `meddly_*_destroy` function.  Each
child holds a reference to its parent (`Edge → AbstractForest → Domain`) so
the parent cannot be GC'd while the child is alive.

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
  supported.  The `ifthenelse` formula relies on integer arithmetic, which is
  incompatible with MEDDLY's OMEGA_INFINITY absorption semantics for EV+MDD.
  See `TODO.md` for details and planned approaches.
- No built-in minterm iteration yet; use the traversal API to walk nodes
  and collect minterms manually (see `collect_minterms` example above).
- Relation forests (`kind = :mxd`) are wired up but minimally tested.
- `libmeddly_c` is built locally; there is no JLL artifact yet.
