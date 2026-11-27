# @giac_matrix: matrices of symbolic entries, with a structure (symmetric, skew, diagonal,
# triangular), properties (posdef, negdef) and assumptions on the entries.
# Structures ported from Kahli Burke's `ergonomics` branch; the syntax is the one agreed with
# MathInterchange (`@giac_matrix P[n, n] [posdef]`), with the names of `@giac_var` arrays.

@testset "@giac_matrix" begin
    S = string

    @testset "a general matrix" begin
        @giac_matrix A[2, 3]
        @test A isa Matrix{GiacExpr} && size(A) == (2, 3)
        @test S.(A) == ["A₁_₁" "A₁_₂" "A₁_₃"; "A₂_₁" "A₂_₂" "A₂_₃"]
        n = 2
        @giac_matrix B[n, n]                       # sizes are evaluated where the macro is called
        @test size(B) == (2, 2)
        @giac_matrix C[0:1, 0:1]                   # ranges give the indices
        @test S(C[1, 2]) == "C₀_₁"
    end

    @testset "structures" begin
        @giac_matrix W[3, 3] [skew] D[2, 2] [diagonal] U[2, 2] [upper] L[2, 2] [lower] P[2, 2] [symmetric]
        @test S.(W) == ["0" "W₁_₂" "W₁_₃"; "-W₁_₂" "0" "W₂_₃"; "-W₁_₃" "-W₂_₃" "0"]
        @test S.(D) == ["D₁_₁" "0"; "0" "D₂_₂"]
        @test S.(U) == ["U₁_₁" "U₁_₂"; "0" "U₂_₂"]
        @test S.(L) == ["L₁_₁" "0"; "L₂_₁" "L₂_₂"]
        @test S.(P) == ["P₁_₁" "P₁_₂"; "P₁_₂" "P₂_₂"]
        @test P[1, 2] == P[2, 1]
        # a quadratic form with a skew matrix vanishes
        @giac_var z[1:3]
        @test S(Giac.Commands.normal(transpose(z) * W * z)) == "0"
        # the structure is written either way
        @giac_matrix Q[2, 2]::symmetric
        @test S.(Q) == ["Q₁_₁" "Q₁_₂"; "Q₁_₂" "Q₂_₂"]
        @test Giac.matrix_properties(W) == Set([:skew])
        @test Giac.matrix_properties(Q) == Set([:symmetric])
        @test isempty(Giac.matrix_properties(GiacExpr[1 2; 3 4]))
    end

    @testset "assumptions on the entries" begin
        @giac_matrix V[2, 2] [upper, real]
        @test S(Giac.Commands.about(V[1, 2])) == "assume[real,[],[]]" ||
              occursin("real", S(Giac.Commands.about(V[1, 2])))
        @giac_matrix Y[2, 2]::positive
        @test occursin("line[0,+infinity]", S(Giac.Commands.about(Y[2, 1])))
        # declaring again resets the entries
        @giac_matrix Y[2, 2]
        @test S(Giac.Commands.about(Y[2, 1])) == "Y₂_₁"
    end

    @testset "posdef and negdef" begin
        @giac_matrix P[2, 2] [posdef]
        @test S.(P) == ["P₁_₁" "P₁_₂"; "P₁_₂" "P₂_₂"]          # symmetric
        @test occursin("line[0,+infinity]", S(Giac.Commands.about(P[1, 1])))   # diagonal entries > 0
        @test S(Giac.Commands.about(P[1, 2])) == "P₁_₂"                          # the others are free
        @test Giac.matrix_properties(P) == Set([:symmetric, :posdef])
        @giac_matrix N[2, 2] [negdef]
        @test occursin("line[-infinity,0]", S(Giac.Commands.about(N[2, 2])))
        @giac_matrix E[2, 2] [diagonal, posdef]
        @test S.(E) == ["E₁_₁" "0"; "0" "E₂_₂"]
        @test Giac.matrix_properties(E) == Set([:diagonal, :posdef])
    end

    @testset "errors" begin
        @test_throws ArgumentError @macroexpand @giac_matrix M
        @test_throws ArgumentError @macroexpand @giac_matrix M[2, 2] [wobbly]
        @test_throws ArgumentError @macroexpand @giac_matrix M[2, 2] [symmetric, skew]
        @test_throws ArgumentError @macroexpand @giac_matrix M[2, 2, 2]
        @test_throws ArgumentError @giac_matrix M[2, 3] [symmetric]          # not square
        @test_throws ArgumentError @giac_matrix M[2, 2] [upper, posdef]      # posdef needs symmetry
    end
end
