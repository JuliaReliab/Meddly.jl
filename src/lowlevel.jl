# Low-level ccall bindings to libmeddly_c.
# libmeddly_c_path is defined in src/Meddly.jl before this file is included:
#   - from deps/deps.jl (written by deps/build.jl), or
#   - from LIBMEDDLY_C_PATH env var / bare name as fallback.

const libmeddly_c = libmeddly_c_path

# ------------------------------------------------------------------ #
# Error helpers                                                        #
# ------------------------------------------------------------------ #

const _C_OK = Cint(0)

function _last_error_msg()::String
    ptr = ccall((:meddly_last_error, libmeddly_c), Cstring, ())
    ptr == C_NULL ? "(no message)" : unsafe_string(ptr)
end

function _check(ret::Cint)
    ret == _C_OK && return
    error("MEDDLY error: $(_last_error_msg())")
end

function _check_ptr(p::Ptr{Cvoid})
    p != C_NULL && return p
    error("MEDDLY error: $(_last_error_msg())")
end

# ------------------------------------------------------------------ #
# Library lifecycle                                                    #
# ------------------------------------------------------------------ #

_ll_initialize() = ccall((:meddly_initialize, libmeddly_c), Cint, ())
_ll_cleanup()    = ccall((:meddly_cleanup,    libmeddly_c), Cint, ())

# ------------------------------------------------------------------ #
# Domain                                                               #
# ------------------------------------------------------------------ #

function _ll_domain_create(sizes::Vector{Cint})
    ccall((:meddly_domain_create, libmeddly_c), Ptr{Cvoid},
          (Ptr{Cint}, Cint), sizes, length(sizes))
end

_ll_domain_destroy(p::Ptr{Cvoid}) =
    ccall((:meddly_domain_destroy, libmeddly_c), Cint, (Ptr{Cvoid},), p)

# ------------------------------------------------------------------ #
# Forest                                                               #
# ------------------------------------------------------------------ #

_ll_forest_create(dom::Ptr{Cvoid}, kind::Cint, range::Cint) =
    ccall((:meddly_forest_create, libmeddly_c), Ptr{Cvoid},
          (Ptr{Cvoid}, Cint, Cint), dom, kind, range)

_ll_forest_create_ev(dom::Ptr{Cvoid}, kind::Cint, range::Cint, ev::Cint) =
    ccall((:meddly_forest_create_ev, libmeddly_c), Ptr{Cvoid},
          (Ptr{Cvoid}, Cint, Cint, Cint), dom, kind, range, ev)

_ll_forest_destroy(p::Ptr{Cvoid}) =
    ccall((:meddly_forest_destroy, libmeddly_c), Cint, (Ptr{Cvoid},), p)

# ------------------------------------------------------------------ #
# Edge                                                                 #
# ------------------------------------------------------------------ #

_ll_edge_create(forest::Ptr{Cvoid}) =
    ccall((:meddly_edge_create, libmeddly_c), Ptr{Cvoid}, (Ptr{Cvoid},), forest)

function _ll_edge_create_from_values(forest::Ptr{Cvoid}, values::Vector{Cint})
    ccall((:meddly_edge_create_from_values, libmeddly_c), Ptr{Cvoid},
          (Ptr{Cvoid}, Ptr{Cint}, Cint), forest, values, length(values))
end

_ll_edge_create_constant_int(forest::Ptr{Cvoid}, value::Int64) =
    ccall((:meddly_edge_create_constant_int, libmeddly_c), Ptr{Cvoid},
          (Ptr{Cvoid}, Clong), forest, value)

function _ll_edge_create_from_minterm_int(forest::Ptr{Cvoid}, vars::Vector{Cint}, value::Int64)
    ccall((:meddly_edge_create_from_minterm_int, libmeddly_c), Ptr{Cvoid},
          (Ptr{Cvoid}, Ptr{Cint}, Clong, Cint), forest, vars, value, length(vars))
end

_ll_edge_destroy(p::Ptr{Cvoid}) =
    ccall((:meddly_edge_destroy, libmeddly_c), Cint, (Ptr{Cvoid},), p)

# ------------------------------------------------------------------ #
# Generic binary apply                                                 #
# ------------------------------------------------------------------ #

function _ll_edge_apply_binary(op_id::Cint, a::Ptr{Cvoid}, b::Ptr{Cvoid})
    result = Ref{Ptr{Cvoid}}(C_NULL)
    ret = ccall((:meddly_edge_apply_binary, libmeddly_c), Cint,
                (Cint, Ptr{Cvoid}, Ptr{Cvoid}, Ref{Ptr{Cvoid}}), op_id, a, b, result)
    ret, result[]
end

function _ll_edge_apply_binary_rf(op_id::Cint, a::Ptr{Cvoid}, b::Ptr{Cvoid},
                                   rf::Ptr{Cvoid})
    result = Ref{Ptr{Cvoid}}(C_NULL)
    ret = ccall((:meddly_edge_apply_binary_rf, libmeddly_c), Cint,
                (Cint, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ref{Ptr{Cvoid}}),
                op_id, a, b, rf, result)
    ret, result[]
