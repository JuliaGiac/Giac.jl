# Run the OpenMath extension's tests, which the `test` target cannot hold:
# OpenMath.jl is not registered. This builds a temporary project with Giac (this
# checkout), OpenMath.jl at a pinned commit, Symbolics, SHA and Test, and runs
# test_openmath_ext.jl in it.
#
#     julia test/run_openmath_tests.jl
#
# The CI-OpenMath workflow does the same with coverage.

using Pkg

# OpenMath.jl's commit these tests were written against
const OPENMATH_URL = "https://github.com/s-celles/OpenMath.jl"
const OPENMATH_REV = "ae4f3608e330221ed8af1ee8b24d98539de4d09d"

Pkg.activate(; temp = true)
Pkg.develop(PackageSpec(path = dirname(@__DIR__)))
Pkg.add(PackageSpec(url = OPENMATH_URL, rev = OPENMATH_REV))
Pkg.add(["Symbolics", "SHA", "Downloads", "Test"])
include(joinpath(@__DIR__, "test_openmath_ext.jl"))
