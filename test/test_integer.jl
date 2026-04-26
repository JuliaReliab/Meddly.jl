# Tests for integer-forest edge creation and pointwise arithmetic.

@testset "Integer forest — edge creation" begin
    dom = Domain([4, 4])   # 2 variables, each 0..3  (16 total minterms)
    f   = MDDForestInt(dom)

    # Constant edge: all minterms → 5
    c5 = @test_nowarn Edge(f, 5)
    @test c5.ptr != C_NULL
    # All 4×4 = 16 minterms are non-zero → cardinality = 16
    @test cardinality(c5) ≈ 16.0

    # Constant 0 edge should be "empty" (all-zero function)
    c0 = @test_nowarn Edge(f, 0)
    @test is_empty(c0)
    @test cardinality(c0) == 0.0

    # Single-minterm integer edge: (x1=1, x2=2) → 7, else 0
    e7 = @test_nowarn Edge(f, [1, 2], 7)
    @test e7.ptr != C_NULL
    # Exactly 1 non-zero minterm
    @test cardinality(e7) ≈ 1.0
end

@testset "Integer forest — arithmetic" begin
    dom = Domain([4, 4])
    f   = MDDForestInt(dom)

    # Two single-minterm edges at the same point
    ea = Edge(f, [1, 2], 5)   # (1,2) → 5
    eb = Edge(f, [1, 2], 3)   # (1,2) → 3

    e_sum  = @test_nowarn ea + eb     # (1,2) → 8
    e_diff = @test_nowarn ea - eb     # (1,2) → 2
    e_prod = @test_nowarn ea * eb     # (1,2) → 15
    e_mx   = @test_nowarn max(ea, eb) # (1,2) → 5
    e_mn   = @test_nowarn min(ea, eb) # (1,2) → 3

    # All results have exactly 1 non-zero minterm (the shared point)
    @test cardinality(e_sum)  ≈ 1.0
    @test cardinality(e_diff) ≈ 1.0
    @test cardinality(e_prod) ≈ 1.0
    @test cardinality(e_mx)   ≈ 1.0
    @test cardinality(e_mn)   ≈ 1.0

    # Subtracting a value from itself should give zero (empty function)
    e_zero = ea - ea
    @test is_empty(e_zero)
end
