# `to_julia` on a symbolic constant reduces it through `evalf` and reads the
# decimal back. With no digit argument, `evalf` yields a Giac DOUBLE printed at
# the global `Digits` — 12 — so every constant reached Julia with four digits
# missing, and `to_julia` and `float` disagreed on `pi` once `float` landed.

using Giac.GenTypes

@testset "to_julia keeps Float64 precision" begin

    @testset "recognised constants" begin
        @test to_julia(giac_eval("pi")) === Float64(pi)
        @test to_julia(giac_eval("e")) === Float64(ℯ)
    end

    @testset "to_julia and float agree" begin
        for src in ("pi", "e", "sqrt(2)", "sin(2)", "cos(1)", "exp(1)",
                    "log(2)", "atan(1)", "sqrt(3)", "tan(1)")
            g = giac_eval(src)
            @test to_julia(g) === float(g)
        end
    end

    @testset "and agree with Julia's own value" begin
        for (src, want) in (("sqrt(2)", sqrt(2.0)), ("sqrt(3)", sqrt(3.0)),
                            ("sin(1)", sin(1.0)), ("cos(1)", cos(1.0)),
                            ("tan(1)", tan(1.0)), ("exp(1)", exp(1.0)),
                            ("log(2)", log(2.0)), ("atan(1)", atan(1.0)),
                            ("sqrt(7)", sqrt(7.0)), ("log(3)", log(3.0)))
            @test to_julia(giac_eval(src)) === want
        end
    end

    # A GIAC double is read from the decimal GIAC prints for it, at `Digits`
    # (12) significant digits. GIAC's doubles carry fewer mantissa bits than a
    # Float64 (the type tag takes the low byte), and reading the stored bits
    # gives values such as 0.29999999999999 for 0.1+0.2; the printed decimal
    # is the better reading. Exact input stays exact.
    @testset "a GIAC double is read from its printed decimal" begin
        @test to_julia(giac_eval("0.1+0.2")) === 0.3
        @test to_julia(giac_eval("sqrt(2.0)")) === 1.41421356237
        for g in (giac_eval("0.1+0.2"), giac_eval("sqrt(2.0)"))
            v = to_julia(g)
            @test float(g) === v
            @test Float64(g) === v
            @test convert(Float64, g) === v
        end
        for v in (0.1, 0.7, 2.34, -0.3, 1.0e-5, 1.25e-7, 0.5, 2.0, -7.0)
            @test to_julia(giac_eval(string(v))) === v
        end
        # parts of a complex double and vector elements read the same way
        @test to_julia(giac_eval("sqrt(2.0) + sqrt(3.0)*i")) === 1.41421356237 + 1.73205080757im
        @test to_julia(Giac.real_part(giac_eval("sqrt(2.0)+i"))) === 1.41421356237
        @test to_julia(Giac.Commands.evalf(giac_eval("exp(i*pi/3)"))) === 0.5 + 0.866025403784im
        w = to_julia(giac_eval("[sqrt(2.0), sqrt(3.0), 0.1+0.2]"))
        @test w isa Vector{Float64}
        @test w == [1.41421356237, 1.73205080757, 0.3]
        @test to_julia(giac_eval("[[0.1+0.2, 1.5], [2.0, sqrt(2.0)]]")) ==
              [[0.3, 1.5], [2.0, 1.41421356237]]
        # exact input stays exact
        @test to_julia(giac_eval("1/10")) === 1//10
        @test to_julia(giac_eval("exact(0.1)")) === 1//10
        @test to_julia(convert(GiacExpr, 1//10)) === 1//10
        @test to_julia(convert(GiacExpr, 1//10) + convert(GiacExpr, 2//10)) === 3//10
    end

    @testset "REAL values are unchanged" begin
        # a REAL carries its digits in its printed form, which stays the source
        r = Giac.Commands.evalf(giac_eval("pi"), 30)
        @test giac_type(r) == GenTypes.REAL
        @test to_julia(r) === Float64(pi)
        @test to_julia(giac_eval("1.23456789012345")) === 1.23456789012345
    end

    # GIAC stores a complex number with a rational part as a FRAC whose
    # numerator is a Gaussian integer; reading the numerator as an Int64
    # failed with "invalid base 10 digit '+'".
    @testset "complex rationals" begin
        @test to_julia(giac_eval("(3+2*i)/4")) === 3//4 + 1//2 * im
        @test to_julia(giac_eval("2/3+i")) === 2//3 + 1//1 * im
        @test to_julia(giac_eval("-i/7")) === 0//1 - 1//7 * im
        z = to_julia(giac_eval("(2^70+i)/3"))
        @test z isa Complex{Rational{BigInt}}
        @test z == big(2)^70 // 3 + 1//3 * im
        @test to_julia(giac_eval("[1/2, 1/3+i/4]")) == [1//2 + 0im, 1//3 + 1//4 * im]
        @test to_julia(giac_eval("[1/2, 1/3+i/4]")) isa Vector{Complex{Rational{Int64}}}
        # real fractions are unchanged
        @test to_julia(giac_eval("3/4")) === 3//4
        @test to_julia(giac_eval("-3/4")) === -3//4
        @test to_julia(giac_eval("2^70/3")) isa Rational{BigInt}
        # the other conversions agree
        g = giac_eval("1/3+2/5*i")
        @test Complex(g) === 1//3 + 2//5 * im
        @test convert(Complex, g) === 1//3 + 2//5 * im
        @test Complex(giac_eval("3/4")) === Complex(3//4)
        @test float(g) ≈ ComplexF64(1 / 3, 2 / 5)
        @test_throws InexactError Rational(g)
        @test_throws InexactError convert(Float64, g)
        @test_throws InexactError Float64(g)
    end

    # GIAC's evalf of a rootof to n digits sets epsilon, the tolerance of its
    # numeric algorithms, to 10⁻ⁿ for the rest of the session. `to_julia`
    # reduces constants with `evalf(g, 18)`, so converting one left epsilon at
    # 1e-18, after which numeric integrals returned two estimates instead of a
    # value.
    @testset "evalf to some digits keeps epsilon" begin
        eps() = string(giac_eval("epsilon"))
        r = giac_eval("rootof([[-3,0,-15,0,-12],[1,0,6,0,9,0,31]])")
        before = eps()
        Giac.Commands.evalf(r, 30)
        @test eps() == before
        # at epsilon 1e-30 Romberg's method gives up and returns its last two
        # approximations
        @giac_var x
        s = to_julia(invoke_cmd(:romberg, exp(-x^2), x, 0, 1))
        @test s isa Float64
        @test abs(s - 0.7468241328124270) < 1e-10
        invoke_cmd(:evalf, r, 25)
        @test eps() == before
        to_julia(r)
        @test eps() == before
        # an epsilon the user set is what is kept
        giac_eval("epsilon:=1e-8")
        try
            Giac.Commands.evalf(r, 30)
            @test eps() == "1e-08"
        finally
            giac_eval("epsilon:=$before")
        end
        @test eps() == before
    end

    @testset "evalf to some digits leaves epsilon as it was" begin
        r = giac_eval("rootof([[-3,0,-15,0,-12],[1,0,6,0,9,0,31]])")
        eps = string(giac_eval("epsilon"))
        Giac.Commands.evalf(r, 30)                       # GIAC itself leaves epsilon at 1e-30
        @test string(giac_eval("epsilon")) == eps
    end

    @testset "the issue #19 fixed point still holds" begin
        # `evalf` cannot reduce these; they must come back unchanged rather
        # than recursing forever.
        for src in ("inf", "+inf", "-inf", "infinity", "undef")
            @test to_julia(giac_eval(src)) isa GiacExpr
        end
    end

    @testset "symbolic input is untouched" begin
        for src in ("x", "x + 1", "sin(x)")
            @test to_julia(giac_eval(src)) isa GiacExpr
        end
    end
end
