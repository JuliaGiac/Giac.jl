# Tests for the numeric constructors on `GiacExpr`.
#
# `convert(T, ::GiacExpr)` was defined for a handful of concrete targets and
# the matching constructors were never written, so `convert(Int64, g)` worked
# while `Int64(g)` raised MethodError. `convert` does not fall back to a
# constructor for a user type, so neither direction filled the other in.

using Giac.GenTypes

@testset "Numeric constructors" begin

    @testset "integers" begin
        g = giac_eval("42")
        @test Int(g) === 42
        @test Int64(g) === Int64(42)
        @test Int32(g) === Int32(42)
        @test UInt8(g) === UInt8(42)
        @test BigInt(g) == big(42)
        @test Integer(g) === 42
        @test convert(Integer, g) === 42
        @test convert(Int32, g) === Int32(42)
        @test convert(BigInt, g) == big(42)
        # agrees with the convert that already existed
        @test Int64(g) === convert(Int64, g)
    end

    @testset "a big integer stays big" begin
        g = giac_eval("2^200")
        @test Integer(g) isa BigInt
        @test Integer(g) == big(2)^200
        @test BigInt(g) == big(2)^200
        @test convert(Integer, g) == big(2)^200
        # ... and narrowing it is refused rather than wrapped
        @test_throws InexactError Int64(g)
    end

    @testset "rationals" begin
        g = giac_eval("3/4")
        @test Rational(g) == 3//4
        @test Rational(g) === convert(Rational, g)
        @test Rational{BigInt}(g) == big(3)//big(4)
        @test convert(Rational{BigInt}, g) == big(3)//big(4)
        @test Rational(giac_eval("5")) == 5//1
    end

    @testset "complex" begin
        g = giac_eval("2 + 3i")
        @test Complex(g) == 2 + 3im
        @test Complex(g) == convert(Complex, g)
        @test ComplexF64(g) === ComplexF64(2, 3)
        @test convert(ComplexF64, g) === ComplexF64(2, 3)
    end

    @testset "symbolic input is refused" begin
        g = giac_eval("x")
        @test_throws MethodError Integer(g)
        @test_throws MethodError Int64(g)
        @test_throws MethodError BigInt(g)
        @test_throws MethodError Rational(g)
        @test_throws MethodError Complex(g)
        # the pre-existing convert keeps throwing MethodError too
        @test_throws MethodError convert(Int64, g)
    end

    @testset "a non-integer is not an integer" begin
        @test_throws MethodError Integer(giac_eval("3/4"))
        @test_throws MethodError Int64(giac_eval("2.5"))
    end
end
