# Symbolic matrices (@matsym): products that do not commute, kept in a canonical form.
# Ported from Kahli Burke's `ergonomics` branch (test/test_matrix_symbols.jl). The testsets that need
# the rules engine (`Giac.Rules`: simplest, equivalent, rewrite, matrix_identities, is_positive,
# apply_relations) are not ported, nor is that engine; LaTeX is read through `show` with the
# `text/latex` MIME type, `giac_latex` being part of the unported presentation layer.

using LinearAlgebra

@testset "Matrix symbols" begin
    @matsym A[n, n] B[n, n] C[n, n] D[n, n] P[n, n]::posdef Q[n, n]::orthogonal W[n, n]::skew x[n] b[n] K[m, n]
    S = string
    Sh(e) = sprint(show, e)          # a trace or determinant shows as such (`string` keeps the name Giac has for it)
    L(e) = (s = sprint(show, MIME("text/latex"), e); chop(s; head = 2, tail = 2))      # the LaTeX within \$\$

    @testset "the algebra holds as expressions are built" begin
        @test (A * B)' == B' * A'
        @test S((A * B)') == "B'*A'"
        @test A * B != B * A
        @test S(inv(A * B)) == "inv(B)*inv(A)"
        @test S(A * inv(A)) == "I" && S(A^2 * inv(A)) == "A"
        @test P' == P && W' == -W
        @test S(Q' * Q) == "I" && S(inv(Q)) == "Q'"
        @test S((A + B)^2) == "A^2 + B^2 + A*B + B*A"
        @test S(inv(A + B)') == "inv((A' + B'))"
        @test S(inv(A + B) * (A + B)) == "I" && S((A + B) * inv(A + B) * C) == "C"
        @test S(2A - A - A) == "0" && iszero(2A - A - A)
        @test S(A + I) == "I + A" && S(3I * A) == "3*A"
        @test size(K) == (:m, :n) && size(x) == (:n, 1)
        @test_throws DimensionMismatch K * K
        @test_throws DimensionMismatch A + K
        @test_throws DimensionMismatch inv(K)
    end

    @testset "quadratic forms" begin
        V = x' * P * x
        Vdot = x' * A' * P * x + x' * P * A * x          # a 1×1 term is its own transpose
        @test S(Vdot) == "2*x'*P*A*x"
        @test quadratic_form(Vdot, x) == A' * P + P * A
        @test S(∇(V + b' * x, x)) == "b + 2*P*x"
        @test_throws ArgumentError quadratic_form(b' * x, x)
        @test iszero(∇(V, A)) && S(∇(Vdot, A)) == "2*P*x*x'"      # gradients in a matrix
    end

    @testset "trace and determinant" begin
        @test iszero(Giac.Commands.normal(tr(A * B) - tr(B * A)))
        @test Sh(tr(A * B * C)) == Sh(tr(C * A * B)) == Sh(tr(C' * B' * A')) == "tr(A*B*C)"
        @test Sh(tr(A * B * inv(A))) == "tr(B)" && S(tr(A * inv(A))) == "n"
        @test S(tr(W)) == "0"
        @test Sh(det(2 * A * B)) == "det(A)*det(B)*2^n"
        @test Sh(det(inv(A))) == "1/det(A)"
        @test occursin("\\operatorname{tr}", L(tr(A * B))) && occursin("\\det A", L(det(A)))
    end

    @testset "explicit matrices" begin
        @giac_matrix Ae[2, 2] Pe[2, 2]::symmetric          # (kb: `Pe[2, 2] symmetric`)
        @test substitute(A' * P + P * A, A => Ae, P => Pe) == Ae' * Pe + Pe * Ae
        @test substitute(tr(A * P), A => Ae, P => Pe) == tr(Ae * Pe)
        @test substitute(det(A) * tr(A * inv(A)), A => Ae) == 2det(Ae)
        @test_throws ArgumentError substitute(A * B, A => Ae)
        @test_throws DimensionMismatch substitute(A * B, A => Ae, B => [1 2 3; 4 5 6])
    end

    @testset "block matrices" begin
        X = [A B; C D]
        @test X isa Matrix{MatExpr}
        @test S.(X * X) == ["A^2 + B*C" "A*B + B*D"; "C*A + D*C" "D^2 + C*B"]
        @test S.([A I; 0 D]) == ["A" "I"; "0" "D"]
        @test S.(inv([A B; 0 D])) == ["inv(A)" "-inv(A)*B*inv(D)"; "0" "inv(D)"]
        @test S.(inv(X) * X) == ["I" "0"; "0" "I"]
        @test S.(X') == ["A'" "C'"; "B'" "D'"]
        @test occursin("\\begin{bmatrix}", sprint(show, MIME("text/latex"), X))
    end

    @testset "display" begin
        @test sprint(show, MIME("text/latex"), inv(A * B)' + 2 * Q' * C) == "\$\$A^{-\\top} B^{-\\top} + 2 Q^{\\top} C\$\$"
        @test occursin("tr(A*B)", sprint(show, tr(A * B)))
        # a coefficient whose text starts with a multibyte character (not on the ergonomics branch,
        # where it threw a StringIndexError)
        @giac_var θ
        @test S((θ + 1) * A) == "(θ+1)*A" && S(θ * A) == "θ*A"
        @test_throws ArgumentError Giac._declare_matsym(:Z, :n, :m, (:symmetric,))
        @test_throws ArgumentError Giac._declare_matsym(:Z, :n, :n, (:bouncy,))
    end

    @testset "a trace or determinant follows its symbols' sizes" begin
        @matsym F[n, m] G[m, n]
        d1 = det(I + F * G)
        @matsym F[3, 2] G[2, 3]
        d2 = det(I + F * G)
        @test string(d1) != string(d2)
    end
end
