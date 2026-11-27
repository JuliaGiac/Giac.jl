# assuming: assumptions for one block, undone afterwards; with_settings and giac_settings: the
# session settings that change results. Scoped assumptions follow Kahli Burke's `ergonomics`
# branch; restoring the state as GIAC held it, and the settings, follow MathInterchange's feedback.

@testset "assuming" begin
    C = Giac.Commands
    S = string

    @testset "a condition holds inside the block only" begin
        @giac_var k
        @test S(assuming(() -> C.simplify(sqrt(k^2)), k > 0)) == "k"
        @test S(C.simplify(sqrt(k^2))) == "abs(k)"
        @test S(C.about(k)) == "k"                              # nothing assumed afterwards
        # several conditions on one variable combine
        r = assuming(k > 0, k < 1) do
            S(C.about(k))
        end
        @test occursin("line[0,1]", r)
    end

    @testset "what a variable was declared with is restored" begin
        @giac_var k::(integer, >(2))
        before = S(C.about(k))
        inside = assuming(k < 10) do
            S(C.about(k))
        end
        @test occursin("integer", inside) && occursin("line[2,10]", inside)   # added to the declaration
        @test S(C.about(k)) == before
    end

    @testset "a condition GIAC already decides" begin
        # with k declared positive, `k > 0` is already `true` when it reaches assuming
        @giac_var k::positive
        before = S(C.about(k))
        @test S(assuming(() -> C.simplify(sqrt(k^2)), k > 0)) == "k"
        @test S(C.about(k)) == before
        @test_throws ArgumentError assuming(() -> nothing, k < 0)   # false: contradicts the declaration
        @test S(C.about(k)) == before
    end

    @testset "a domain" begin
        @giac_var n
        @test occursin("integer", assuming(() -> S(C.about(n)), n => :integer))
        @test S(C.about(n)) == "n"
        @test_throws ArgumentError assuming(() -> nothing, n => :wobbly)
    end

    @testset "restored after an error" begin
        @giac_var k
        @test_throws ErrorException assuming(k > 0) do
            error("inside")
        end
        @test S(C.about(k)) == "k"
    end

    @testset "settings changed inside are put back" begin
        @giac_var k
        @test !giac_settings().complex_mode
        assuming(k > 0) do
            giac_eval("complex_mode:=1")
        end
        @test !giac_settings().complex_mode
    end
end

@testset "with_settings and giac_settings" begin
    S = string
    s = giac_settings()
    @test s isa NamedTuple
    @test keys(s) == (:complex_mode, :approx_mode, :angle_radian, :complex_variables, :epsilon, :digits)
    @test s.epsilon isa Float64 && s.digits isa Int

    @giac_var x
    @test with_settings(() -> giac_settings().complex_mode; complex_mode = true)
    @test !giac_settings().complex_mode
    # MathInterchange's case: complex_mode changes what simplify(sqrt(x^2)) means
    @test S(with_settings(() -> Giac.Commands.simplify(sqrt(x^2)); complex_mode = false)) == "abs(x)"
    @test with_settings(() -> giac_settings().digits; digits = 20) == 20
    @test giac_settings().digits == s.digits
    @test with_settings(() -> giac_settings().epsilon; epsilon = 1e-8) == 1e-8
    @test giac_settings().epsilon == s.epsilon
    # restored after an error, and every setting, not only those given
    @test_throws ErrorException with_settings(approx_mode = true) do
        giac_eval("angle_radian:=0")
        error("inside")
    end
    @test giac_settings() == s
    @test_throws ArgumentError with_settings(() -> nothing; wobbly = 1)
end
