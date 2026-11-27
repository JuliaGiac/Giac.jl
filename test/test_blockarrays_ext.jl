# Block matrices of expressions with BlockArrays.jl (GiacBlockArraysExt), and the scalar
# behaviour they rely on. Ported from Kahli Burke's `ergonomics` branch; the partition lines in
# LaTeX come later, with the typesetting.

using BlockArrays
using LinearAlgebra

@testset "symbolic scalars in broadcasting and 5-argument mul!" begin
    @giac_var t
    @test all(iszero, Giac.Commands.expand.(t .* [1, 2] - [t, 2t]))   # t is a scalar in broadcasting
    C = Matrix{GiacExpr}(undef, 2, 2)
    A = GiacExpr[1 2; 3 4]
    mul!(C, A, A, one(GiacExpr), zero(GiacExpr))
    @test string.(C) == string.(A * A)
    mul!(C, A, A, t, one(GiacExpr))                    # C = t A² + C
    @test string.(Giac.Commands.expand.(C - (t .+ 1) .* (A * A))) == ["0" "0"; "0" "0"]
end

@testset "BlockArrays" begin
    @giac_matrix A[2, 2]
    @giac_var b[1:2] d
    M = BlockArray([A I; I A'], [2, 2], [2, 2])
    @test string.(M[Block(1, 2)]) == ["1" "0"; "0" "1"]
    # products of conforming block matrices work and keep the partition
    MM = M * M
    @test MM isa BlockMatrix && blocksize(MM) == (2, 2)
    @test all(iszero, Giac.Commands.expand.(Matrix(MM) - Matrix(M) * Matrix(M)))
    K = BlockArray([A b; transpose(b) d], [2, 1], [2, 1])
    @test blocksize(K * K) == (2, 2)
    v = BlockArray([b; d], [2, 1])
    @test blocksize(K * v) == (2,)
    @test all(iszero, Giac.Commands.expand.(Vector(K * v) - Matrix(K) * Vector(v)))
end
