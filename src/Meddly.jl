module Meddly

export initialize, cleanup
export Domain, AbstractForest, MDDForestBool, MDDForestInt, Edge
export cardinality, is_empty
export eq, neq, lt, lte, gt, gte
export land, lor, lnot
export and, or
export bool_forest, copy_edge, ifthenelse
export todot
export NodeHandle
export root_node, num_vars, level_size
export is_terminal, node_level, terminal_value, node_children
export @match
export MDDSession, mdd, defvar!, compile!, var!

# Load the library path written by deps/build.jl.
# Falls back to LIBMEDDLY_C_PATH env var (or bare name) when the package
# has not been built yet — useful during development / CI.
const _depsjl = joinpath(@__DIR__, "..", "deps", "deps.jl")
if isfile(_depsjl)
    include(_depsjl)          # defines: const libmeddly_c_path = "..."
else
    const libmeddly_c_path =
        get(ENV, "LIBMEDDLY_C_PATH", "libmeddly_c")
end

include("lowlevel.jl")
include("types.jl")
include("highlevel.jl")

end # module
