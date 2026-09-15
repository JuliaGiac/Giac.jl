# Nemo Conversion Extension Tests (081-nemo-oscar-bridge)
# Bidirectional bridge Giac.jl <-> Nemo.jl, modelled on the LibPARI bridge:
# value-preserving (not representation-preserving), with an explicit refusal
# list. Reals/balls and p-adics are refused in v1; finite fields and number
# fields require the caller to supply the parent ring.

using Nemo
import Nemo: ZZ, QQ
using Giac: to_giac, to_nemo

const SUPPORTED_OUTWARD = "ZZRingElem, QQFieldElem, univariate polys over " *
    "ZZ/QQ, FqFieldElem/FpFieldElem, AbsSimpleNumFieldElem, ZZMatrix/QQMatrix"
const SUPPORTED_INWARD = "parent ring ZZ, QQ, a univariate polynomial ring " *
    "over ZZ/QQ, a number field, a finite field, or a ZZ/QQ matrix space"

@testset "Nemo Bridge (to_giac: Nemo -> Giac)" begin

    @testset "integers" begin
        @test to_giac(ZZ(42)) == giac_eval("42")
        @test to_giac(ZZ(-7)) == giac_eval("-7")
        @test to_giac(ZZ(0)) == giac_eval("0")
        # arbitrary precision
        big_n = big"123456789012345678901234567890"
        @test to_julia(to_giac(ZZ(big_n))) == big_n
    end

    @testset "rationals" begin
        @test to_giac(QQ(3, 4)) == giac_eval("3/4")
        @test to_giac(QQ(-5, 2)) == giac_eval("-5/2")
        @test to_giac(QQ(6, 1)) == giac_eval("6")
    end

    @testset "univariate polynomials over ZZ" begin
        R, x = polynomial_ring(ZZ, "x")
        @test to_giac(3x^3 - 2x + 5) == giac_eval("3*x^3-2*x+5")
        @test to_giac(x^2 + 1) == giac_eval("x^2+1")
        @test to_giac(R(0)) == giac_eval("0")
    end

    @testset "univariate polynomials over QQ" begin
        S, y = polynomial_ring(QQ, "y")
        @test to_giac(QQ(1, 2) * y^2 + 3) == giac_eval("1/2*y^2+3")
        @test to_giac(QQ(3, 4) * y - QQ(1, 2)) == giac_eval("3/4*y-1/2")
    end

    @testset "finite fields" begin
        # prime field: element lifts to an integer
        Fp, z = finite_field(7, "z")
        @test to_giac(Fp(5)) == giac_eval("5")
        @test to_giac(Fp(0)) == giac_eval("0")
        # non-prime field: element is a polynomial in the generator symbol
        F, t = finite_field(7, 3, "t")
        @test to_giac(t^2 + 1) == giac_eval("t^2+1")
        @test to_giac(t) == giac_eval("t")
    end

    @testset "number fields" begin
        R, x = polynomial_ring(QQ, "x")
        K, a = number_field(x^2 - 2, "a")
        @test to_giac(a) == giac_eval("a")
        @test to_giac(a^2) == giac_eval("2")     # reduced: a^2 = 2
        @test to_giac(3a + 1) == giac_eval("3*a+1")
    end

    @testset "matrices over ZZ" begin
        M = Nemo.matrix(ZZ, 2, 2, ZZRingElem[1, 2, 3, 4])
        g = to_giac(M)
        @test g isa Giac.GiacMatrix
        @test size(g) == (2, 2)
        @test to_julia(g[1, 1]) == 1
        @test to_julia(g[2, 1]) == 3
    end

    @testset "matrices over QQ" begin
        M = Nemo.matrix(QQ, 2, 2, QQFieldElem[1, QQ(1, 2), QQ(3, 4), 4])
        g = to_giac(M)
        @test g isa Giac.GiacMatrix
        @test to_julia(g[1, 2]) == 1 // 2
    end
end

