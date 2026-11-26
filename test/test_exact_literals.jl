# Tests for @exact: the numbers Julia would compute in floating point (π, ℯ,
# roots and quotients of integer literals) kept exact

@testset "@exact literals" begin
    G(v) = convert(GiacExpr, v)
    S(v) = string(v)

    @testset "constants, roots, powers and quotients of integer literals" begin
        @giac_var x
        ex = Giac._exact_literals(:(sin(2π * x) + sqrt(2) * x^(1 / 2) + 2^(1 // 3) * ℯ))
        @test S(Base.invokelatest(eval(:(x -> $ex)), x)) ==
              S(sin(2 * G(π) * x) + sqrt(G(2)) * x^(1 // 2) + G(2)^(1 // 3) * G(ℯ))
        @test Giac._exact_literals(:(f(1.5, 2 * 3))) == :(f(1.5, 2 * 3))           # floats and integers as written
        @giac_var a::positive
        @test S(@exact sqrt(2 / a) * sin(2π * x / a)) == S(sqrt(2 // 1 / a) * sin(2 * G(π) * x / a))
        @test !occursin(".", S(@exact 2π * x + sqrt(2)))
        @test @exact(sqrt(1 / 2)) == 1 / sqrt(G(2)) && !occursin(".", S(@exact sqrt(1 / 2)))
        @giac_var a
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
    end
end
