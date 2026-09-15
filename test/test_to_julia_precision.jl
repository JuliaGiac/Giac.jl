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
