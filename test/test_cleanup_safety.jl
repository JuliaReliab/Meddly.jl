# Finalizer safety across cleanup() / initialize() boundaries.
#
# These deliberately call cleanup() and initialize(), so this file must run
# LAST in the suite (runtests.jl includes it right before its final cleanup()).
# The generation guard (src/highlevel.jl / src/types.jl) must make finalizers
# that run after a cleanup — or after a cleanup()/initialize() cycle that
# invalidated their pointers — skip the C++ destroy instead of crashing.

@testset "GC safety: finalizers after cleanup()" begin
    dom = Domain([3, 3])
    f   = MDDForestBool(dom)
    e   = Edge(f, [1, 2])
    cleanup()                       # tears down all MEDDLY objects globally
    dom = nothing; f = nothing; e = nothing
    GC.gc(true)                     # finalizers run with library down → must skip
    @test true
    initialize()                    # restore for the next testset
end

@testset "GC safety: stale objects after cleanup()/initialize()" begin
    dom = Domain([3, 3])
    f   = MDDForestInt(dom)
    e   = Edge(f, [1, 2], 5)
    cleanup()
    initialize()                    # new session → generation bumped
    # Old objects now belong to a stale generation.  Collecting them must not
    # touch the new session's MEDDLY state.
    dom = nothing; f = nothing; e = nothing
    GC.gc(true)
    @test true
    # Library is initialized here; runtests.jl's trailing cleanup() closes it.
end
