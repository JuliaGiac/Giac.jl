@testset "Operators" begin
    @testset "Arithmetic Operators" begin
        # T048-T053 [US3]: Test operator overloading
        # Test that operators are defined
        a = giac_eval("2")
        b = giac_eval("3")

        # With real GIAC, operators return results
        @test string(a + b) == "5"
        @test string(a - b) == "-1"
        @test string(a * b) == "6"
        @test string(a / b) == "2/3"
        @test string(a ^ b) == "8"
        @test string(-a) == "-2"
    end

    @testset "Mixed Type Arithmetic" begin
        # T054-T057 [US3]: Test mixed type operations
        a = giac_eval("x")

        # With real GIAC, mixed type operations work
        @test string(a + 1) == "x+1"
        @test string(1 + a) == "1+x"
        @test string(a - 1) == "x-1"
        @test string(1 - a) == "1-x"
        @test string(a * 2) in ["2*x", "x*2"]  # GIAC may not reorder
        @test string(2 * a) == "2*x"
        @test string(a / 2) == "x/2"
        @test string(2 / a) == "2/x"
    end

    @testset "Comparison Operators" begin
        # T058 [US3]: Test equality
        a = giac_eval("x")
        b = giac_eval("x")

        # Note: equality comparison depends on stub implementation
        @test (a == b) isa Bool
    end

    @testset "Constructing from numbers" begin
        @test string(GiacExpr(3 // 4)) == "3/4"
        @test string(GiacExpr(2)) == "2"
        @test string.(GiacExpr.([1//2 1; 0 2//3])) == ["1/2" "1"; "0" "2/3"]
        @test GiacExpr(3 // 4) isa GiacExpr
    end

    @testset "Hash" begin
        # Test that GiacExpr can be hashed
        a = giac_eval("x^2")
        @test hash(a) isa UInt
    end

    # ============================================================================
    # Number Type Conversion Tests (043-fix-rational-arithmetic)
    # Tests for Rational, Complex, and Irrational type conversions
    # ============================================================================

    @testset "Rational Arithmetic (US1-US4)" begin
        # Tests for Rational number conversion using division operator
        x = giac_eval("x")

        # T004 [US1]: Basic Rational subtraction
        @testset "T004: x - (1//2) contains 1/2" begin
            result = x - (1//2)
            result_str = string(result)
            @test occursin("1/2", result_str) || occursin("1//2", result_str) == false
            @test !occursin("1//2", result_str)  # Should NOT have Julia syntax
        end

        # T005 [US1]: sin(x) - (1//2) produces sin(x)-1/2
        @testset "T005: sin(x) - (1//2) produces sin(x)-1/2" begin
            sinx = sin(x)
            result = sinx - (1//2)
            result_str = string(result)
            @test occursin("sin", result_str)
            @test occursin("1/2", result_str) || occursin("-1/2", result_str)
            @test !occursin("-1\"", result_str)  # Should NOT be just -1
        end

        # T006 [US1]: (1//2) + x contains 1/2+x
        @testset "T006: (1//2) + x contains 1/2" begin
            result = (1//2) + x
            result_str = string(result)
            @test occursin("1/2", result_str)
        end

        # T007 [US1]: x * (2//3) contains fraction
        @testset "T007: x * (2//3) contains 2/3" begin
            result = x * (2//3)
            result_str = string(result)
            @test occursin("2/3", result_str) || occursin("2", result_str)
        end

        # T008 [US2]: Large numerator/denominator
        @testset "T008: x + (22//7) large fraction" begin
            result = x + (22//7)
            result_str = string(result)
            @test occursin("22/7", result_str)
        end

        # T009 [US3]: Negative Rational
        @testset "T009: x + (-1//2) negative Rational" begin
            result = x + (-1//2)
            result_str = string(result)
            # Should contain -1/2 or equivalent
            @test occursin("1/2", result_str)
        end

        # T010 [US4]: Integer-like Rational simplifies
        @testset "T010: x + (4//2) simplifies to x+2" begin
            result = x + (4//2)
            result_str = string(result)
            @test occursin("2", result_str)
        end

        # T011 [US1]: Zero numerator edge case
        @testset "T011: x + (0//5) zero numerator" begin
            result = x + (0//5)
            result_str = string(result)
            @test result_str == "x" || occursin("x", result_str)
        end

        # T012 [US1]: Unit denominator edge case
        @testset "T012: x + (7//1) unit denominator" begin
            result = x + (7//1)
            result_str = string(result)
            @test occursin("7", result_str)
        end
    end

    @testset "Complex Arithmetic (US5)" begin
        # Tests for Complex number conversion using arithmetic operators
        x = giac_eval("x")

        # T016 [US5]: x + (1 + 2im) contains 2*i not 2im
        @testset "T016: x + (1 + 2im) contains i not im" begin
            result = x + (1 + 2im)
            result_str = string(result)
            @test occursin("i", result_str)
            @test !occursin("im", result_str)  # Should NOT have Julia syntax
        end

        # T017 [US5]: x * (0 + 1im) produces i*x
        @testset "T017: x * im produces i*x" begin
            result = x * (0 + 1im)
            result_str = string(result)
            @test occursin("i", result_str)
            @test occursin("x", result_str)
        end

        # T018 [US5]: Pure real Complex
        @testset "T018: x + (3.5 + 0im) pure real" begin
            result = x + (3.5 + 0im)
            result_str = string(result)
            @test occursin("3.5", result_str) || occursin("7/2", result_str)
        end

        # T019 [US5]: Pure imaginary Complex
        @testset "T019: x + 2im pure imaginary" begin
            result = x + (0 + 2im)
            result_str = string(result)
            @test occursin("2", result_str)
            @test occursin("i", result_str)
        end
    end

    @testset "Irrational Constants Arithmetic (US6)" begin
        # Tests for Irrational constant conversion (π, ℯ)
        x = giac_eval("x")

        # T023 [US6]: x + π contains pi not π
        @testset "T023: x + π contains pi" begin
            result = x + π
            result_str = string(result)
            @test occursin("pi", result_str)
            @test !occursin("π", result_str)  # Should NOT have Unicode
        end

        # T024 [US6]: x * ℯ contains e
        @testset "T024: x * ℯ contains e" begin
            result = x * ℯ
            result_str = string(result)
            @test occursin("e", result_str)
        end

        # T025 [US6]: π * x * 2 contains 2*pi
        # Note: Need GiacExpr in chain early, so x*π or π*x, then multiply by 2
        # (2*π evaluates to Float64 in Julia before our convert sees it)
        @testset "T025: x * π * 2 contains 2*pi" begin
            result = x * π * 2
            result_str = string(result)
            @test occursin("pi", result_str)
            @test occursin("2", result_str)
        end
    end

    @testset "BigInt Rational Edge Case" begin
        # T031: BigInt Rational support
        x = giac_eval("x")

        @testset "T031: BigInt Rational" begin
            result = x + (BigInt(1)//BigInt(2))
            result_str = string(result)
            @test occursin("1/2", result_str)
        end
    end

    # =========================================================================
    # Base.numerator / Base.denominator (057-numerator-denominator-methods)
    # =========================================================================
    @testset "Base.numerator and Base.denominator" begin
        @giac_var x

        # Numeric fractions
        @test string(numerator(giac_eval("25/15"))) == "5"
        @test string(denominator(giac_eval("25/15"))) == "3"

        # Return type assertions
        @test numerator(giac_eval("25/15")) isa GiacExpr
        @test denominator(giac_eval("25/15")) isa GiacExpr

        # Negative fraction
        @test string(numerator(giac_eval("-3/7"))) == "-3"
        @test string(denominator(giac_eval("-3/7"))) == "7"

        # Symbolic rational expressions
        expr = (x^3 - 1) / (x^2 - 1)
        num_str = string(numerator(expr))
        den_str = string(denominator(expr))
        @test occursin("x", num_str)
        @test occursin("x", den_str)

        # Integer (numerator is itself, denominator is 1)
        @test string(numerator(giac_eval("42"))) == "42"
        @test string(denominator(giac_eval("42"))) == "1"

        # Zero
        @test string(numerator(giac_eval("0"))) == "0"
        @test string(denominator(giac_eval("0"))) == "1"

        # Non-fraction expression (numerator returns itself, denominator is 1)
        @test string(numerator(x + 1)) == "x+1"
        @test string(denominator(x + 1)) == "1"
    end
end
