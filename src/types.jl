# Julia types that own MEDDLY C++ objects via Ptr{Cvoid}.
# Each public constructor calls the corresponding C create function and
# registers a finalizer.  Each child struct holds a reference to its
# parent (Edge → Forest → Domain) to prevent premature GC.

# ------------------------------------------------------------------ #
# Domain                                                               #
# ------------------------------------------------------------------ #

mutable struct Domain
    ptr::Ptr{Cvoid}
    labels::Vector{String}  # labels[k] = name for variable at level k (1-indexed)
                             # empty vector → todot falls back to "x{k}"

    function Domain(level_sizes::Vector{Int};
                    labels::Vector{String} = String[])
        isempty(level_sizes) && error("level_sizes must not be empty")
        !isempty(labels) && length(labels) != length(level_sizes) &&
            error("labels length ($(length(labels))) must equal level count ($(length(level_sizes)))")
        sizes = Cint.(level_sizes)
        ptr = _check_ptr(_ll_domain_create(sizes))
        d = new(ptr, labels)
        finalizer(d) do x
            if x.ptr != C_NULL
                _ll_domain_destroy(x.ptr)
                x.ptr = C_NULL
            end
        end
        d
    end
end

Base.show(io::IO, d::Domain) =
    print(io, "Domain(", d.ptr == C_NULL ? "destroyed" : string(d.ptr), ")")

# ------------------------------------------------------------------ #
# Forest kind / range constants — must match meddly_c.h               #
# ------------------------------------------------------------------ #

const _FOREST_MDD = Cint(0)
const _FOREST_MXD = Cint(1)

const _RANGE_BOOLEAN = Cint(0)
const _RANGE_INTEGER = Cint(1)

# Binary operation IDs — must match MEDDLY_OP_* in meddly_c.h
const _OP_PLUS               = Cint(10)
const _OP_MINUS              = Cint(11)
const _OP_MULTIPLY           = Cint(12)
const _OP_MAXIMUM            = Cint(13)
const _OP_MINIMUM            = Cint(14)
const _OP_EQUAL              = Cint(15)
const _OP_NOT_EQUAL          = Cint(16)
const _OP_LESS_THAN          = Cint(17)
const _OP_LESS_THAN_EQUAL    = Cint(18)
const _OP_GREATER_THAN       = Cint(19)
const _OP_GREATER_THAN_EQUAL = Cint(20)

# ------------------------------------------------------------------ #
# AbstractForest and concrete forest types                             #
# ------------------------------------------------------------------ #

"""
    AbstractForest

Abstract supertype for all MDD forest types.  Concrete subtypes:
- `MDDForestBool` — multi-terminal boolean MDD forest
- `MDDForestInt`  — multi-terminal integer MDD forest
"""
abstract type AbstractForest end

function _kind_int(kind::Symbol)
    kind == :mdd && return _FOREST_MDD
    kind == :mxd && return _FOREST_MXD
    error("Unknown forest kind :$kind  (expected :mdd or :mxd)")
end

"""
    MDDForestBool(domain; kind = :mdd)

Boolean multi-terminal MDD forest over `domain`.
"""
mutable struct MDDForestBool <: AbstractForest
    ptr::Ptr{Cvoid}
    domain::Domain
    _int_forest::WeakRef   # back-reference to the paired MDDForestInt (if any)

    function MDDForestBool(domain::Domain; kind::Symbol = :mdd)
        ptr = _check_ptr(_ll_forest_create(domain.ptr, _kind_int(kind), _RANGE_BOOLEAN))
        f = new(ptr, domain, WeakRef(nothing))
        finalizer(f) do x
            if x.ptr != C_NULL
                _ll_forest_destroy(x.ptr)
                x.ptr = C_NULL
            end
        end
        f
    end
end

Base.show(io::IO, f::MDDForestBool) =
    print(io, "MDDForestBool(", f.ptr == C_NULL ? "destroyed" : string(f.ptr), ")")

