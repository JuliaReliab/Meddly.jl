# High-level Julia API built on top of types.jl and lowlevel.jl.

# ------------------------------------------------------------------ #
# Library lifecycle                                                    #
# ------------------------------------------------------------------ #

"""
    initialize()

Initialize the MEDDLY library.  Must be called before any other Meddly
operation and before creating any `Domain`, `Forest`, or `Edge`.
"""
function initialize()
    _check(_ll_initialize())
end

"""
    cleanup()

Release all MEDDLY global resources.  All `Domain`/`Forest`/`Edge`
objects must be garbage-collected (or explicitly freed) before calling
this function, otherwise behaviour is undefined.
"""
function cleanup()
    _check(_ll_cleanup())
end

# ------------------------------------------------------------------ #
# Set operations                                                       #
# ------------------------------------------------------------------ #

"""
    a | b  →  Edge

Union of two edges (logical OR for boolean forests).
"""
function Base.:(|)(a::Edge, b::Edge)
    ret, ptr = _ll_edge_union(a.ptr, b.ptr)
    _check(ret)
    _make_edge(ptr, a.forest)
end

"""
    a & b  →  Edge

Intersection of two edges (logical AND for boolean forests).
"""
function Base.:(&)(a::Edge, b::Edge)
    ret, ptr = _ll_edge_intersection(a.ptr, b.ptr)
    _check(ret)
    _make_edge(ptr, a.forest)
end

"""
    setdiff(a, b)  →  Edge

Set difference: elements in `a` but not in `b`.
"""
function Base.setdiff(a::Edge, b::Edge)
    ret, ptr = _ll_edge_difference(a.ptr, b.ptr)
    _check(ret)
    _make_edge(ptr, a.forest)
end

# ------------------------------------------------------------------ #
# Integer arithmetic operations                                        #
# ------------------------------------------------------------------ #

function _apply_binary(op_id::Cint, a::Edge, b::Edge)
    ret, ptr = _ll_edge_apply_binary(op_id, a.ptr, b.ptr)
    _check(ret)
    _make_edge(ptr, a.forest)
end

"""
    a + b  →  Edge

Pointwise addition of two integer-valued edges.
"""
Base.:(+)(a::Edge, b::Edge) = _apply_binary(_OP_PLUS, a, b)

"""
    a - b  →  Edge

Pointwise subtraction of two integer-valued edges.
"""
Base.:(-)(a::Edge, b::Edge) = _apply_binary(_OP_MINUS, a, b)

"""
    a * b  →  Edge

Pointwise multiplication of two integer-valued edges.
"""
Base.:(*)(a::Edge, b::Edge) = _apply_binary(_OP_MULTIPLY, a, b)

"""
    max(a, b)  →  Edge

Pointwise maximum of two integer-valued edges.
"""
Base.max(a::Edge, b::Edge) = _apply_binary(_OP_MAXIMUM, a, b)

"""
    min(a, b)  →  Edge

Pointwise minimum of two integer-valued edges.
"""
Base.min(a::Edge, b::Edge) = _apply_binary(_OP_MINIMUM, a, b)

# ------------------------------------------------------------------ #
# Comparison operators (result in a boolean forest)                    #
# ------------------------------------------------------------------ #

function _compare(op_id::Cint, a::Edge, b::Edge, rf::Forest)
    ret, ptr = _ll_edge_apply_binary_rf(op_id, a.ptr, b.ptr, rf.ptr)
    _check(ret)
    _make_edge(ptr, rf)
end

"""
    eq(a, b, bool_forest)  →  Edge

Pointwise equality: boolean edge true where `a == b`.
`bool_forest` must be a boolean `Forest` over the same domain as `a` and `b`.
"""
eq(a::Edge, b::Edge, rf::Forest)  = _compare(_OP_EQUAL,              a, b, rf)

"""
    neq(a, b, bool_forest)  →  Edge

Pointwise inequality: boolean edge true where `a != b`.
"""
neq(a::Edge, b::Edge, rf::Forest) = _compare(_OP_NOT_EQUAL,          a, b, rf)

