# GiacSymbolicUtilsExt: exact conversion between Giac and SymbolicUtils, with SymbolicUtils alone
# (no Symbolics). The cases are MathInterchange's fixtures (MathInterfaceGiac.jl, test/giac.jl):
# exact numbers, radicals never turned into floats, an error rather than a guess.

using SymbolicUtils
const SU = SymbolicUtils

@testset "GiacSymbolicUtilsExt" begin
    @syms x::Real
    @giac_var v
    C = Giac.Commands
    names = Dict("v" => x)                     # Giac name => SymbolicUtils symbol
    su(g) = to_symbolicutils(g; symbols = names)
    eq(a, b) = isequal(SU.simplify(a - b), 0) || isequal(a, b)

    @testset "exact antiderivatives" begin
        @test isequal(su(C.integrate(v^2 + 2, v)), (1 // 3) * x^3 + 2x)
        @test eq(su(C.integrate(2v + 1, v)), x^2 + x)
        @test isequal(su(C.integrate((v + 1)^2, v)), (1 // 3) * (1 + x)^3)        # kept factored
        @test isequal(su(C.integrate(3 * v^2 / 4 - v + 5, v)), (1 // 4) * x^3 - (1 // 2) * x^2 + 5x)
    end

    @testset "Giac's function names" begin
        # Giac writes the natural logarithm ln (MathInterchange's report on integrate(1/v, v))
        @test isequal(su(C.integrate(1 / v, v)), log(abs(x)))
        @test isequal(to_symbolicutils(giac_eval("ln(v)"); symbols = names, strict_symbols = true), log(x))
        @test isequal(su(giac_eval("ln(2)")), SU.term(log, 2))           # not 0.693…
        # an elementary function comes back as itself, or as the form Giac evaluates it to
        g(f) = su(giac_eval(Giac.giac_source(f(x); names = Dict(x => "v"))))
        for f in (sqrt, abs, sign, exp, log, sin, cos, tan, asin, acos, atan, sinh, cosh, tanh, floor)
            @test isequal(g(f), f(x))
        end
        @test isequal(g(asinh), log(sqrt(1 + x^2) + x))
        # GIAC 2.1 writes acosh with two square roots, right off the real axis too
        @test isequal(g(acosh), Giac.giac_version() >= v"2.1" ? log(x + sqrt(1 + x) * sqrt(-1 + x)) :
                                                                  log(sqrt(-1 + x^2) + x))
        @test isequal(g(atanh), (1 // 2) * log((1 + x) / (1 - x)))
        @test isequal(g(ceil), -floor(-x))
    end

    @testset "simplify under premises" begin
        @test isequal(su(assuming(() -> C.simplify(sqrt(v^2)), v > 0)), x)
        @test isequal(su(C.simplify(sqrt(v^2))), abs(x))
        @test isequal(su(assuming(() -> C.simplify(sqrt(v^2)), v < 0)), -x)
    end

    @testset "numbers stay exact" begin
        s = su(sqrt(giac_eval("2")) * v)
        @test isequal(s, SU.term(sqrt, 2) * x)
        @test !occursin("1.41", string(s))
        @test su(giac_eval("1/3")) === 1 // 3 || su(giac_eval("1/3")) == Rational{BigInt}(1, 3)
        @test su(giac_eval("1/3")) isa Rational{BigInt}
        @test su(giac_eval("inv(2)")) == 1 // 2
        @test su(giac_eval("7")) === 7
        big_n = su(giac_eval("2^100"))
        @test big_n isa BigInt && big_n == big(2)^100
        @test isequal(su(giac_eval("v^(1/3)")), x^(1 // 3))
        @test isequal(su(giac_eval("sqrt(v)")), sqrt(x))
        # constants that arithmetic must not turn into floats
        @test !occursin("6.28", string(su(2 * giac_eval("pi") * v)))
        @test occursin("exp(1)", string(su(giac_eval("exp(1)"))))
        @test isequal(su(giac_eval("i")), im)
    end

    @testset "an error rather than a guess" begin
        @test_throws ArgumentError su(giac_eval("1.5"))                     # a float
        @test_throws ArgumentError su(giac_eval("1.5") * v)
        @test isequal(su(giac_eval("atan(v)")), atan(x))                    # in the table
        @test_throws ArgumentError su(giac_eval("Gamma(v)"))                # not in the table
        @test to_symbolicutils(giac_eval("1.5"); exact = false) == 1.5      # opt out
        # a name the caller did not map becomes a SymbolicUtils symbol of the same name
        w = to_symbolicutils(giac_eval("w"))
        @test SU.issym(w) && string(w) == "w"
        # unless strict_symbols asks for an error (an identifier outside the request)
        @test_throws ArgumentError to_symbolicutils(giac_eval("w") + v; symbols = Dict("v" => x),
                                                    strict_symbols = true)
        mapped = Dict{String, Any}("v" => x)
        @test isequal(to_symbolicutils(v + 1; symbols = mapped, strict_symbols = true), x + 1)
        @test collect(keys(mapped)) == ["v"]                       # nothing added
    end

    @testset "to Giac" begin
        back = Dict(x => "v")                   # SymbolicUtils symbol => Giac name
        G(t) = to_giac(t; names = back)
        # the same Giac expression as MathInterchange's string: GIAC writes `0<v` as `v>0`
        same_relation(t, s) = string(G(t)) == string(giac_eval(s))
        same_value(t, s) = string(C.simplify(G(t) - giac_eval(s))) == "0"
        @test same_relation(x > 0, "0<v")
        @test same_relation((x < 0) | (x > 10), "(v<0) or (10<v)")
        @test same_relation((0 < x) & (x <= 10), "(0<v) and (v<=10)")
        @test string(to_giac(1 // 3 * x; names = back)) in ("v/3", "1/3*v")
        @test same_value(x^2 + 2x, "v^2+2*v")
        @test string(G(sqrt(x))) == "sqrt(v)"
        @test same_value(SU.term(sqrt, 2) * x, "sqrt(2)*v")
        @test !occursin("1.41", string(G(SU.term(sqrt, 2) * x)))
        @test_throws ArgumentError to_giac(0.5 * x; names = back)
        @test string(to_giac(0.5 * x; names = back, exact = false)) == "0.5*v"
        # giac_source: the unevaluated Giac text, to record what Giac receives
        src(t) = Giac.giac_source(t; names = back)
        @test src(x > 0) == "(0<v)"
        @test src((x < 0) | (x > 10)) == "((v<0) or (10<v))"
        @test src((0 < x) & (x <= 10)) == "((0<v) and (v<=10))"
        @test src(!(x > 0)) == "(not((0<v)))"
        @test src((1 // 3) * x) == "((1/3)*v)"
        @test src(x^2 + 2) in ("(2+(v^2))", "((v^2)+2)")
        @test src(sqrt(x^2)) == "sqrt((v^2))"                  # not evaluated: no abs here
        @test src(SU.term(sqrt, 2) * x) in ("(sqrt(2)*v)", "(v*sqrt(2))")
        @test src(-x) == "(-v)" || src(-x) == "((-1)*v)"
        @test_throws ArgumentError src(0.5 * x)
        @test_throws ArgumentError Giac.giac_source(SU.term(cbrt, x); names = back)
        @test Giac.giac_source(0.5 * x; names = back, exact = false) == "(0.5*v)"
        # what Giac makes of the text is what to_giac builds
        for t in (x^2 + 2x, (1 // 3) * x^3 + SU.term(sqrt, 2) * x, sqrt(x^2), (0 < x) & (x <= 10))
            @test string(giac_eval(src(t))) == string(G(t))
        end
        # a round trip keeps exactness
        e = (1 // 3) * x^3 + SU.term(sqrt, 2) * x
        @test isequal(to_symbolicutils(to_giac(e; names = back); symbols = names), e)
    end
end
