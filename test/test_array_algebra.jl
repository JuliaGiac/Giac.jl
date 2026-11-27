# Symbolic linear algebra on Julia arrays of GiacExpr, and GiacMatrix as an AbstractMatrix.
# Ported from Kahli Burke's `ergonomics` branch (test/test_array_algebra.jl).

@testset "Array algebra" begin
    @giac_var a11 a12 a21 a22 x1 x2
    A = [a11 a12; a21 a22]
    x = [x1, x2]

    @testset "GiacMatrix is an AbstractMatrix{GiacExpr}" begin
        M = GiacMatrix(A)
        @test M isa AbstractMatrix{GiacExpr}
        @test eltype(M) === GiacExpr && size(M) == (2, 2) && length(M) == 4
        @test string.(M[:, 1]) == ["a11", "a21"]          # slicing
        @test string.(M[2, :]) == ["a21", "a22"]
        @test string(M[3]) == "a12"                       # linear indexing, column-major
        @test string.(Matrix(M)) == string.(A)
        @test Matrix(M) isa Matrix{GiacExpr}
        @test string.(2 .* M) == ["2*a11" "2*a12"; "2*a21" "2*a22"]   # broadcasting
        # functions Julia's array code relies on keep their generic meaning
        @test axes(M) == (Base.OneTo(2), Base.OneTo(2))
        @test string.(reverse(M; dims = 1)) == ["a21" "a22"; "a11" "a12"]
        @test rank(M) == 2
    end

    @testset "UniformScaling" begin
        @test string.(A + I) == ["a11+1" "a12"; "a21" "a22+1"]
        @test string.(I + A) == string.(A + I)
        @test string.(A - 2I) == ["a11-2" "a12"; "a21" "a22-2"]
        @test string.(3I - A) == ["-a11+3" "-a12"; "-a21" "-a22+3"]
        @test_throws DimensionMismatch [a11 a12] + I
    end

    @testset "block matrices" begin
        @giac_var b1 b2 d
        Z = zeros(GiacExpr, 2, 2)
        @test string.([A I; I A']) ==
              ["a11" "a12" "1" "0"; "a21" "a22" "0" "1"; "1" "0" "a11" "a21"; "0" "1" "a12" "a22"]
        @test string.([A Z; Z A])[1, 3] == "0"
        @test size([A [b1, b2]; [b1 b2] d]) == (3, 3)
        @test string(Giac.Commands.factor(det([A Z; Z A]))) == string(Giac.Commands.factor(det(A)^2))
        # Julia's `true` is the integer 1; Giac's logical constant is giac_eval("true")
        @test string(convert(GiacExpr, true)) == "1" && string(x1 + true) == "x1+1"
    end

    @testset "det, inv and \\ hand off to Giac" begin
        @test string(det(A)) == "a11*a22-a12*a21"
        Ainv = inv(A)
        @test Ainv isa Matrix{GiacExpr}
        @test string.(Giac.Commands.simplify.(A * Ainv)) == ["1" "0"; "0" "1"]
        sol = A \ x
        @test string.(Giac.Commands.simplify.(A * sol - x)) == ["0", "0"]
    end

    @testset "symbolic scalars with arrays and I" begin
        @giac_var s t
        @test string.(s * I - A) == ["-a11+s" "-a12"; "-a21" "-a22+s"]
        @test string.(A - I * s) == ["a11-s" "a12"; "a21" "a22-s"]
        @test string(det(s * I - GiacExpr[0 1; -2 -3])) == "s^2+3*s+2"
        @test string.(t * x) == ["t*x1", "t*x2"]
        @test string.([1 2] * t) == ["t" "2*t"]
        @test string.(x / t) == ["x1/t", "x2/t"]
    end

    @testset "5-argument mul!" begin
        @giac_var s
        C = zeros(GiacExpr, 2, 2)
        mul!(C, A, GiacExpr[1 0; 0 1], one(GiacExpr), zero(GiacExpr))
        @test string.(C) == string.(A)
        mul!(C, A, GiacExpr[1 0; 0 1], s, one(GiacExpr))
        @test string.(Giac.Commands.factor.(C)) == string.(Giac.Commands.factor.((s + 1) .* A))
    end

    @testset "spectra, rank, null space, exp" begin
        @giac_var t k
        M = GiacExpr[0 1; -2 -3]
        @test string.(eigvals(M)) == ["-2", "-1"]                    # by real part, then imaginary
        @test [imag(to_julia(Giac.Commands.evalf(l))) for l in eigvals(GiacExpr[0 1; -1 -1])] ≈
              [-sqrt(3) / 2, sqrt(3) / 2]
        E = eigen(M)
        @test all(iszero, Giac.Commands.simplify.(M * E.vectors - E.vectors * Diagonal(E.values)))
        @test eigvecs(M) == E.vectors
        @test E.values == eigvals(M)
        @test length(eigvals(GiacExpr[0 1; -k -3])) == 2
        @test string.(eigvals(GiacExpr[1 1; 0 1])) == ["1", "1"]
        @test_throws ArgumentError eigen(GiacExpr[1 1; 0 1])     # not diagonalizable
        @test rank(M) == 2 && rank(GiacExpr[1 2; 2 4]) == 1
        N = nullspace(GiacExpr[1 2; 2 4])
        @test size(N) == (2, 1) && all(iszero, GiacExpr[1 2; 2 4] * N)
        @test size(nullspace(M)) == (2, 0)
        Φ = exp(M * t)
        @test string(Φ[1, 1]) == "2*exp(-t)-exp(-2*t)"
        @test all(iszero, Giac.Commands.simplify.(map(e -> Giac.Commands.diff(e, t), Φ) - M * Φ))   # Φ' = MΦ
    end

    @testset "a Giac matrix stays one" begin
        σz, σx = GiacMatrix([1 0; 0 -1]), GiacMatrix([0 1; 1 0])
        up, dn = GiacMatrix(reshape([1, 0], 2, 1)), GiacMatrix(reshape([0, 1], 2, 1))
        @giac_var θ
        σθ = cos(θ) * σz + sin(θ) * σx
        @test σθ isa GiacMatrix && σz * θ isa GiacMatrix && -σz isa GiacMatrix
        @test σz / 2 isa GiacMatrix && string.(Matrix(σz / 2)) == ["1/2" "0"; "0" "-1/2"]   # exact
        @test σz / θ isa GiacMatrix
        @test σz + I isa GiacMatrix && string.(Matrix(σz + I)) == ["2" "0"; "0" "0"]
        @test I - σz isa GiacMatrix
        ψ = (kron(up, dn) - kron(dn, up)) / sqrt(GiacExpr(2))
        @test ψ isa GiacMatrix && size(ψ) == (4, 1)
        @test size(kron(σz, up)) == (4, 2)
        # a command takes a Julia matrix of expressions as it takes a Giac matrix
        @test string(Giac.Commands.eigenvalues(Matrix(σθ))) == string(Giac.Commands.eigenvalues(σθ))
    end

    @testset "generic Julia operations" begin
        @test string(Giac.Commands.expand(x' * A * x)) ==
              string(Giac.Commands.expand(a11 * x1^2 + (a12 + a21) * x1 * x2 + a22 * x2^2))
        @test A' isa LinearAlgebra.Adjoint
        @test string.(A[:, 1]) == ["a11", "a21"]
    end
end

@testset "vector calculus" begin
    @giac_var w1 w2 k
    w = [w1, w2]
    f = w1^2 * w2 + k * w2
    @test string.(∇(f, w)) == ["2*w1*w2", "w1^2+k"]
    @test string.(hessian(f, w)) == ["2*w2" "2*w1"; "2*w1" "0"]
    @test string.(jacobian([w1 * w2, w1 + w2], w)) == ["w2" "w1"; "1" "1"]
    @test size(jacobian([w1, w2, k * w1], w)) == (3, 2)
end