"""
    lt(a, b, bool_forest)  →  Edge

Pointwise less-than: boolean edge true where `a < b`.
"""
lt(a::Edge, b::Edge, rf::Forest)  = _compare(_OP_LESS_THAN,          a, b, rf)

"""
    lte(a, b, bool_forest)  →  Edge

Pointwise less-than-or-equal: boolean edge true where `a <= b`.
"""
lte(a::Edge, b::Edge, rf::Forest) = _compare(_OP_LESS_THAN_EQUAL,    a, b, rf)

"""
    gt(a, b, bool_forest)  →  Edge

Pointwise greater-than: boolean edge true where `a > b`.
"""
gt(a::Edge, b::Edge, rf::Forest)  = _compare(_OP_GREATER_THAN,       a, b, rf)

"""
    gte(a, b, bool_forest)  →  Edge

Pointwise greater-than-or-equal: boolean edge true where `a >= b`.
"""
gte(a::Edge, b::Edge, rf::Forest) = _compare(_OP_GREATER_THAN_EQUAL, a, b, rf)

# ------------------------------------------------------------------ #
# Named logical operators for boolean-forest edges                     #
# ------------------------------------------------------------------ #

"""
    land(a, b)  →  Edge

Logical AND (intersection) of two boolean-forest edges.
Equivalent to `a & b`.
"""
land(a::Edge, b::Edge) = a & b

"""
    lor(a, b)  →  Edge

Logical OR (union) of two boolean-forest edges.
Equivalent to `a | b`.
"""
lor(a::Edge, b::Edge) = a | b

"""
    lnot(a)  →  Edge

Logical NOT (complement) of a boolean-forest edge: flips true↔false.
"""
function lnot(a::Edge)
    ret, ptr = _ll_edge_complement(a.ptr)
    _check(ret)
    _make_edge(ptr, a.forest)
end

# ------------------------------------------------------------------ #
# Cross-forest COPY and ifthenelse                                     #
# ------------------------------------------------------------------ #

"""
    copy_edge(e::Edge, target::Forest)  →  Edge

Copy `e` into `target` (same domain, different range type).
Primary use: convert a boolean-forest edge to an integer-forest edge
(false → 0, true → 1), enabling it to drive arithmetic operations.
"""
function copy_edge(e::Edge, target::Forest)
    ret, ptr = _ll_edge_copy(e.ptr, target.ptr)
    _check(ret)
    _make_edge(ptr, target)
end

"""
    ifthenelse(c::Edge, t::Edge, e::Edge)  →  Edge

Pointwise conditional: returns `t` where `c` is non-zero, `e` elsewhere.

`c` may be either:
- a **boolean-forest** edge (result of a comparison or logical operator):
  automatically converted to an integer 0/1 edge via `copy_edge`.
- an **integer-forest** edge with values in {0, 1}: used directly.

`t` and `e` must be in the same integer forest.

Implemented as `c * t + (1 − c) * e` using MEDDLY's arithmetic operations.
"""
function ifthenelse(c::Edge, t::Edge, e::Edge)
    c_int = c.forest.range == :boolean ? copy_edge(c, t.forest) : c
    one_e = Edge(t.forest, 1)
    c_int * t + (one_e - c_int) * e
end

# ------------------------------------------------------------------ #
# Queries                                                              #
# ------------------------------------------------------------------ #

"""
    todot(e::Edge) → String

Return a Graphviz DOT-format string representing the decision diagram for `e`.

The result can be written to a `.dot` file and rendered with the `dot` command:

```julia
write("graph.dot", todot(e))
run(`dot -Tpdf graph.dot -o graph.pdf`)
```
"""
function todot(e::Edge)::String
    dir = mktempdir()
    try
        base = joinpath(dir, "g")
        _check(_ll_edge_todot(e.ptr, base))
        read(base * ".dot", String)
    finally
        rm(dir; recursive = true, force = true)
    end
end

"""
    cardinality(e::Edge) → Float64

Return the number of elements (minterms) represented by `e`.
For large sets the count can exceed Int64 range, so a Float64 is used.
Returns -1.0 if the underlying MEDDLY call failed.
"""
function cardinality(e::Edge)
    _ll_edge_cardinality(e.ptr)