end

function _ll_edge_copy(src::Ptr{Cvoid}, dst_forest::Ptr{Cvoid})
    result = Ref{Ptr{Cvoid}}(C_NULL)
    ret = ccall((:meddly_edge_copy, libmeddly_c), Cint,
                (Ptr{Cvoid}, Ptr{Cvoid}, Ref{Ptr{Cvoid}}), src, dst_forest, result)
    ret, result[]
end

function _ll_edge_ifthenelse(cond::Ptr{Cvoid}, then_e::Ptr{Cvoid}, else_e::Ptr{Cvoid})
    result = Ref{Ptr{Cvoid}}(C_NULL)
    ret = ccall((:meddly_edge_ifthenelse, libmeddly_c), Cint,
                (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ref{Ptr{Cvoid}}),
                cond, then_e, else_e, result)
    ret, result[]
end

# ------------------------------------------------------------------ #
# Set operations                                                       #
# ------------------------------------------------------------------ #

function _ll_edge_union(a::Ptr{Cvoid}, b::Ptr{Cvoid})
    result = Ref{Ptr{Cvoid}}(C_NULL)
    ret = ccall((:meddly_edge_union, libmeddly_c), Cint,
                (Ptr{Cvoid}, Ptr{Cvoid}, Ref{Ptr{Cvoid}}), a, b, result)
    ret, result[]
end

function _ll_edge_intersection(a::Ptr{Cvoid}, b::Ptr{Cvoid})
    result = Ref{Ptr{Cvoid}}(C_NULL)
    ret = ccall((:meddly_edge_intersection, libmeddly_c), Cint,
                (Ptr{Cvoid}, Ptr{Cvoid}, Ref{Ptr{Cvoid}}), a, b, result)
    ret, result[]
end

function _ll_edge_difference(a::Ptr{Cvoid}, b::Ptr{Cvoid})
    result = Ref{Ptr{Cvoid}}(C_NULL)
    ret = ccall((:meddly_edge_difference, libmeddly_c), Cint,
                (Ptr{Cvoid}, Ptr{Cvoid}, Ref{Ptr{Cvoid}}), a, b, result)
    ret, result[]
end

# ------------------------------------------------------------------ #
# Queries                                                              #
# ------------------------------------------------------------------ #

function _ll_edge_complement(a::Ptr{Cvoid})
    result = Ref{Ptr{Cvoid}}(C_NULL)
    ret = ccall((:meddly_edge_complement, libmeddly_c), Cint,
                (Ptr{Cvoid}, Ref{Ptr{Cvoid}}), a, result)
    ret, result[]
end


_ll_edge_cardinality(p::Ptr{Cvoid}) =
    ccall((:meddly_edge_cardinality, libmeddly_c), Cdouble, (Ptr{Cvoid},), p)

_ll_edge_is_empty(p::Ptr{Cvoid}) =
    ccall((:meddly_edge_is_empty, libmeddly_c), Cint, (Ptr{Cvoid},), p) != Cint(0)

# ------------------------------------------------------------------ #
# Traversal / node inspection                                          #
# ------------------------------------------------------------------ #

_ll_edge_get_node(e::Ptr{Cvoid}) =
    ccall((:meddly_edge_get_node, libmeddly_c), Cint, (Ptr{Cvoid},), e)

_ll_forest_num_vars(f::Ptr{Cvoid}) =
    ccall((:meddly_forest_num_vars, libmeddly_c), Cint, (Ptr{Cvoid},), f)

_ll_forest_level_size(f::Ptr{Cvoid}, level::Cint) =
    ccall((:meddly_forest_level_size, libmeddly_c), Cint,
          (Ptr{Cvoid}, Cint), f, level)

_ll_node_is_terminal(node::Cint) =
    ccall((:meddly_node_is_terminal, libmeddly_c), Cint, (Cint,), node) != Cint(0)

_ll_node_level(f::Ptr{Cvoid}, node::Cint) =
    ccall((:meddly_node_level, libmeddly_c), Cint, (Ptr{Cvoid}, Cint), f, node)

_ll_node_bool_value(f::Ptr{Cvoid}, node::Cint) =
    ccall((:meddly_node_bool_value, libmeddly_c), Cint,
          (Ptr{Cvoid}, Cint), f, node) != Cint(0)

_ll_node_int_value(f::Ptr{Cvoid}, node::Cint) =
    Int(ccall((:meddly_node_int_value, libmeddly_c), Clonglong,
              (Ptr{Cvoid}, Cint), f, node))

function _ll_node_get_children(f::Ptr{Cvoid}, node::Cint, out::Vector{Cint})
    ccall((:meddly_node_get_children, libmeddly_c), Cint,
          (Ptr{Cvoid}, Cint, Ptr{Cint}, Cint), f, node, out, length(out))
end
