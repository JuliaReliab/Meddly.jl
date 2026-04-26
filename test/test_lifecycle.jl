# Tests for library lifecycle, Domain, and Forest construction.

@testset "initialize / cleanup" begin
    @test_nowarn initialize()
    @test_nowarn cleanup()
    # Re-initialize so subsequent test files can use Meddly objects.
    initialize()
end

@testset "Domain" begin
    dom = @test_nowarn Domain([2, 2, 2])   # 3 binary variables
    @test dom.ptr != C_NULL
end

@testset "Forest" begin
    dom = Domain([2, 2, 2])
    f   = @test_nowarn MDDForestBool(dom)
    @test f.ptr != C_NULL

    f_int = @test_nowarn MDDForestInt(dom; kind = :mdd)
    @test f_int.ptr != C_NULL

    @test_throws ErrorException MDDForestBool(dom; kind = :bad)
    @test_throws ErrorException MDDForestInt(dom; kind = :bad)
end
