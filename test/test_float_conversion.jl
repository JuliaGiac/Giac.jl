# Tests for `AbstractFloat(::GiacExpr)`, and the `float` that falls out of it.
#
# `Base.float(x) = AbstractFloat(x)` is defined on `Any`, not on `Number`
# (base/float.jl), so declaring the constructor is enough to get `float` for a
# type that is not a `Number` — which `GiacExpr` is not.

using Giac.GenTypes

@testset "Float conversion" begin

    @testset "float falls out of AbstractFloat" begin
        # Nothing defines `Base.float(::GiacExpr)`; it comes from Base's
        # `float(x) = AbstractFloat(x)`.
        @test float(giac_eval("2")) === 2.0
        @test AbstractFloat(giac_eval("2")) === 2.0
        @test which(float, (GiacExpr,)).module === Base
    end

    @testset "scalars" begin
        @test float(giac_eval("2")) === 2.0
        @test float(giac_eval("2.34")) === 2.34
        @test float(giac_eval("23456789012345678901")) isa BigFloat
        @test float(giac_eval("1234567890/2345678901")) isa Float64
        @test float(giac_eval("2 + 3i")) === ComplexF64(2, 3)
    end

    @testset "the result is always a float" begin
        # `float` returning a `GiacExpr` or a `String` would be a contract
        # violation; both used to happen.
        for src in ("2", "2.34", "inf", "-inf", "undef", "pi", "e", "sin(2)")
            @test float(giac_eval(src)) isa Union{AbstractFloat,Complex{<:AbstractFloat}}
        end
    end

    @testset "non-finite atoms" begin
        # `is_constant` calls these constant — no free symbols — but `evalf`
        # cannot reduce them. Without an explicit mapping they fall through
        # and come back unconverted, or hit the final throw.
        @test float(giac_eval("inf")) === Inf
        @test float(giac_eval("+inf")) === Inf
        @test float(giac_eval("infinity")) === Inf
        @test float(giac_eval("-inf")) === -Inf
        @test float(giac_eval("-infinity")) === -Inf
        @test isnan(float(giac_eval("undef")))
        @test float(giac_eval("1/0")) === Inf
    end

    @testset "a string is not a number" begin
        # A Giac string has no free symbols, so `is_constant` is true for it.
        @test_throws ArgumentError float(giac_eval("\"abc\""))
    end

    @testset "symbolic input is refused" begin
        for src in ("x", "x + 1", "x = 1")
            @test_throws ArgumentError float(giac_eval(src))
        end
    end

    @testset "containers" begin
        @test float(giac_eval("[1,2,3]")) == [1.0, 2.0, 3.0]
        @test float(giac_eval("[1,2,3]")) isa Vector{Float64}
        @test float(giac_eval("[]")) isa Vector{Float64}   # not Vector{Any}
        @test isempty(float(giac_eval("[]")))
        @test float(giac_eval("[pi,1]")) isa Vector{Float64}
        @test_throws ArgumentError float(giac_eval("[x,1]"))
    end

    @testset "Float64 fidelity" begin
        # The symbolic branch reduces through `evalf(ex, d)` and reads the
        # decimal back. `d = 16` is short of what a Float64 needs, and `d = 17`
        # still loses an ulp to double rounding on values such as sqrt(2).
        for (src, want) in (
            ("sqrt(2)", sqrt(2.0)), ("sqrt(3)", sqrt(3.0)), ("sqrt(7)", sqrt(7.0)),
            ("sin(1)", sin(1.0)), ("sin(2)", sin(2.0)), ("cos(1)", cos(1.0)),
            ("cos(2)", cos(2.0)), ("tan(1)", tan(1.0)), ("tan(2)", tan(2.0)),
            ("exp(1)", exp(1.0)), ("exp(2)", exp(2.0)), ("log(2)", log(2.0)),
            ("log(3)", log(3.0)), ("log(10)", log(10.0)), ("atan(1)", atan(1.0)),
            ("atan(2)", atan(2.0)),
        )
            @test float(giac_eval(src)) === want
        end
    end

    @testset "a REAL keeps the precision it carries" begin
        # `parse(BigFloat, s)` alone rounds to the ambient precision, which
        # discards whatever Giac computed beyond it.
        for digits in (20, 50, 100)
            r = Giac.Commands.evalf(giac_eval("pi"), digits)
            v = float(r)
            @test v isa BigFloat
            @test precision(v) >= ceil(Int, digits * log2(10))
            # every digit Giac printed is preserved, to within an ulp there
            setprecision(BigFloat, 8 + ceil(Int, 4 * digits * log2(10))) do
                want = parse(BigFloat, string(r))
                @test abs(BigFloat(v) - want) < abs(want) * big(10.0)^(-digits + 1)
            end
        end
        # and it does not depend on the ambient setting
        r = Giac.Commands.evalf(giac_eval("pi"), 100)
        setprecision(BigFloat, 53) do
            @test precision(float(r)) >= ceil(Int, 100 * log2(10))
        end
    end

    @testset "recognised constants" begin
        @test float(giac_eval("pi")) === Float64(pi)
        @test float(giac_eval("e")) === Float64(ℯ)
        @test float(giac_eval("i")) === ComplexF64(0, 1)
    end
end
