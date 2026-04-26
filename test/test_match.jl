# Tests for the @match macro.

@testset "@match two arms" begin
    dom    = Domain([4, 4])
    bool_f = MDDForestBool(dom)
    int_f  = MDDForestInt(dom)

    ea = Edge(int_f, [1, 2], 5)
    eb = Edge(int_f, [1, 2], 3)
    ec = Edge(int_f, [2, 3], 7)

    cond = gt(ea, eb, bool_f)   # true at (1,2)

    # @match(cond => ea, _ => ec)  ==  ifthenelse(cond, ea, ec)
    result_match = @test_nowarn @match(cond => ea, _ => ec)
    result_ite   = ifthenelse(cond, ea, ec)

    @test result_match.ptr != C_NULL
    # same as ifthenelse: (1,2)→5, (2,3)→7  →  cardinality 2
    @test cardinality(result_match) ≈ 2.0
    @test cardinality(result_match) ≈ cardinality(result_ite)
end

@testset "@match three arms" begin
    dom    = Domain([4, 4])
    bool_f = MDDForestBool(dom)
    int_f  = MDDForestInt(dom)

    ea = Edge(int_f, [1, 2], 5)
    eb = Edge(int_f, [1, 2], 3)
    ec = Edge(int_f, [2, 3], 7)
    ed = Edge(int_f, [3, 1], 2)

    cond1 = gt(ea, eb, bool_f)   # true at (1,2)
    cond2 = gt(ec, ea, bool_f)   # true at (2,3)

    # cond1 → ea, cond2 → ec, _ → ed
    # (1,2): cond1=T → 5;  (2,3): cond2=T → 7;  (3,1): neither → 2
    result = @test_nowarn @match(
        cond1 => ea,
        cond2 => ec,
        _ => ed
    )
    @test result.ptr != C_NULL
    @test cardinality(result) ≈ 3.0
end

@testset "@match && condition" begin
    dom    = Domain([4, 4])
    bool_f = MDDForestBool(dom)
    int_f  = MDDForestInt(dom)

    ea = Edge(int_f, [1, 2], 5)
    eb = Edge(int_f, [1, 2], 3)
    ec = Edge(int_f, [2, 3], 7)
    ed = Edge(int_f, [1, 2], 10)

    cond1 = gt(ea, eb, bool_f)           # true at (1,2)
    cond2 = lnot(gt(ec, ea, bool_f))     # false at (2,3), true elsewhere

    # && rewrites to land — true only at (1,2)
    # (1,2): land=T → ed=10;  (2,3): land=F → ec=7
    result = @test_nowarn @match(
        cond1 && cond2 => ed,
        _ => ec
    )
    @test result.ptr != C_NULL
    @test cardinality(result) ≈ 2.0

    # Verify equivalence with explicit land
    expected = ifthenelse(land(cond1, cond2), ed, ec)
    @test cardinality(result) ≈ cardinality(expected)
end

@testset "@match || condition" begin
    dom    = Domain([4, 4])
    bool_f = MDDForestBool(dom)
    int_f  = MDDForestInt(dom)

    ea = Edge(int_f, [1, 2], 5)
    eb = Edge(int_f, [1, 2], 3)
    ec = Edge(int_f, [2, 3], 7)
    ez = Edge(int_f)   # zero edge

    cond1 = gt(ea, eb, bool_f)   # true at (1,2)
    cond2 = gt(ec, ea, bool_f)   # true at (2,3)

    # || rewrites to lor — true at (1,2) or (2,3)
    # (1,2): lor=T → ea=5 (non-zero);  (2,3): lor=T → ea=0;  elsewhere: F → 0
    result = @test_nowarn @match(
        cond1 || cond2 => ea,
        _ => ez
    )
    @test result.ptr != C_NULL
    @test cardinality(result) ≈ 1.0   # only (1,2) is non-zero

    # Verify equivalence with explicit lor
    expected = ifthenelse(lor(cond1, cond2), ea, ez)
    @test cardinality(result) ≈ cardinality(expected)
end

@testset "@match with comparison operator overloads" begin
    dom   = Domain([4, 4])
    int_f = MDDForestInt(dom)

    ea = Edge(int_f, [1, 2], 5)
    eb = Edge(int_f, [1, 2], 3)
    ec = Edge(int_f, [2, 3], 7)
    ed = Edge(int_f, [3, 1], 2)

    # No explicit bool_f needed — operator overloads infer it
    result = @test_nowarn @match(
        ea > eb => ea,
        ec > ea => ec,
        _ => ed
    )
    @test result.ptr != C_NULL
    # (1,2)→ea=5, (2,3)→ec=7, (3,1)→ed=2
    @test cardinality(result) ≈ 3.0
end

@testset "@match nested && and ||" begin
    dom    = Domain([4, 4, 4])
    bool_f = MDDForestBool(dom)
    int_f  = MDDForestInt(dom)

    ea = Edge(int_f, [1, 2, 1], 3)
    eb = Edge(int_f, [1, 2, 1], 1)
    ec = Edge(int_f, [2, 3, 2], 5)
    ed = Edge(int_f, [2, 3, 2], 2)
    ez = Edge(int_f)

    c1 = gt(ea, eb, bool_f)   # true at (1,2,1)
    c2 = gt(ec, ed, bool_f)   # true at (2,3,2)
    c3 = lnot(c1)             # false at (1,2,1), true elsewhere

    # (c1 || c2) && c3: at (1,2,1) lor=T but c3=F → false
    #                   at (2,3,2) lor=T and c3=T → true
    result = @test_nowarn @match(
        (c1 || c2) && c3 => ec,
        _ => ez
    )
    @test result.ptr != C_NULL
    @test cardinality(result) ≈ 1.0   # only (2,3,2)→5
end
