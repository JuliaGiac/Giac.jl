# Tests for @exact: the numbers Julia would compute in floating point (decimal
# literals, π, ℯ, roots and quotients of integer literals) kept exact

@testset "@exact literals" begin
    G(v) = convert(GiacExpr, v)
    S(v) = string(v)

    @testset "a float literal is read from its shortest decimal form" begin
        R = Giac._shortest_rational
        @test R(0.1) === 1 // 10
        @test R(2.5e-3) === 1 // 400
        @test R(-1.25) === -5 // 4
        @test R(3.0) === 3 // 1
        @test R(-0.0) === 0 // 1
        @test R(123456.789) === 123456789 // 1000
        @test R(1.0e16) === 10^16 // 1
        @test R(0.1f0) === 1 // 10                       # a Float32 literal, from its own digits
        @test R(1.0e300) == big(10)^300 // 1              # too large for Int: a BigInt rational
        @test R(5.0e-324) == 5 // big(10)^324
    end

    @testset "decimal literals become exact Giac numbers" begin
        r = @exact 0.1 + 0.2
        @test r isa GiacExpr && S(r) == "3/10"
        @test @exact(0.1 + 0.2 == 0.3)
        @test S(@exact 2.5e-3) == "1/400"
        @test S(@exact -0.75) == "-3/4"
        @test S(@exact 1.5f0) == "3/2"
        @test S(@exact 1.0e-30) == "1/" * "1" * "0"^30
        @test S(@exact [0.5, 0.25]) == S([G(1 // 2), G(1 // 4)])
        @giac_var x
        @test S(@exact 0.5x + 0.25) == S(G(1 // 2) * x + G(1 // 4)) == "1/2*x+1/4"
        @test !occursin(".", S(@exact Giac.Commands.solve(x^2 - 0.5, x)))
        @test occursin(".", S(Giac.Commands.solve(x^2 - 0.5, x)))      # floats without the macro
        @test S(@exact exp(0.5)) == "exp(1/2)"
        @test S(@exact sqrt(2.0)) == "sqrt(2)"
        @test @exact(sqrt(0.5)) == 1 / sqrt(G(2))
    end

    # From Kahli Burke's ergonomics branch (test/test_normal_forms.jl, "exact literals")
    @testset "constants, roots, powers and quotients of integer literals" begin
        @giac_var x
        ex = Giac._exact_literals(:(sin(2π * x) + sqrt(2) * x^(1 / 2) + 2^(1 // 3) * ℯ))
        @test S(Base.invokelatest(eval(:(x -> $ex)), x)) ==
              S(sin(2 * G(π) * x) + sqrt(G(2)) * x^(1 // 2) + G(2)^(1 // 3) * G(ℯ))
        @test Giac._exact_literals(:(f(n, 2 * 3))) == :(f(n, 2 * 3))   # names and integers as written
        @giac_var a::positive
        @test S(@exact sqrt(2 / a) * sin(2π * x / a)) == S(sqrt(2 // 1 / a) * sin(2 * G(π) * x / a))
        @test !occursin(".", S(@exact 2π * x + sqrt(2)))
        @test @exact(sqrt(1 / 2)) == 1 / sqrt(G(2)) && !occursin(".", S(@exact sqrt(1 / 2)))
        @giac_var a
        @test (@exact 1 / 2) isa GiacExpr && S(@exact 1 / 2) == "1/2"
        @test S(@exact exp(1 / 2)) == "exp(1/2)"
        @test S(@exact 2^-1) == "1/2"
        @test S(@exact cbrt(2)) == S(G(2)^(1 // 3))
        @test S(@exact pi / 4) == "pi/4"
    end

    @testset "assignments bind Giac numbers" begin
        @exact three = 3
        @test three isa GiacExpr && sqrt(three) == 3 / sqrt(three)
        @exact begin
            h = 1 / 2
            n = 0
            for k in 1:2
                n = k                                 # not the macro's own assignment
            end
        end
        @test h isa GiacExpr && S(h) == "1/2" && n === 2
        @exact flag = true
        @test flag === true
        @exact d = 0.1
        @test d isa GiacExpr && S(d) == "1/10"
    end

    @testset "what is left as written" begin
        @giac_var x
        y = 0.1
        @test S(@exact y * x) == S(y * x)                   # a float in a variable is no literal
        @test (@exact 2 * 3) === 6                          # integer arithmetic is Julia's
        @test (@exact 7) === 7
        @test (@exact 123456789012345678901234567890) isa Int128
        @test (@exact big(2)^70) == big(2)^70
        @test (@exact Base.pi * 2) isa Float64              # a qualified π is Julia's float
        @test (@exact :(0.1)) === 0.1                       # quoted code
        @test Giac._exact_literals(:(@foo 0.1)).args[end] === 0.1   # other macros' code
        @test S(@exact @exact(0.1) + 0.2) == "3/10"         # a nested @exact expands itself
    end

    @testset "big literals" begin
        @test S(@exact big(0.1)) == "1/10"
        @test S(@exact big(1 / 2)) == "1/2" && S(@exact big(π)) == "pi"
        @test S(@exact big"0.1") == "1/10"
        @test S(@exact big"2.5e-3") == "1/400"
        @test (@exact big"12345678901234567890123") isa BigInt
    end

    @testset "hygiene and export" begin
        @test Symbol("@exact") in names(Giac)
        m = Module(:ExactHygiene)
        Core.eval(m, :(import Giac))
        r = Core.eval(m, :(Giac.@exact 0.1 + 0.2))
        @test r isa GiacExpr && S(r) == "3/10"
    end
end
