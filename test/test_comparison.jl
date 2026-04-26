# Tests for pointwise comparison operators and cross-forest copy.

@testset "Comparison operators" begin
    dom    = Domain([4, 4])
    bool_f = MDDForestBool(dom)
    int_f  = MDDForestInt(dom)

    ea = Edge(int_f, [1, 2], 5)   # (1,2) → 5
    eb = Edge(int_f, [1, 2], 3)   # (1,2) → 3

    # Note: single-minterm edges are 0 at all other points.
    # Domain is [4,4] → 16 total minterms.
    # Comparisons operate on total functions, so the "background" 0-values matter.

    # gt: 5 > 3 at (1,2) → true; 0 > 0 elsewhere → false.  Cardinality = 1.
    c_gt = @test_nowarn gt(ea, eb, bool_f)
    @test c_gt.ptr != C_NULL
    @test !is_empty(c_gt)
    @test cardinality(c_gt) ≈ 1.0

    # lt: 5 < 3 → false; 0 < 0 → false.  Everywhere false → empty.
    c_lt = @test_nowarn lt(ea, eb, bool_f)
    @test is_empty(c_lt)
    @test cardinality(c_lt) == 0.0

    # eq: 5 == 3 → false at (1,2); 0 == 0 → true at the other 15 minterms.
    c_eq = @test_nowarn eq(ea, eb, bool_f)
    @test cardinality(c_eq) ≈ 15.0

    # neq: 5 != 3 → true at (1,2); 0 != 0 → false elsewhere.  Cardinality = 1.
    c_neq = @test_nowarn neq(ea, eb, bool_f)
    @test cardinality(c_neq) ≈ 1.0

    # gte: 5 >= 3 → true at (1,2); 0 >= 0 → true at 15 others.  Cardinality = 16.
    c_gte = @test_nowarn gte(ea, eb, bool_f)
    @test cardinality(c_gte) ≈ 16.0

    # lte: 5 <= 3 → false at (1,2); 0 <= 0 → true at 15 others.  Cardinality = 15.
    c_lte = @test_nowarn lte(ea, eb, bool_f)
    @test cardinality(c_lte) ≈ 15.0
end

@testset "Comparison operator overloads (no explicit bool_f)" begin
    dom   = Domain([4, 4])
    int_f = MDDForestInt(dom)

    ea = Edge(int_f, [1, 2], 5)
    eb = Edge(int_f, [1, 2], 3)

    # Boolean forest is created lazily; result matches the explicit version
    bool_f = MDDForestBool(dom)
    @test cardinality(ea >  eb)  ≈ cardinality(gt(ea,  eb, bool_f))
    @test cardinality(ea <  eb)  ≈ cardinality(lt(ea,  eb, bool_f))
    @test cardinality(ea == eb)  ≈ cardinality(eq(ea,  eb, bool_f))
    @test cardinality(ea != eb)  ≈ cardinality(neq(ea, eb, bool_f))
    @test cardinality(ea >= eb)  ≈ cardinality(gte(ea, eb, bool_f))
    @test cardinality(ea <= eb)  ≈ cardinality(lte(ea, eb, bool_f))

    # Paired bool forest is eagerly created and is a MDDForestBool
    @test int_f.bool_forest isa MDDForestBool
    bf1 = int_f.bool_forest
    _ = (ea > eb)
    @test int_f.bool_forest === bf1   # same object every time
end

@testset "ifthenelse via C++ ternary (boolean condition)" begin
    dom   = Domain([4, 4])
    int_f = MDDForestInt(dom)

    ea = Edge(int_f, [1, 2], 5)
    eb = Edge(int_f, [1, 2], 3)
    ec = Edge(int_f, [2, 3], 7)

    # ea > eb is true at (1,2); ec > ea is true at (2,3)
    cond = ea > eb
    @test cond.forest isa MDDForestBool

    result = @test_nowarn ifthenelse(cond, ea, ec)
    @test result.ptr != C_NULL
    # (1,2)→5, (2,3)→7 → cardinality 2
    @test cardinality(result) ≈ 2.0

    # Chained conditions via land
    c2 = land(ea > eb, lnot(ec > ea))  # true only at (1,2)
    result2 = ifthenelse(c2, ea, ec)
    @test cardinality(result2) ≈ 2.0   # (1,2)→ea=5, (2,3)→ec=7
end

@testset "copy_edge (bool → int)" begin
    dom    = Domain([4, 4])
    bool_f = MDDForestBool(dom)
    int_f  = MDDForestInt(dom)

    ea = Edge(int_f, [1, 2], 5)
    eb = Edge(int_f, [1, 2], 3)

    c_bool = gt(ea, eb, bool_f)                     # true at (1,2)
    c_int  = @test_nowarn copy_edge(c_bool, int_f)  # 1 at (1,2), 0 elsewhere
    @test c_int.ptr != C_NULL
    # The 1-valued minterm contributes 1 to cardinality
    @test cardinality(c_int) ≈ 1.0
end
