@testset "session API" begin

    # basic 3-variable session — explicit compile! before var!
    b = mdd()
    defvar!(b, :x, 3, [0, 1])
    defvar!(b, :y, 2, [0, 1, 2])
    defvar!(b, :z, 1, [0, 1, 2])
    compile!(b)   # fix configuration; forests created here
    x = var!(b, :x)
    y = var!(b, :y)
    z = var!(b, :z)

    @test x isa Edge
    @test y isa Edge
    @test z isa Edge

    # projections: cardinality = number of minterms with non-zero value
    # x ∈ {0,1}, y ∈ {0,1,2}, z ∈ {0,1,2}: 18 total minterms
    # x-projection: value 1 at 9 minterms (x=1), value 0 at 9 (x=0)
    @test cardinality(x) == 9.0
    # y-projection: value != 0 at 12 minterms (y=1 or y=2)
    @test cardinality(y) == 12.0
    # z-projection: same
    @test cardinality(z) == 12.0

    # arithmetic
    f = 3 * x + y - 2 * z
    @test f isa Edge
    # f=0 at (x=0,y=0,z=0), (x=0,y=2,z=1), (x=1,y=1,z=2) → 3 zero minterms
    @test cardinality(f) == 15.0

    # scalar comparison → boolean edge
    result = f >= 0
    @test result isa Edge
    @test result.forest isa MDDForestBool
    @test cardinality(result) == 12.0   # 12 minterms where f >= 0

    lt2 = f < 2
    @test cardinality(lt2) == 12.0  # 12 minterms where f < 2

    # and / or / ! on boolean edges
    cond = and(result, lt2)    # 0 ≤ f < 2  →  6 minterms
    @test cardinality(cond) == 6.0

    neg = !cond
    @test cardinality(neg) == 12.0   # 18 - 6

    r2 = !and(f >= 0, f < 2)
    @test cardinality(r2) == 12.0

    or_result = or(f < 0, f >= 3)
    @test cardinality(or_result) == cardinality(!and(f >= 0, f < 3))

    # ifthenelse with integer arms
    g = ifthenelse(cond, 5, 10)
    @test g isa Edge
    @test g.forest isa MDDForestInt
    @test cardinality(g) == 18.0   # all 18 minterms have non-zero value

    # ifthenelse: edge arm + integer arm
    # cond true at 6 minterms (f=0 or f=1); f=0 at 3 of those → value 0 (no count)
    g2 = ifthenelse(cond, f, 0)
    @test cardinality(g2) == 3.0   # 3 minterms where cond=true AND f≠0 (i.e. f=1)

    # scalar == on integer edge
    eq0 = (x == 0)
    @test eq0.forest isa MDDForestBool
    @test cardinality(eq0) == 9.0

    # unary minus
    neg_x = -x
    @test cardinality(neg_x) == 9.0   # 9 minterms where x=1 → value -1

    # @match with integer arm values
    f2 = @match(
        x == 0        => 0,
        y == 0 && z == 0 => 0,
        y == 0 || z == 0 => 1,
        y == 2 || z == 2 => 3,
        _             => 2)
    @test f2 isa Edge
    @test cardinality(f2) == 8.0   # 8 non-zero minterms (x=1 only)

    # compile! is idempotent
    compile!(b)
    @test b._int_forest isa MDDForestInt

    # defvar! after compile! raises an error
    b2 = mdd()
    defvar!(b2, :a, 1, [0, 1])
    compile!(b2)
    @test_throws ErrorException defvar!(b2, :b, 2, [0, 1])

    # var! auto-compiles if compile! was not called
    b2b = mdd()
    defvar!(b2b, :a, 1, [0, 1])
    _ = var!(b2b, :a)
    @test b2b._int_forest isa MDDForestInt

    # var! on undefined name raises error
    b3 = mdd()
    defvar!(b3, :q, 1, [0, 1])
    _ = var!(b3, :q)
    @test_throws ErrorException var!(b3, :undefined)

end
