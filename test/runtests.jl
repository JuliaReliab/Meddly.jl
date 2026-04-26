using Test

# Resolve library path: prefer deps/deps.jl (written by Pkg.build),
# then LIBMEDDLY_C_PATH env var, then bare name as last resort.
const _depsjl = joinpath(@__DIR__, "..", "deps", "deps.jl")
if isfile(_depsjl)
    include(_depsjl)          # defines: const libmeddly_c_path = "..."
else
    const libmeddly_c_path = get(ENV, "LIBMEDDLY_C_PATH", "libmeddly_c")
end
const _lib_path = libmeddly_c_path
const _lib_available = let
    try
        import Libdl
        h = Libdl.dlopen(_lib_path; throw_error = false)
        h !== nothing
    catch
        false
    end
end

if !_lib_available
    @warn "libmeddly_c not found at '$(_lib_path)'. " *
          "Run Pkg.build(\"Meddly\") or build c/Makefile, then re-run the tests."
    @test_skip "libmeddly_c not available"
else

using Meddly

@testset "Meddly.jl" begin

    include("test_lifecycle.jl")
    include("test_boolean.jl")
    include("test_integer.jl")
    include("test_comparison.jl")
    include("test_ifthenelse.jl")
    include("test_misc.jl")
    include("test_traverse.jl")

    cleanup()

end # @testset

end # if _lib_available
