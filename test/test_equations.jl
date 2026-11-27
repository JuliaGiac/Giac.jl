# Equations as values: sides, arithmetic on both sides, isolate, substitution by equation,
# equations between arrays and solving for a matrix unknown.
# Ported from Kahli Burke's `ergonomics` branch (test/test_equations.jl, test/test_array_algebra.jl).

@testset "Equations" begin
    @giac_var x y a b
    S = string
    eq = 2x + 3 ~ y

    @testset "sides" begin
        @test S(lhs(eq)) == "2*x+3"
        @test S(rhs(eq)) == "y"
        @test S.(rhs.([x ~ 1, y ~ 2])) == ["1", "2"]
        @test_throws ArgumentError lhs(x + 1)
        @test Giac._is_equation(eq)
        @test !Giac._is_equation(x + 1)
        @test !Giac._is_equation(giac_eval("3"))
    end

    @testset "arithmetic applies to both sides" begin
        @test S(eq - 3) == S(2x ~ y - 3)
        @test S(eq + 1) == S(lhs(eq) + 1 ~ y + 1)
        @test S(2eq) == S(2 * (2x + 3) ~ 2y)
        @test S(eq / 2) == S((2x + 3) / 2 ~ y / 2)
        @test S(-eq) == S(-(2x + 3) ~ -y)
        @test S(eq^2) == S((2x + 3)^2 ~ y^2)
        @test S(eq + (a ~ b)) == S(2x + 3 + a ~ y + b)
        @test S(1 / eq) == S(1 / (2x + 3) ~ 1 / y)
        @test S(Giac.Commands.simplify((eq - 3) / 2)) == S(x ~ (y - 3) / 2)
        # ordinary arithmetic is unchanged
        @test S(x + 1) == "x+1"
    end

    @testset "isolate" begin
        @test S(isolate(eq, x)) == S(x ~ (y - 3) / 2)
        sols = isolate(x^2 ~ a, x)
        @test sols isa Vector{GiacExpr} && length(sols) == 2
        @test all(s -> S(lhs(s)) == "x", sols)
        @test Set(S.(isolate(x^2 - 4, x))) == Set(["x=-2", "x=2"])
        @test_throws ArgumentError isolate(x ~ x + 1, x)
    end

    @testset "substitute with equations" begin
        @test S(substitute(x + y, y ~ 2x)) == S(substitute(x + y, y => 2x))
        @test S(substitute(x * y + a, [y ~ 2x, a ~ 1])) == S(substitute(x * y + a, y => 2x, a => 1))
        @test S(substitute(x * y + a, y ~ 2x, a => 1)) == S(substitute(x * y + a, y => 2x, a => 1))
        @test S(substitute(y^2, isolate(eq, y))) == S(substitute(y^2, y => 2x + 3))
        # pairs alone work as before
        @test S(substitute(x + 1, x => 5)) == "6"
        @test substitute(x + 1) === x + 1 || S(substitute(x + 1)) == "x+1"
    end

    @testset "a float keeps its digits" begin
        @test S(x ~ 0.123456789012345) == "x=0.123456789012345"
    end
end

@testset "Equations between arrays" begin
    @giac_var a11 a12 a21 a22 p11 p12 p22 s
    A = [a11 a12; a21 a22]
    P = [p11 p12; p12 p22]              # a symmetric unknown

    @testset "entry by entry" begin
        eqs = A ~ [1 2; 3 4]
        @test size(eqs) == (2, 2) && string(eqs[2, 1]) == "a21=3"
        @test string.(A ~ I) == ["a11=1" "a12=0"; "a21=0" "a22=1"]
        @test size(A ~ s * I) == (2, 2) && string((A ~ s * I)[1, 1]) == "a11=s"
        @test string.([a11, a12] ~ 0) == ["a11=0", "a12=0"]   # every entry equal to one value
        @test_throws DimensionMismatch A ~ [a11 a12]
    end

    @testset "solve for a matrix unknown" begin
        eqs = P * A + A' * P ~ -I
        N = Giac.Commands.normal
        @test string(N(eqs[1, 2])) == string(N(eqs[2, 1]))      # symmetric unknown: repeated equation
        P★ = Giac.Commands.solve(eqs, P)
        @test P★ isa Matrix{GiacExpr}
        @test string.(Giac.Commands.simplify.(P★ * A + A' * P★)) == ["-1" "0"; "0" "-1"]
        @test string(P★[1, 2]) == string(P★[2, 1])

        # a concrete stable A gives a numeric P
        @giac_var b
        Ab = GiacExpr[giac_eval("-b") giac_eval("-1"); giac_eval("1") giac_eval("0")]
        Pb = Giac.Commands.solve(P * Ab + Ab' * P ~ -I, P)
        @test string.(Giac.Commands.normal.(Pb)) == ["1/b" "1/2"; "1/2" "(b^2+2)/(2*b)"]

        # no solution
        @test_throws ArgumentError Giac.Commands.solve(P ~ P + I, P)             # reduces to 0 = 1
    end
end
