# Kronecker products and vectorization of linear matrix equations.
# Ported from Kahli Burke's `ergonomics` branch (test/test_kronecker.jl); LaTeX is read through
# `show` with the `text/latex` MIME type instead of the unported `giac_latex`.

@testset "Kronecker products" begin
    @matsym A[n, n] B[m, m] C[n, n] D[m, m] E[n, n] F[m, m] P[n, n]::symmetric X[n, m] S[n, n]::skew
    T(M) = sprint(show, M)
    L(e) = (s = sprint(show, MIME("text/latex"), e); chop(s; head = 2, tail = 2))

    @testset "the algebra" begin
        @test size(kron(A, B)) == (Symbol("m*n"), Symbol("m*n"))
        @test T(kron(A, B) * kron(C, D)) == "kron(A*C, B*D)"               # the mixed product
        @test T(kron(A, B)') == "kron(A', B')"
        @test T(inv(kron(A, B))) == "kron(inv(A), inv(B))"
        @test T(inv(kron(A, B)) * kron(A, B)) == "I"
        @test T(kron(A + C, 2B)) == "2*kron(A, B) + 2*kron(C, B)"          # bilinear
        @test T(kron(S, A)') == "-kron(S, A')"
        @test T(tr(kron(A, B))) == "tr(A)*tr(B)"
        @test T(det(kron(A, B))) == "det(A)^m*det(B)^n"
        @test T(differential(kron(A, B))) == "kron(A, dB) + kron(dA, B)"
    end

    @testset "sizes that are products" begin
        @matsym Y[m*n, m*n]
        @test size(Y) == size(kron(A, B)) && size(Y * kron(B, A)) == size(Y)
        @test size(vec(X)) == (Symbol("m*n"), 1)
        @test_throws DimensionMismatch Y * A
    end

    @testset "vectorizing linear matrix equations" begin
        K, R = vectorize(A' * P + P * A, P)
        @test T(K) == "kron(A', I) + kron(I, A')" && iszero(R)
        @test T(vectorize(E * X + X * F, X).K) == "kron(F', I) + kron(I, E)"
        K2, R2 = vectorize(A * X * B + C * C * X, X)
        @test T(K2) == "kron(B', A) + kron(I, C^2)" && iszero(R2)
        @test T(vectorize(A * P + C, P).R) == "C"
        @test_throws ArgumentError vectorize(P * A * P, P)
        @test T(vectorize(A * E' * C, E).K) == "kron(C', A)*K(n, n)"        # a transpose, through K
        @test L(K) == "A^{\\top} \\otimes I + I \\otimes A^{\\top}"
    end

    @testset "explicit: the Lyapunov equation as a linear system" begin
        K, _ = vectorize(A' * P + P * A, P)
        A₂ = GiacExpr[0 1; -2 -3]
        K₂ = substitute(K, A => A₂)
        @test size(K₂) == (4, 4)
        P₂ = reshape(Giac.Commands.simplify.(K₂ \ (-vec(GiacExpr[1 0; 0 1]))), 2, 2)
        @test string.(P₂) == ["5/4" "1/4"; "1/4" "1/4"]
        @test P₂ * A₂ + A₂' * P₂ == -GiacExpr[1 0; 0 1]
        @test string(substitute(tr(kron(A, B)), A => A₂, B => GiacExpr[1 2; 3 4])) == "-15"
        # with vech unknowns: three for n = 2
        L₂ = substitute(vectorize(A' * P + P * A, P; unknowns = :vech).K, A => A₂)
        @test size(L₂) == (3, 3)
        @test string.(Giac.Commands.simplify.(L₂ \ (-GiacExpr[1, 0, 1]))) == ["5/4", "1/4", "1/4"]
        @test_throws ArgumentError vectorize(A * P, P; unknowns = :vech)          # not symmetric
    end

    @testset "commutation and duplication matrices" begin
        K(a, b) = Giac.commutation(a, b)
        D, Dp = Giac.duplication(:n), Giac.duplication_plus(:n)
        @matsym G[m, n] H[p, q]
        @test T(K(:m, :n)') == "K(n, m)" && T(inv(K(:m, :n))) == "K(n, m)"
        @test T(K(:m, :n) * K(:n, :m)) == "I" && T(K(1, :n)) == "I" && T(K(:n, :n)^2) == "I"
        @test T(K(:p, :m) * kron(G, H)) == "kron(H, G)*K(q, n)"           # K moves past ⊗
        @test T(K(:p, :m) * kron(G, H) * K(:n, :q)) == "kron(H, G)"
        @test T(Dp * D) == "I" && T(K(:n, :n) * D) == "D(n)" && T(Dp * K(:n, :n)) == "Dplus(n)"
        @test T(tr(K(:n, :n))) == "n" && T(det(K(2, 3))) == "-1"
        @test size(D) == (Symbol("n*n"), Symbol("(n+1)/2*n")) && size(vech(P)) == (Symbol("(n+1)/2*n"), 1)
        @test_throws ArgumentError vech(A)
        @test L(Dp * kron(A, C) * D) == "D_{n}^{+} \\left(A \\otimes C\\right) D_{n}"
        # the explicit matrices
        @matsym G3[m, n] P3[n, n]::symmetric
        X₂, P₂ = GiacExpr[1 2 3; 4 5 6], GiacExpr[1 2; 2 3]
        @test substitute(K(:m, :n), G3 => X₂) * vec(X₂) == vec(permutedims(X₂))
        D₂, Dp₂ = substitute(D, P3 => P₂), substitute(Dp, P3 => P₂)
        @test D₂ * GiacExpr[1, 2, 3] == vec(P₂) && Dp₂ * vec(P₂) == GiacExpr[1, 2, 3]
        C₂, F₂, E₂ = GiacExpr[1 2; 3 4], GiacExpr[0 1; 1 1], GiacExpr[5 6; 7 8]
        Kt = substitute(vectorize(C * E' * A, E).K, C => C₂, A => F₂, E => E₂)
        @test Kt * vec(E₂) == vec(C₂ * permutedims(E₂) * F₂)
    end
end
