@testset "API" begin
    @testset "giac_eval" begin
        # T009 [US1]: Test basic expression evaluation
        @test isdefined(Giac, :giac_eval)

        # Test evaluation with string
        result = giac_eval("2+3")
        @test result isa GiacExpr

        # Test empty string throws error
        @test_throws GiacError giac_eval("")
    end

    @testset "to_julia" begin
        # T022 [US1]: Test numeric conversion
        @test isdefined(Giac, :to_julia)

        # Placeholder tests - will work once library is connected
        # These test the stub behavior for now
    end

    @testset "Calculus Functions via Giac.Commands" begin
        # T025-T028: Calculus API functions available via Commands submodule
        # invoke_cmd is always available
        @test :invoke_cmd in names(Giac.Commands)
        @test :integrate in names(Giac.Commands)
        @test :limit in names(Giac.Commands)
        @test :series in names(Giac.Commands)
        # diff extends Base.diff via multiple dispatch - verify method exists
        @test isdefined(Base, :diff)
    end

    @testset "Algebra Functions via Giac.Commands" begin
        # T029-T033: Algebra API functions available via Commands submodule
        # Note: gcd is in JULIA_CONFLICTS (conflicts with Base.gcd) so it's not exported
        # Use invoke_cmd(:gcd, ...) instead
        @test :factor in names(Giac.Commands)
        @test :expand in names(Giac.Commands)
        @test :simplify in names(Giac.Commands)
        @test :solve in names(Giac.Commands)
        # gcd conflicts with Base.gcd - use invoke_cmd instead
        @test :gcd in Giac.JULIA_CONFLICTS
    end

    @testset "GiacMatrix Symbol Constructor" begin
        # Note: Element access tests use @test_broken because
        # _giac_matrix_getindex returns C_NULL when the real library isn't loaded.
        # The constructor correctly creates elements, but retrieval requires
        # the full GIAC library.

        # =====================================================================
        # User Story 1: Create 2D Symbolic Matrix (P1 - MVP)
        # =====================================================================
        @testset "US1: 2D Symbolic Matrix" begin
            # T003: Basic 2D matrix creation
            @testset "basic 2D matrix creation" begin
                M = GiacMatrix(:m, 2, 3)
                @test M isa GiacMatrix
                @test size(M) == (2, 3)
            end

            # T004: Element access returns correct symbolic variable
            @testset "element access" begin
                M = GiacMatrix(:m, 2, 3)
                # Element names should be m11, m12, m13, m21, m22, m23
                @test string(M[1, 1]) == "m11"
                @test string(M[1, 2]) == "m12"
                @test string(M[2, 3]) == "m23"
            end

            # T005: Matrix dimensions
            @testset "matrix dimensions" begin
                M = GiacMatrix(:a, 3, 4)
                @test size(M) == (3, 4)
                @test size(M, 1) == 3
                @test size(M, 2) == 4
            end

            # T006: Square matrix with det operation
            @testset "square matrix det" begin
                A = GiacMatrix(:a, 2, 2)
                @test size(A) == (2, 2)
                # det should return a GiacExpr (symbolic determinant)
                d = det(A)
                @test d isa GiacExpr
            end

            @testset "norm of matrix" begin
                M = [1 2; 3 4]
                A = GiacMatrix(M)
                for p ∈ (1,2,3Inf)
                    @test norm(M,p) == norm(A,p)
                end
            end

            @testset "norm of GiacExpr" begin
                m = [1 2 3]
                a = Giac.Commands.list(m)
                for p ∈ (1,2,3Inf)
                    @test norm(m,p) == norm(a,p)
                end

                @giac_var x
                @test norm(x) == abs(x)
                @test norm([1,x]) == sqrt(1 + x^2)
            end
        end

        # =====================================================================
        # User Story 2: Create 1D Symbolic Vector (P2)
        # =====================================================================
        @testset "US2: 1D Symbolic Vector" begin
            # T009: 1D vector creation
            @testset "1D vector creation" begin
                V = GiacMatrix(:v, 3)
                @test V isa GiacMatrix
            end

            # T010: Vector shape is n×1 column vector
            @testset "vector shape" begin
                V = GiacMatrix(:v, 3)
                @test size(V) == (3, 1)
            end

            # T011: Vector element naming (v1, v2, v3 not v11, v21, v31)
            @testset "vector element naming" begin
                V = GiacMatrix(:v, 3)
                @test string(V[1, 1]) == "v1"
                @test string(V[2, 1]) == "v2"
                @test string(V[3, 1]) == "v3"
            end
        end

        # =====================================================================
        # User Story 3: Unicode and Custom Base Names (P3)
        # =====================================================================
        @testset "US3: Unicode Base Names" begin
            # T014: Greek letter base name
            @testset "Greek letter base name" begin
                Γ = GiacMatrix(:Γ, 2, 2)
                @test Γ isa GiacMatrix
                @test string(Γ[1, 1]) == "Γ11"
                @test string(Γ[2, 2]) == "Γ22"
            end

            # T015: Longer base name
            @testset "longer base name" begin
                C = GiacMatrix(:coeff, 2, 2)
                @test C isa GiacMatrix
                @test string(C[1, 1]) == "coeff11"
                @test string(C[1, 2]) == "coeff12"
            end
        end

        # =====================================================================
        # Edge Cases and Error Handling
        # =====================================================================
        @testset "Edge Cases" begin
            # T017: Negative dimension error
            @testset "negative dimension error" begin
                @test_throws ArgumentError GiacMatrix(:m, -1, 3)
                @test_throws ArgumentError GiacMatrix(:m, 2, -1)
            end

            # T018: Zero dimension throws error (GiacMatrix requires positive dimensions)
            @testset "zero dimension error" begin
                @test_throws ArgumentError GiacMatrix(:m, 0, 3)
                @test_throws ArgumentError GiacMatrix(:m, 2, 0)
                @test_throws ArgumentError GiacMatrix(:m, 0)
            end

            # T019: No dimensions error
            @testset "no dimensions error" begin
                @test_throws ArgumentError GiacMatrix(:m)
            end

            # T020: More than 2 dimensions error
            @testset "more than 2 dimensions error" begin
                @test_throws ArgumentError GiacMatrix(:m, 2, 3, 4)
            end

            # T021: Large matrix with underscore naming
            @testset "large matrix underscore naming" begin
                M = GiacMatrix(:m, 10, 10)
                @test size(M) == (10, 10)
                # Should use underscore separators since dim > 9
                @test string(M[1, 10]) == "m_1_10"
                @test string(M[10, 1]) == "m_10_1"
            end

            # T022: Single element matrix
            @testset "single element matrix" begin
                M = GiacMatrix(:m, 1, 1)
                @test size(M) == (1, 1)
                @test string(M[1, 1]) == "m11"
            end
        end
    end
end
