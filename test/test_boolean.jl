# Tests for boolean-forest edges and set operations.

@testset "Edge — empty" begin
    dom = Domain([2, 2, 2])
    f   = MDDForestBool(dom)
    e   = @test_nowarn Edge(f)
    @test e.ptr != C_NULL
    @test is_empty(e)
    @test cardinality(e) == 0.0
end

@testset "Edge — from values" begin
    dom = Domain([2, 2, 2])
    f   = MDDForestBool(dom)
    # Single minterm: variable 1 = 0, variable 2 = 1, variable 3 = 0
    e = @test_nowarn Edge(f, [0, 1, 0])
    @test e.ptr != C_NULL
    @test !is_empty(e)
    @test cardinality(e) ≈ 1.0
end

@testset "union / intersection / difference" begin
    dom = Domain([2, 2, 2])
    f   = MDDForestBool(dom)

    e1 = Edge(f, [0, 0, 0])   # element {(0,0,0)}
    e2 = Edge(f, [1, 0, 0])   # element {(1,0,0)}
    e3 = Edge(f, [0, 0, 0])   # same as e1

    u = @test_nowarn e1 | e2
    @test cardinality(u) ≈ 2.0

    i = @test_nowarn e1 & e3
    @test cardinality(i) ≈ 1.0

    d = @test_nowarn setdiff(u, e2)
    @test cardinality(d) ≈ 1.0

    # Intersection with disjoint set should be empty.
    empty_e = e1 & e2
    @test is_empty(empty_e)
    @test cardinality(empty_e) == 0.0
end
