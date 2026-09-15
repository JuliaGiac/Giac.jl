# Tests for GiacMatrix iteration and linear indexing (PR #10 by @jverzani)
# Covers: Base.iterate, Base.length, Base.LinearIndices, Base.CartesianIndices,
# linear getindex M[i], and Cartesian-index getindex M[CartesianIndex(i, j)].
# Iteration order is column-major (matching Julia's standard convention).

@testset "GiacMatrix iteration & linear indexing (PR #10)" begin

    # ========================================================================
    # length: total number of entries (rows * cols)
    # ========================================================================

    @testset "length" begin
        @giac_var x y
        M23 = GiacMatrix([x   y   x+y;
                          2*x 2*y x*y])
        M11 = GiacMatrix([x;;])              # 1x1
        M31 = GiacMatrix([x, 2*x, x^2])      # 3x1 column vector

        @test length(M23) == 6
        @test length(M11) == 1
        @test length(M31) == 3
        # length always equals prod(size).
        @test length(M23) == prod(size(M23))
    end

    # ========================================================================
    # iteration: column-major order (matches Julia matrix convention)
    # for 2x3 matrix, entries are visited as
    #   M[1,1], M[2,1], M[1,2], M[2,2], M[1,3], M[2,3]
    # ========================================================================

    @testset "iterate (column-major)" begin
        @giac_var x y
        M = GiacMatrix([x   y   x+y;
                        2*x 2*y x*y])

        collected = collect(M)
        @test length(collected) == 6
        # Column-major order:
        @test string(collected[1]) == string(M[1, 1])   # x
        @test string(collected[2]) == string(M[2, 1])   # 2*x
        @test string(collected[3]) == string(M[1, 2])   # y
        @test string(collected[4]) == string(M[2, 2])   # 2*y
        @test string(collected[5]) == string(M[1, 3])   # x+y
        @test string(collected[6]) == string(M[2, 3])   # x*y
    end

    @testset "iterate via for-loop with enumerate" begin
        @giac_var x
        M = GiacMatrix([x x+1; 2*x x^2])
        seen = String[]
        for (i, e) in enumerate(M)
            push!(seen, "$i:" * string(e))
        end
        # Column-major: M[1,1], M[2,1], M[1,2], M[2,2]
        @test seen == ["1:x", "2:2*x", "3:x+1", "4:x^2"]
    end

    @testset "iterate on 1x1 and column vector" begin
        @giac_var x
        M11 = GiacMatrix([x;;])
        @test_broken collect(M11) == [M11[1, 1]]   # one element
        @test [x] == [M11[1, 1]]   # one element

        V31 = GiacMatrix([x, 2*x, x^2])     # 3x1
        v = collect(V31)
        @test length(v) == 3
        @test string(v[1]) == "x"
        @test string(v[2]) == "2*x"
        @test string(v[3]) == "x^2"
    end

    # ========================================================================
    # Linear getindex M[i]: column-major
    # ========================================================================

    @testset "linear getindex M[i]" begin
        @giac_var x y
        M = GiacMatrix([x   y   x+y;
                        2*x 2*y x*y])
        # Column-major linear order:
        @test string(M[1]) == string(M[1, 1])
        @test string(M[2]) == string(M[2, 1])
        @test string(M[3]) == string(M[1, 2])
        @test string(M[4]) == string(M[2, 2])
        @test string(M[5]) == string(M[1, 3])
        @test string(M[6]) == string(M[2, 3])
    end

    @testset "linear getindex on a column vector" begin
        @giac_var x
        V = GiacMatrix([x, 2*x, x^2])   # 3x1
        @test string(V[1]) == "x"
        @test string(V[2]) == "2*x"
        @test string(V[3]) == "x^2"
    end

    # ========================================================================
    # LinearIndices(M) / CartesianIndices(M)
    # ========================================================================

    @testset "LinearIndices(M)" begin
        @giac_var x
        M = GiacMatrix([x x+1 x^2; 2*x x^2 x^3])
        LI = LinearIndices(M)
        @test size(LI) == size(M)
        # Column-major numbering:
        @test LI[1, 1] == 1
        @test LI[2, 1] == 2
        @test LI[1, 2] == 3
        @test LI[2, 2] == 4
        @test LI[1, 3] == 5
        @test LI[2, 3] == 6
    end

    @testset "CartesianIndices(M)" begin
        @giac_var x
        M = GiacMatrix([x x+1 x^2; 2*x x^2 x^3])
        CI = CartesianIndices(M)
        @test size(CI) == size(M)
        # Column-major: linear index 1..6 maps to (1,1),(2,1),(1,2),(2,2),(1,3),(2,3)
        @test CI[1] == CartesianIndex(1, 1)
        @test CI[2] == CartesianIndex(2, 1)
        @test CI[3] == CartesianIndex(1, 2)
        @test CI[4] == CartesianIndex(2, 2)
        @test CI[5] == CartesianIndex(1, 3)
        @test CI[6] == CartesianIndex(2, 3)
    end

    @testset "M[CartesianIndex(i, j)]" begin
        @giac_var x y
        M = GiacMatrix([x   y   x+y;
                        2*x 2*y x*y])
        @test string(M[CartesianIndex(1, 1)]) == "x"
        @test string(M[CartesianIndex(2, 3)]) == "x*y"
        # Cartesian-index access agrees with two-arg getindex.
        for i in 1:M.rows, j in 1:M.cols
            @test string(M[CartesianIndex(i, j)]) == string(M[i, j])
        end
    end

    @testset "linear index via LinearIndices is consistent with M[i]" begin
        @giac_var x y
        M = GiacMatrix([x   y   x+y;
                        2*x 2*y x*y])
        LI = LinearIndices(M)
        for i in 1:M.rows, j in 1:M.cols
            @test string(M[LI[i, j]]) == string(M[i, j])
        end
    end
end