end

"""
    is_empty(e::Edge) → Bool

Return `true` if `e` represents the empty set.
"""
function is_empty(e::Edge)
    _ll_edge_is_empty(e.ptr)
end

# ------------------------------------------------------------------ #
# Traversal                                                            #
# ------------------------------------------------------------------ #

"""
    NodeHandle

Integer type (`Int32`) used as a node identifier within a MEDDLY forest.
Terminal nodes have handle ≤ 0; internal nodes have handle > 0.

Terminal encoding for MT forests:
- Boolean false → `0`;  boolean true → `-1` (= `Int32(-1)`).
- Integer zero  → `0`;  integer value `v ≠ 0` → `Int32(v) | typemin(Int32)`.
"""
const NodeHandle = Int32

"""
    root_node(e::Edge) → NodeHandle

Return the root node handle of edge `e`.
"""
root_node(e::Edge) = NodeHandle(_ll_edge_get_node(e.ptr))

"""
    num_vars(f::Forest) → Int

Return the number of variables `K` in the forest's domain.
Internal nodes have levels 1 (bottom variable) through `K` (top variable).
"""
num_vars(f::Forest) = Int(_ll_forest_num_vars(f.ptr))

"""
    level_size(f::Forest, level::Int) → Int

Return the domain size (number of distinct values 0..size-1) for the
variable at `level` (1-indexed).  An internal node at `level` has exactly
this many children, one per variable value.
"""
level_size(f::Forest, level::Int) =
    Int(_ll_forest_level_size(f.ptr, Cint(level)))

"""
    is_terminal(node::NodeHandle) → Bool

Return `true` if `node` is a terminal node (handle ≤ 0).
This is a pure computation on the handle; no forest pointer is needed.
"""
is_terminal(node::NodeHandle) = node <= NodeHandle(0)

"""
    node_level(f::Forest, node::NodeHandle) → Int

Return the level of `node`: `0` for terminals, `1..K` for internal nodes.
"""
node_level(f::Forest, node::NodeHandle) =
    Int(_ll_node_level(f.ptr, Cint(node)))

"""
    terminal_value(f::Forest, node::NodeHandle) → Bool | Int

Return the value encoded in terminal `node`:
- Boolean forest → `Bool` (`false` or `true`).
- Integer forest  → `Int`.

Throws if `node` is not a terminal.
"""
function terminal_value(f::Forest, node::NodeHandle)
    is_terminal(node) ||
        error("terminal_value: node $(node) is not a terminal")
    if f.range == :boolean
        _ll_node_bool_value(f.ptr, Cint(node))
    else
        _ll_node_int_value(f.ptr, Cint(node))
    end
end

"""
    node_children(f::Forest, node::NodeHandle) → Vector{NodeHandle}

Return the dense child array of internal `node`.

The vector has length `level_size(f, node_level(f, node))`.
`children[i+1]` (1-based Julia index) is the child for variable value `i`
(0-based MEDDLY index).

In a fully-reduced MDD, the children's levels may be lower than
`node_level(f, node) - 1` (skipped levels act as redundant nodes).
Use `node_level` to determine the actual level of each child before
recursing.

Example — evaluate an integer MDD at a given variable assignment:
```julia
function evaluate(f, node, var_values)   # var_values[level] = value
    while !is_terminal(node)
        lv   = node_level(f, node)
        node = node_children(f, node)[var_values[lv] + 1]
    end
    terminal_value(f, node)
end
```

Throws if `node` is a terminal.
"""
function node_children(f::Forest, node::NodeHandle)
    is_terminal(node) &&
        error("node_children: node $(node) is a terminal")
    lv  = node_level(f, node)
    sz  = level_size(f, lv)
    out = Vector{Cint}(undef, sz)
    n   = _ll_node_get_children(f.ptr, Cint(node), out)
    n < 0 && error("MEDDLY error in node_children: $(_last_error_msg())")
    Vector{NodeHandle}(out)
end