@testset "Nemo Bridge (to_nemo: Giac -> Nemo)" begin

    @testset "into ZZ" begin
        @test to_nemo(giac_eval("42"), ZZ) == ZZ(42)
        @test to_nemo(giac_eval("-7"), ZZ) == ZZ(-7)
        big_n = big"123456789012345678901234567890"
        @test to_nemo(giac_eval(string(big_n)), ZZ) == ZZ(big_n)
    end

    @testset "into QQ" begin
        @test to_nemo(giac_eval("3/4"), QQ) == QQ(3, 4)
        @test to_nemo(giac_eval("-5/2"), QQ) == QQ(-5, 2)
        @test to_nemo(giac_eval("6"), QQ) == QQ(6, 1)
    end

    @testset "into a univariate polynomial ring over ZZ" begin
        R, x = polynomial_ring(ZZ, "x")
        @test to_nemo(giac_eval("3*x^3-2*x+5"), R) == 3x^3 - 2x + 5
        @test to_nemo(giac_eval("x^2+1"), R) == x^2 + 1
        @test to_nemo(giac_eval("0"), R) == R(0)
    end

    @testset "into a univariate polynomial ring over QQ" begin
        S, y = polynomial_ring(QQ, "y")
        @test to_nemo(giac_eval("1/2*y^2+3"), S) == QQ(1, 2) * y^2 + 3
        @test to_nemo(giac_eval("3/4*y-1/2"), S) == QQ(3, 4) * y - QQ(1, 2)
    end

    @testset "into a number field" begin
        R, x = polynomial_ring(QQ, "x")
        K, a = number_field(x^2 - 2, "a")
        @test to_nemo(giac_eval("a^2+3"), K) == a^2 + 3
        @test to_nemo(giac_eval("3*a+1"), K) == 3a + 1
        @test to_nemo(giac_eval("5"), K) == K(5)
    end

    @testset "into a prime finite field" begin
        Fp, z = finite_field(7, "z")
        @test to_nemo(giac_eval("5"), Fp) == Fp(5)
        @test to_nemo(giac_eval("10"), Fp) == Fp(3)   # 10 mod 7
    end

    @testset "into a non-prime finite field" begin
        F, t = finite_field(7, 3, "t")
        @test to_nemo(giac_eval("t^2+1"), F) == t^2 + 1
        @test to_nemo(giac_eval("t"), F) == t
        @test to_nemo(giac_eval("3"), F) == F(3)
    end

    @testset "into a ZZ matrix space" begin
        # Build via GiacMatrix then convert
        m = giac_eval("[[1,2],[3,4]]")
        M = to_nemo(m, Nemo.matrix_space(ZZ, 2, 2))
        @test M == Nemo.matrix(ZZ, 2, 2, ZZRingElem[1, 2, 3, 4])
    end
end

@testset "Nemo Bridge round-trip (by value)" begin
    R, x = polynomial_ring(ZZ, "x")
    S, y = polynomial_ring(QQ, "y")
    Rx, xp = polynomial_ring(QQ, "x")
    K, a = number_field(xp^2 - 2, "a")
    F, t = finite_field(7, 3, "t")

    cases = [
        (ZZ(42), ZZ),
        (QQ(3, 4), QQ),
        (3x^3 - 2x + 5, R),
        (QQ(1, 2) * y^2 + 3, S),
        (3a + 1, K),
        (t^2 + 1, F),
    ]
    for (elem, parent) in cases
        @test to_nemo(to_giac(elem), parent) == elem
    end
end

@testset "Nemo Bridge refusals" begin

    @testset "transcendental functions refused inward" begin
        R, x = polynomial_ring(ZZ, "x")
        @test_throws ErrorException to_nemo(giac_eval("sin(x)"), R)
        @test_throws ErrorException to_nemo(giac_eval("ln(x)"), R)
        @test_throws ErrorException to_nemo(giac_eval("exp(x)"), R)
    end

    @testset "constants pi/e refused inward" begin
        R, x = polynomial_ring(ZZ, "x")
        @test_throws ErrorException to_nemo(giac_eval("pi"), ZZ)
        @test_throws ErrorException to_nemo(giac_eval("e"), ZZ)
    end

    @testset "reals/balls refused both directions" begin
        # Inward: Giac float into ZZ is refused (not an exact integer).
        @test_throws ErrorException to_nemo(giac_eval("3.14"), ZZ)
        # Outward: ArbFieldElem refused in v1.
        A = ArbField(64)
        @test_throws ErrorException to_giac(A(1))
        # p-adic refused outward
        Qp = PadicField(7, 10)
        @test_throws ErrorException to_giac(Qp(1))
    end

    @testset "non-integer into ZZ refused" begin
        @test_throws ErrorException to_nemo(giac_eval("3/4"), ZZ)
    end
end