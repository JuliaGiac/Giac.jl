# taylor (Taylor polynomials in one or several variables) and collect_terms / coefficients
# (grouping by monomials). Ported from Kahli Burke's `ergonomics` branch.

@testset "taylor" begin
    @giac_var q1 q2 u
    q = [q1, q2]
    S = string
    @test S(taylor(sin(q1), q1, 5)) == "q1-q1^3/6+q1^5/120"
    @test S(taylor(exp(q1), q1 => 1, 1)) == "exp(1)+exp(1)*(q1-1)"
    # total degree: u*q1^2/2 is third order
    @test taylor(-sin(q1) + q1 * q2 + u * cos(q1), [q; u], 2) == u - q1 + q1 * q2
    # a tuple keeps π exact; an array f is expanded entry by entry
    @test S.(taylor([q2, -sin(q1) + u * cos(q1)], [q; u] => (π, 0, 0), 1)) == ["q2", "q1-pi-u"]
    @test_throws DimensionMismatch taylor(q1, q => (1, 2, 3), 1)
end

@testset "collect_terms" begin
    @giac_var q1 q2 a b
    q = [q1, q2]
    S = string
    c = Giac.coefficients(a * q1^2 + b * q1 * q2 + 2a * q1^2 + 3, q)
    @test S(c[q1^2]) == "3*a"
    @test S(c[q1 * q2]) == "b"
    @test S(c[one(GiacExpr)]) == "3"
    @test length(c) == 3
    # graded order: degree, then powers of the earlier variables
    @test S(collect_terms((q1 + q2 + a)^2, q)) == "q1^2+2*q1*q2+q2^2+2*a*q1+2*a*q2+a^2"
    @test S(collect_terms(a * q1 * q2 + b * q1 * q2 + q2^2 + q1^2, q)) == "q1^2+(a+b)*q1*q2+q2^2"
    # a factor that depends on the variables without being a power is part of the monomial
    @test S(collect_terms(a * sin(q1) * q2 + b * sin(q1) * q2, q)) == "(a+b)*q2*sin(q1)"
    @test S(collect_terms(-a * q1 - q1 + 2, q)) == "(-a-1)*q1+2"
    @test S(collect_terms(a * q1 - a * q1, q)) == "0"
    @test S.(collect_terms([a * q1 + b * q1, q2], q)) == ["(a+b)*q1", "q2"]
    @test S(collect_terms((q1 + a)^2, q1)) == "q1^2+2*a*q1+a^2"
end

@testset "Giac's own functions are not exported again by Commands" begin
    # `using Giac, Giac.Commands` must not make `taylor` ambiguous: Commands keeps GIAC's command
    # under its qualified name and does not export it
    @test !Base.isexported(Giac.Commands, :taylor)
    @test Base.isexported(Giac.Commands, :series)
    @giac_var x
    @test occursin("order_size", string(Giac.Commands.taylor(sin(x), x, 3)))   # GIAC's taylor
    @test string(taylor(sin(x), x, 3)) == "x-x^3/6"
end
