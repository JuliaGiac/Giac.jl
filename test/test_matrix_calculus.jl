# Matrix calculus: differentials, gradients, Jacobians, Hessians, derivatives along a direction.
# Ported from Kahli Burke's `ergonomics` branch (test/test_matrix_calculus.jl); LaTeX is read
# through `show` with the `text/latex` MIME type instead of the unported `giac_latex`.

@testset "Matrix calculus" begin
    @matsym X[n, n] Y[n, n] A[n, n] W[n, n] P[n, n]::posdef x[n] b[n]
    S(M) = sprint(show, M)
    L(e) = (s = sprint(show, MIME("text/latex"), e); chop(s; head = 2, tail = 2))

    @testset "differentials" begin
        @test S(differential(X * Y)) == "X*dY + dX*Y"
        @test S(differential(X^2)) == "X*dX + dX*X"
        @test S(differential(inv(X))) == "-inv(X)*dX*inv(X)"
        @test S(differential(tr(A * X), X)) == "tr(A*dX)"
        @test S(differential(det(X))) == "det(X)*tr(inv(X)*dX)"
        @test S(differential(x' * A * x, x)) == "dx'*A*x + x'*A*dx"
        @test iszero(differential(A * x, X))                          # X does not appear
        @test L(differential(inv(X))) == "-X^{-1} \\mathrm{d}X X^{-1}"
    end

    @testset "scalar variables and matrices together" begin
        @giac_var u v
        @test S(differential(u^2 + tr(A * X), u, X)) == "2*u*du+tr(A*dX)"
        @test isequal(differential(u^2 + tr(A * X)), 2u * differential(u) + differential(tr(A * X)))   # everything varies
        @test S(differential(u * det(X), u, X)) == "det(X)*du+u*det(X)*tr(inv(X)*dX)"
        @test S(differential(u * v)) == "v*du+u*dv" && S(differential(u)) == "du"
    end

    @testset "gradients" begin
        @test S(∇(tr(A * X), X)) == "A'"
        @test S(∇(det(X), X)) == "det(X)*inv(X')"
        @test S(∇(log(det(X)), X)) == "inv(X')"
        @test S(∇(tr(X' * A * X), X)) == "A'*X + A*X"
        @test ∇(x' * W * x + b' * x, x) == (W + W') * x + b
    end

    @testset "Jacobians and Hessians" begin
        @test S(jacobian(A * x, x)) == "A"
        @test S(jacobian(inv(X) * x, x)) == "inv(X)"
        @test S(jacobian((x' * x) * b, x)) == "2*b*x'"
        @test S(hessian(x' * W * x, x)) == "W + W'"
        H = hessian(x' * A * x * (b' * x), x)
        @test H == H'                                                  # a Hessian is symmetric
    end

    @testset "derivatives along a direction" begin
        V̇ = derivative(x' * P * x, x => A * x)
        @test S(V̇) == "2*x'*P*A*x"
        @test S(quadratic_form(V̇, x)) == "A'*P + P*A"               # the Lyapunov matrix
        @test S(derivative(x' * P * x, x => A * x, P => W)) == "x'*W*x + 2*x'*P*A*x"
        @test S(derivative(tr(X * X), X => A)) == "2*tr(A*X)"
        @test_throws ArgumentError derivative(x' * x)
        @test_throws DimensionMismatch derivative(x' * x, x => A)
    end

    @testset "a 1×1 factor is a scalar" begin
        @test S((x' * x) * b) == "(x'*x)*b"
        @test_throws DimensionMismatch A * b'
    end
end
