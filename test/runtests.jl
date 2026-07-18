using Test

# The shim ships prebuilt as libmeddly_c_jll; LIBMEDDLY_C_PATH overrides it for
# development against a locally built shim.
import libmeddly_c_jll
const libmeddly_c_path = get(ENV, "LIBMEDDLY_C_PATH", libmeddly_c_jll.libmeddly_c)
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
    @warn "libmeddly_c not found at '$(_lib_path)'."
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
    include("test_match.jl")
    include("test_session.jl")
    include("test_cleanup_safety.jl")   # LAST: toggles cleanup()/initialize()

    cleanup()

end # @testset

end # if _lib_available
