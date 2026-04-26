# Tests for logical operators (land/lor/lnot) and ifthenelse.

@testset "land / lor / lnot" begin
    dom    = Domain([4, 4])
    bool_f = MDDForestBool(dom)
    int_f  = MDDForestInt(dom)

    ea = Edge(int_f, [1, 2], 5)
    eb = Edge(int_f, [1, 2], 3)
    ec = Edge(int_f, [2, 3], 7)

    # gt(ea,eb) is true at (1,2);  gt(ec,ea) is true at (2,3)
    c1 = gt(ea, eb, bool_f)   # true at (1,2)
    c2 = gt(ec, ea, bool_f)   # true at (2,3)

    # land: AND → must be true at BOTH points simultaneously
    c_and = @test_nowarn land(c1, c2)
    @test is_empty(c_and)   # no minterm satisfies both

    # lor: OR → true at (1,2) or (2,3)
    c_or = @test_nowarn lor(c1, c2)
    @test cardinality(c_or) ≈ 2.0

    # lnot: complement of c1 (true at (1,2)) → false at (1,2), true at 15 others
    c_not = @test_nowarn lnot(c1)
    @test cardinality(c_not) ≈ 15.0
end

@testset "ifthenelse" begin
    dom    = Domain([4, 4])
    bool_f = MDDForestBool(dom)
    int_f  = MDDForestInt(dom)

    # ea = 5 at (1,2);  eb = 3 at (1,2);  ec = 7 at (2,3)
    ea = Edge(int_f, [1, 2], 5)
    eb = Edge(int_f, [1, 2], 3)
    ec = Edge(int_f, [2, 3], 7)

    # cond: ea > eb  →  true at (1,2) only
    cond_bool = gt(ea, eb, bool_f)
    cond_int  = copy_edge(cond_bool, int_f)   # 1 at (1,2), 0 elsewhere

    # ifthenelse(cond, ea, ec):
    #   at (1,2):  cond=1 → result = 1*5 + 0*0 = 5     (ec is 0 at (1,2))
    #   at (2,3):  cond=0 → result = 0*0 + 1*7 = 7     (ea is 0 at (2,3))
    #   elsewhere: cond=0 → result = 0*0 + 1*0 = 0
    result = @test_nowarn ifthenelse(cond_int, ea, ec)
    @test result.ptr != C_NULL
    # Two non-zero minterms: (1,2)→5 and (2,3)→7
    @test cardinality(result) ≈ 2.0

    # Degenerate case: condition always false → result equals else branch
    always_false = copy_edge(lt(ea, eb, bool_f), int_f)  # 0 everywhere
    result2 = ifthenelse(always_false, ea, ec)
    @test cardinality(result2) ≈ cardinality(ec)
end

@testset "ifthenelse with boolean condition (auto-convert)" begin
    dom    = Domain([4, 4])
    bool_f = MDDForestBool(dom)
    int_f  = MDDForestInt(dom)

    ea = Edge(int_f, [1, 2], 5)
    eb = Edge(int_f, [1, 2], 3)
    ec = Edge(int_f, [2, 3], 7)

    # Boolean condition — no manual copy_edge needed
    cond = gt(ea, eb, bool_f)   # true at (1,2), false elsewhere
    result = @test_nowarn ifthenelse(cond, ea, ec)
    @test result.ptr != C_NULL
    # (1,2): cond=1 → ea=5 (non-zero)
    # (2,3): cond=0 → ec=7 (non-zero)
    # elsewhere: both ea=0 and ec=0
    @test cardinality(result) ≈ 2.0

    # Compound condition with land
    c1 = gt(ea, eb, bool_f)              # true at (1,2)
    c2 = lnot(gt(ec, ea, bool_f))        # true everywhere except (2,3)
    cond2 = land(c1, c2)                 # true at (1,2) only
    result2 = @test_nowarn ifthenelse(cond2, ea, ec)
    @test cardinality(result2) ≈ 2.0
end
