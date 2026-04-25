module Meddly

export initialize, cleanup
export Domain, Forest, Edge
export cardinality, is_empty
export eq, neq, lt, lte, gt, gte
export land, lor, lnot
export copy_edge, ifthenelse
export todot

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
