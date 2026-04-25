# Julia types that own MEDDLY C++ objects via Ptr{Cvoid}.
# Each public constructor calls the corresponding C create function and
# registers a finalizer.  Each child struct holds a reference to its
# parent (Edge → Forest → Domain) to prevent premature GC.

# ------------------------------------------------------------------ #
# Domain                                                               #
# ------------------------------------------------------------------ #

mutable struct Domain
    ptr::Ptr{Cvoid}

    function Domain(level_sizes::Vector{Int})
        isempty(level_sizes) && error("level_sizes must not be empty")
        sizes = Cint.(level_sizes)
        ptr = _check_ptr(_ll_domain_create(sizes))
        d = new(ptr)
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
# Forest                                                               #
# ------------------------------------------------------------------ #

mutable struct Forest
    ptr::Ptr{Cvoid}
    domain::Domain   # keep domain alive as long as forest is alive
    range::Symbol    # :boolean or :integer

    function Forest(domain::Domain;
                    kind::Symbol  = :mdd,
                    range::Symbol = :boolean)
        kind_int = if kind == :mdd
            _FOREST_MDD
        elseif kind == :mxd
            _FOREST_MXD
        else
            error("Unknown forest kind :$kind  (expected :mdd or :mxd)")
        end

        range_int = if range == :boolean
            _RANGE_BOOLEAN
        elseif range == :integer
            _RANGE_INTEGER
        else
            error("Unknown forest range :$range  (expected :boolean or :integer)")
        end

        ptr = _check_ptr(_ll_forest_create(domain.ptr, kind_int, range_int))
        f = new(ptr, domain, range)
        finalizer(f) do x
            if x.ptr != C_NULL
                _ll_forest_destroy(x.ptr)
                x.ptr = C_NULL
            end
        end
        f
    end
end

Base.show(io::IO, f::Forest) =
    print(io, "Forest(", f.ptr == C_NULL ? "destroyed" : string(f.ptr), ")")

# ------------------------------------------------------------------ #
# Edge                                                                 #
# ------------------------------------------------------------------ #

mutable struct Edge
    ptr::Ptr{Cvoid}
    forest::Forest   # keep forest (and transitively domain) alive

    # Raw constructor: just stores fields, no finalizer.
    # Use _make_edge() or the public Edge(forest[, values]) constructors instead.
    Edge(ptr::Ptr{Cvoid}, forest::Forest) = new(ptr, forest)
end

# Internal factory: wraps a raw C pointer and registers the finalizer.
function _make_edge(ptr::Ptr{Cvoid}, forest::Forest)
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
function Edge(forest::Forest)
    ptr = _check_ptr(_ll_edge_create(forest.ptr))
    _make_edge(ptr, forest)
end

# Create an edge representing the single minterm given by values (boolean forest).
# values[i] is the assignment for variable i (1-indexed Julia convention).
function Edge(forest::Forest, values::Vector{Int})
    isempty(values) && error("values must not be empty")
    vals = Cint.(values)
    ptr  = _check_ptr(_ll_edge_create_from_values(forest.ptr, vals))
    _make_edge(ptr, forest)
end

# Create a constant integer-valued edge: all variable assignments → value.
function Edge(forest::Forest, value::Integer)
    ptr = _check_ptr(_ll_edge_create_constant_int(forest.ptr, Int64(value)))
    _make_edge(ptr, forest)
end

# Create a single-minterm integer edge: vars → value, 0 everywhere else.
# vars[i] is the assignment for variable i (1-indexed Julia convention).
function Edge(forest::Forest, vars::Vector{Int}, value::Integer)
    isempty(vars) && error("vars must not be empty")
    vs  = Cint.(vars)
    ptr = _check_ptr(_ll_edge_create_from_minterm_int(forest.ptr, vs, Int64(value)))
    _make_edge(ptr, forest)
end

Base.show(io::IO, e::Edge) =
    print(io, "Edge(", e.ptr == C_NULL ? "destroyed" : string(e.ptr), ")")