"""
    MDDForestInt(domain; kind = :mdd)

Integer multi-terminal MDD forest over `domain`.

A paired boolean forest (`bool_forest::MDDForestBool`) over the same domain
is created automatically and stored as a field, enabling comparison operator
overloads (`==`, `<`, etc.) without requiring a separate forest argument.
"""
mutable struct MDDForestInt <: AbstractForest
    ptr::Ptr{Cvoid}
    domain::Domain
    bool_forest::MDDForestBool  # paired boolean forest (eagerly created)

    function MDDForestInt(domain::Domain; kind::Symbol = :mdd)
        k   = _kind_int(kind)
        ptr = _check_ptr(_ll_forest_create(domain.ptr, k, _RANGE_INTEGER))
        bf  = MDDForestBool(domain; kind = kind)
        f   = new(ptr, domain, bf)
        bf._int_forest = WeakRef(f)   # back-reference for scalar ifthenelse
        finalizer(f) do x
            if x.ptr != C_NULL
                _ll_forest_destroy(x.ptr)
                x.ptr = C_NULL
            end
        end
        f
    end
end

Base.show(io::IO, f::MDDForestInt) =
    print(io, "MDDForestInt(", f.ptr == C_NULL ? "destroyed" : string(f.ptr), ")")

# ------------------------------------------------------------------ #
# Edge                                                                 #
# ------------------------------------------------------------------ #

mutable struct Edge
    ptr::Ptr{Cvoid}
    forest::AbstractForest  # keep forest (and transitively domain) alive

    # Raw constructor: just stores fields, no finalizer.
    # Use _make_edge() or the public Edge(forest[, values]) constructors instead.
    Edge(ptr::Ptr{Cvoid}, forest::AbstractForest) = new(ptr, forest)
end

# Internal factory: wraps a raw C pointer and registers the finalizer.
function _make_edge(ptr::Ptr{Cvoid}, forest::AbstractForest)
    e = Edge(ptr, forest)
    finalizer(e) do x
        if x.ptr != C_NULL
            _ll_edge_destroy(x.ptr)
            x.ptr = C_NULL
        end
    end
    e
end

# Create an edge initialized to the empty set.
function Edge(forest::AbstractForest)
    ptr = _check_ptr(_ll_edge_create(forest.ptr))
    _make_edge(ptr, forest)
end

# Create an edge representing the single minterm given by values (boolean forest).
# values[i] is the assignment for variable i (1-indexed Julia convention).
function Edge(forest::AbstractForest, values::Vector{Int})
    isempty(values) && error("values must not be empty")
    vals = Cint.(values)
    ptr  = _check_ptr(_ll_edge_create_from_values(forest.ptr, vals))
    _make_edge(ptr, forest)
end

# Create a constant integer-valued edge: all variable assignments → value.
function Edge(forest::AbstractForest, value::Integer)
    ptr = _check_ptr(_ll_edge_create_constant_int(forest.ptr, Int64(value)))
    _make_edge(ptr, forest)
end

# Create a single-minterm integer edge: vars → value, 0 everywhere else.
# vars[i] is the assignment for variable i (1-indexed Julia convention).
function Edge(forest::AbstractForest, vars::Vector{Int}, value::Integer)
    isempty(vars) && error("vars must not be empty")
    vs  = Cint.(vars)
    ptr = _check_ptr(_ll_edge_create_from_minterm_int(forest.ptr, vs, Int64(value)))
    _make_edge(ptr, forest)
end

Base.show(io::IO, e::Edge) =
    print(io, "Edge(", e.ptr == C_NULL ? "destroyed" : string(e.ptr), ")")

# ------------------------------------------------------------------ #
# MDDSession — reference-style session object                          #
# ------------------------------------------------------------------ #

"""
    MDDSession

Session object for the reference-style MDD API.  Create with `mdd()`,
register variables with `defvar!`, then build projection edges with `var!`.
"""
mutable struct MDDSession
    _var_defs   ::Dict{Symbol, Tuple{Int, Vector{Int}}}  # name => (level, domain)
    _num_levels ::Int
    _domain     ::Union{Domain, Nothing}
    _int_forest ::Union{MDDForestInt, Nothing}
    _bool_forest::Union{MDDForestBool, Nothing}

    MDDSession() = new(Dict{Symbol,Tuple{Int,Vector{Int}}}(), 0, nothing, nothing, nothing)
end
