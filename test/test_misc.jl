# Tests for DOT output and GC / finalizer safety.

@testset "todot" begin
    dom = Domain([2, 2, 2])
    f   = MDDForestBool(dom)
    e   = Edge(f, [0, 1, 0])
    dot = @test_nowarn todot(e)
    @test dot isa String
    @test occursin("digraph", dot)
end

@testset "GC / finalizer safety" begin
    # Create objects and let them go out of scope; GC should not crash.
    dom = Domain([3, 3])
    f   = MDDForestBool(dom)
    for _ in 1:20
        e = Edge(f, [1, 2])
    end
    GC.gc(true)   # force full GC; must not segfault
    @test true
end

@testset "GC safety: whole graph collected together" begin
    # domain + forests + edges all become unreachable at once, so the domain
    # and forest finalizers race.  Before the ordering guard this segfaulted:
    # ~domain deletes the forests, then the forest finalizer double-freed them.
    # MDDForestInt creates two forests (int + paired bool) on one domain.
    for _ in 1:10
        let dom = Domain([3, 3, 3]), f = MDDForestInt(dom)
            e = Edge(f, [0, 1, 2], 1) + Edge(f, [1, 1, 2], 2)
            _ = (e > Edge(f, 1))
        end
        GC.gc(true)
    end
    @test true   # reached here without a segfault
end
