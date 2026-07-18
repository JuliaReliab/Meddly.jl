module Meddly

export initialize, cleanup, is_initialized
export Domain, AbstractForest, MDDForestBool, MDDForestInt, MDDForestBoolMxD, Edge
export cardinality, is_empty
export eq, neq, lt, lte, gt, gte
export land, lor, lnot
export and, or
export bool_forest, copy_edge, ifthenelse
export todot
export NodeHandle
export root_node, num_vars, level_size
export is_terminal, node_level, terminal_value, node_children, create_node, edge_from_node
export current_num_nodes, peak_num_nodes, reset_peak_num_nodes!
export @match
export MDDSession, mdd, defvar!, compile!, var!
export mxd_singleton, post_image, reachable_bfs

# The C ABI shim (with MEDDLY statically linked) is shipped prebuilt as
# libmeddly_c_jll — no source build needed.  LIBMEDDLY_C_PATH overrides it for
# development against a locally built shim.
import libmeddly_c_jll
const libmeddly_c_path = get(ENV, "LIBMEDDLY_C_PATH", libmeddly_c_jll.libmeddly_c)

include("lowlevel.jl")
include("types.jl")
include("highlevel.jl")

end # module
