# Tests for DOT output and GC / finalizer safety.

@testset "todot" begin
    dom = Domain([2, 2, 2])
    f   = Forest(dom)
    e   = Edge(f, [0, 1, 0])
    dot = @test_nowarn todot(e)
    @test dot isa String
    @test occursin("digraph", dot)
end

@testset "GC / finalizer safety" begin
    # Create objects and let them go out of scope; GC should not crash.
    dom = Domain([3, 3])
    f   = Forest(dom)
    for _ in 1:20
        e = Edge(f, [1, 2])
    end
    GC.gc(true)   # force full GC; must not segfault
    @test true
end
