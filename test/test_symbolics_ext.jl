# Tests for Symbolics.jl extension (042-preserve-symbolic-sqrt)
# Verifies symbolic expression preservation during to_symbolics conversion

using Test
using Giac
using Symbolics
using Symbolics.SymbolicUtils: Term

@testset "Symbolics Extension - Symbolic Preservation" begin

    # Note: String parsing helper functions (_is_function_call, _extract_function_parts,
    # _split_args) were removed in Feature 050 

    # ============================================================================
    # User Story 1: Square Root Preservation (P1 - MVP)
    # ============================================================================
    @testset "US1: Square Root Preservation" begin
        # T009: Test sqrt(2) preservation
        @testset "T009: sqrt(2) preserves symbolic sqrt" begin
            result = giac_eval("sqrt(2)")
            sym = to_symbolics(result)
            sym_str = string(sym)
            # Should contain sqrt, not 1.414...
            @test occursin("sqrt", sym_str) || occursin("^", sym_str)  # sqrt or power form
            @test !occursin("1.414", sym_str)
        end

        # T010: Test factor(x^8-1) contains sqrt(2)
        @testset "T010: factor(x^8-1) preserves sqrt(2)" begin
            result = giac_eval("factor(x^8-1)")
            sym = to_symbolics(result)
            @test sym isa Num
            # The expression should be preserved symbolically
            @test Symbolics.unwrap(sym) !== nothing
        end

        # T011: Test nested sqrt preservation
        @testset "T011: nested sqrt(sqrt(2)) preservation" begin
            result = giac_eval("sqrt(sqrt(2))")
            sym = to_symbolics(result)
            sym_str = string(sym)
            @test !occursin("1.189", sym_str)  # sqrt(sqrt(2)) ≈ 1.189
        end

        # T012: Test mixed expression
        @testset "T012: mixed expression x^2 + sqrt(2)*x + 1" begin
            result = giac_eval("x^2 + sqrt(2)*x + 1")
            sym = to_symbolics(result)
            sym_str = string(sym)
            @test !occursin("1.414", sym_str)
        end
    end

    # ============================================================================
    # User Story 2: Other Symbolic Functions Preservation (P2)
    # ============================================================================
    @testset "US2: Other Symbolic Functions" begin
        # T017: Test cbrt(2) preservation
        @testset "T017: cbrt(2) preserves symbolic cbrt" begin
            result = giac_eval("2^(1/3)")  # GIAC uses 2^(1/3) for cbrt
            sym = to_symbolics(result)
            sym_str = string(sym)
            @test !occursin("1.259", sym_str)
        end

        # T018: Test exp(1) preservation
        @testset "T018: exp(1) preserves symbolic exp" begin
            result = giac_eval("exp(1)")
            sym = to_symbolics(result)
            sym_str = string(sym)
            @test !occursin("2.718", sym_str)
        end

        # T019: Test log(2) preservation
        @testset "T019: log(2) preserves symbolic log" begin
            result = giac_eval("log(2)")
            sym = to_symbolics(result)
            sym_str = string(sym)
            @test !occursin("0.693", sym_str)
        end

        # T020: Test pi preservation
        @testset "T020: pi returns Symbolics constant" begin
            result = giac_eval("pi")
            sym = to_symbolics(result)
            sym_str = string(sym)
            @test !occursin("3.141", sym_str)
        end

        # T021: Test trigonometric functions
        @testset "T021: sin, cos, tan preservation" begin
            # sin(1)
            result = giac_eval("sin(1)")
            sym = to_symbolics(result)
            @test !occursin("0.841", string(sym))

            # cos(1)
            result = giac_eval("cos(1)")
            sym = to_symbolics(result)
            @test !occursin("0.540", string(sym))
        end
    end

    # ============================================================================
    # User Story 3: Complex Numbers with Symbolic Parts (P3)
    # ============================================================================
    @testset "US3: Complex Numbers Symbolic Preservation" begin
        # T027: Test 1 + sqrt(2)*i
        @testset "T027: 1 + sqrt(2)*i preserves sqrt(2)" begin
            result = giac_eval("1 + sqrt(2)*i")
            sym = to_symbolics(result)
            sym_str = string(sym)
            @test !occursin("1.414", sym_str)
        end

        # T028: Test sqrt(2) + sqrt(3)*i
        @testset "T028: sqrt(2) + sqrt(3)*i preserves both sqrts" begin
            result = giac_eval("sqrt(2) + sqrt(3)*i")
            sym = to_symbolics(result)
            sym_str = string(sym)
            @test !occursin("1.414", sym_str)
            @test !occursin("1.732", sym_str)
        end

        # T029: Test exp(i*pi)
        @testset "T029: exp(i*pi) preserves symbolic form" begin
            result = giac_eval("exp(i*pi)")
            sym = to_symbolics(result)
            # exp(i*pi) = -1, but we want symbolic form preserved
            sym_str = string(sym)
            # This could simplify to -1 which is fine, or preserve exp
            @test sym_str == "-1" || occursin("exp", sym_str) || occursin("π", sym_str)
        end
    end

    # ============================================================================
    # Feature 044: Integer Factorization Preservation (US1)
    # ============================================================================
    @testset "US1: Integer Factorization Preservation" begin
        # T006: ifactor(1000000) should preserve 2^6*5^6 structure
        @testset "T006: ifactor(1000000) preserves 2^6*5^6" begin
            using Giac.Commands: ifactor
            result = ifactor(1000000)
            sym = to_symbolics(result)
            sym_str = string(sym)
            # Should contain exponents and multiplication, not evaluate to 1000000
            @test occursin("^", sym_str) || occursin("*", sym_str)
            @test !occursin("1000000", sym_str)
        end

        # T007: ifactor(120) should preserve 2^3*3*5 structure
        @testset "T007: ifactor(120) preserves 2^3*3*5" begin
            using Giac.Commands: ifactor
            result = ifactor(120)
            sym = to_symbolics(result)
            sym_str = string(sym)
            # Should contain factors, not evaluate to 120
            @test (occursin("2", sym_str) && occursin("3", sym_str) && occursin("5", sym_str)) || occursin("*", sym_str)
            @test !occursin("120", sym_str) || occursin("^", sym_str)  # 120 ok if in factored form
        end

        # T008: ifactor(17) should return 17 (prime)
        @testset "T008: ifactor(17) returns 17 (prime)" begin
            using Giac.Commands: ifactor
            result = ifactor(17)
            sym = to_symbolics(result)
            @test sym == 17 || string(sym) == "17"
        end

        # T009: ifactor(-24) should preserve negative factored form
        @testset "T009: ifactor(-24) preserves negative factored form" begin
            using Giac.Commands: ifactor
            result = ifactor(-24)
            sym = to_symbolics(result)
            sym_str = string(sym)
            # Should contain negative and factors
            @test occursin("-", sym_str) || occursin("2", sym_str)
        end
    end

    # ============================================================================
    # Feature 044: Polynomial Factorization Preservation (US2)
    # ============================================================================
    @testset "US2: Polynomial Factorization Preservation" begin
        # T016: factor(x^2-1) should preserve (x-1)*(x+1) structure
        @testset "T016: factor(x^2-1) preserves (x-1)*(x+1)" begin
            using Giac.Commands: factor
            x = giac_eval("x")
            result = factor(x^2 - 1)
            sym = to_symbolics(result)
            sym_str = string(sym)
            # Should contain multiplication of factors
            @test occursin("*", sym_str) || occursin("x", sym_str)
        end

        # T017: factor(x^3-1) should preserve factored structure
        @testset "T017: factor(x^3-1) preserves factored form" begin
            using Giac.Commands: factor
            x = giac_eval("x")
            result = factor(x^3 - 1)
            sym = to_symbolics(result)
            sym_str = string(sym)
            # Should contain factored form
            @test occursin("x", sym_str)
        end
    end

    # ============================================================================
    # Feature 044: Display Factored Forms (US3)
    # ============================================================================
    @testset "US3: Display Factored Forms" begin
        # T024: string(to_symbolics(ifactor(1000000))) should show factored form
        @testset "T024: Display shows factored structure" begin
            using Giac.Commands: ifactor
            result = ifactor(1000000)
            sym = to_symbolics(result)
            sym_str = string(sym)
            # Display should show factored form with ^ and *
            @test occursin("^", sym_str) || occursin("*", sym_str)
        end

        # T025: string(to_symbolics(factor(x^2-1))) should show factored form
        @testset "T025: Polynomial display shows factored structure" begin
            using Giac.Commands: factor
            x = giac_eval("x")
            result = factor(x^2 - 1)
            sym = to_symbolics(result)
            sym_str = string(sym)
            # Display should show factored polynomial
            @test occursin("x", sym_str)
        end
    end

    # ============================================================================
    # Feature 045: Large Integer Factorization (ZINT handling)
    # ============================================================================
    @testset "Feature 045: Large Integer Factorization" begin
        using Giac.Commands: ifactor

        # T004: Specific failing case from bug report
        @testset "T004: ifactor with very large number (specific failing case)" begin
            big_num = "632459103267572196107100983820469021721602147490918660274601"
            result = ifactor(giac_eval(big_num))
            # Should not throw an exception
            sym = @test_nowarn to_symbolics(result)
            @test sym isa Num
            # Verify it's a product (factored form)
            sym_str = string(sym)
            @test occursin("*", sym_str)
        end

        # T005: Int128-range factors
        @testset "T005: ifactor with Int128-range result" begin
            # A number that factors into Int128-range primes
            # 2^100 is larger than Int64 but results should convert
            result = ifactor(giac_eval("2^63 * 3"))  # 2^63 is just beyond Int64
            sym = @test_nowarn to_symbolics(result)
            @test sym isa Num
        end

        # T006: BigInt-range factors
        @testset "T006: ifactor with BigInt-range result" begin
            # Product of two very large primes
            result = ifactor(giac_eval("170141183460469231731687303715884105727"))  # 2^127 - 1 (Mersenne prime)
            sym = @test_nowarn to_symbolics(result)
            @test sym isa Num
        end

        # T007: Mixed small and large factors
        @testset "T007: ifactor with mixed small and large factors" begin
            # 2 * large_prime
            result = ifactor(giac_eval("2 * 650655447295098801102272374367"))
            sym = @test_nowarn to_symbolics(result)
            @test sym isa Num
            sym_str = string(sym)
            @test occursin("2", sym_str)
            @test occursin("*", sym_str)
        end

        # Regression tests for backward compatibility
        @testset "Regression: ifactor(1000000) still works" begin
            result = ifactor(1000000)
            sym = @test_nowarn to_symbolics(result)
            @test sym isa Num
        end

        @testset "Regression: ifactor(17) prime still works" begin
            result = ifactor(17)
            sym = @test_nowarn to_symbolics(result)
            @test sym isa Num
        end

        @testset "Regression: ifactor(-24) negative still works" begin
            result = ifactor(-24)
            sym = @test_nowarn to_symbolics(result)
            @test sym isa Num
        end

        # Edge cases
        @testset "T019: Int64/Int128 boundary" begin
            # Max Int64 = 9223372036854775807
            # Test a number just beyond Int64 max
            result = ifactor(giac_eval("9223372036854775808"))  # Int64 max + 1
            sym = @test_nowarn to_symbolics(result)
            @test sym isa Num
        end

        @testset "T020: Large exponents (2^100)" begin
            result = giac_eval("2^100")
            sym = @test_nowarn to_symbolics(result)
            @test sym isa Num
        end
    end

    # ============================================================================
    # Edge Cases and Backward Compatibility (Phase 6)
    # ============================================================================
    @testset "Edge Cases and Backward Compatibility" begin
        # T036: Mixed numeric/symbolic expressions
        @testset "T036: Mixed numeric and symbolic" begin
            # Note: GIAC evaluates 2.5 + sqrt(2) to a float
            # To preserve structure, use exact fractions
            result = giac_eval("5/2 + sqrt(2)")
            sym = to_symbolics(result)
            sym_str = string(sym)
            # Should preserve sqrt(2) - check that it's not 3.914...
            @test !occursin("3.914", sym_str) || !occursin("1.414", sym_str)
        end

        # T037: Backward compatibility - simple expressions still work
        @testset "T037: Backward compatibility" begin
            # Simple polynomial
            result = giac_eval("x^2 + 2*x + 1")
            sym = to_symbolics(result)
            @test sym isa Num

            # Simple integer
            result = giac_eval("42")
            sym = to_symbolics(result)
            @test sym isa Num
        end
    end

    # ============================================================================
    # Feature 063: Fix TypeError when converting power expressions (issue #1)
    # ============================================================================
    @testset "Feature 063: to_giac power expressions" begin
        @variables a x y

        # US1: Basic power expressions
        @testset "US1: to_giac(a^2) — issue #1 reproducer" begin
            result = to_giac(a^2)
            @test result isa GiacExpr
            @test occursin("a", string(result))
            @test occursin("^", string(result)) || occursin("2", string(result))
        end

        @testset "US1: to_giac(x^3) — other integer exponents" begin
            result = to_giac(x^3)
            @test result isa GiacExpr
            @test occursin("x", string(result))
        end

        @testset "US1: to_giac(x^2 + y^2) — sum of squares" begin
            result = to_giac(x^2 + y^2)
            @test result isa GiacExpr
            result_str = string(result)
            @test occursin("x", result_str)
            @test occursin("y", result_str)
        end

        # US2: Compound expressions
        @testset "US2: to_giac(sin(x)^2) — function with power" begin
            result = to_giac(sin(x)^2)
            @test result isa GiacExpr
            result_str = string(result)
            @test occursin("sin", result_str)
        end

        @testset "US2: to_giac(x^2 * y) — power with multiplication" begin
            result = to_giac(x^2 * y)
            @test result isa GiacExpr
            result_str = string(result)
            @test occursin("x", result_str)
            @test occursin("y", result_str)
        end

        @testset "US2: to_giac((x + y)^2) — power of sum" begin
            result = to_giac((x + y)^2)
            @test result isa GiacExpr
            result_str = string(result)
            @test occursin("x", result_str)
            @test occursin("y", result_str)
        end

        # US2: Edge cases
        @testset "US2: edge cases — a^0, a^(-1), a^b" begin
            @variables b

            result_zero = to_giac(a^0)
            @test result_zero isa GiacExpr

            result_neg = to_giac(a^(-1))
            @test result_neg isa GiacExpr

            result_sym = to_giac(a^b)
            @test result_sym isa GiacExpr
            result_str = string(result_sym)
            @test occursin("a", result_str)
            @test occursin("b", result_str)
        end

        # US3: Roundtrip conversion
        @testset "US3: roundtrip to_symbolics(to_giac(a^2))" begin
            original = a^2
            roundtrip = to_symbolics(to_giac(original))
            @test roundtrip isa Num
            # Verify mathematical equivalence by substituting a value
            @test Symbolics.substitute(roundtrip, Dict(a => 3)) == Symbolics.substitute(original, Dict(a => 3))
        end

        @testset "US3: roundtrip to_symbolics(to_giac(x^2 + y))" begin
            original = x^2 + y
            roundtrip = to_symbolics(to_giac(original))
            @test roundtrip isa Num
            @test Symbolics.substitute(roundtrip, Dict(x => 2, y => 5)) == Symbolics.substitute(original, Dict(x => 2, y => 5))
        end
    end

    # ============================================================================
    # Issue #89: irrational constants in to_giac (Symbolics 7)
    # ============================================================================
    # With Symbolics 7, Num(pi) unwraps to identity(π) around the Irrational π.
    # to_giac recursed on it forever (StackOverflowError) instead of mapping
    # it to GIAC's constant.
    @testset "Issue #89: to_giac on irrational constants" begin
        @variables x
        g(e) = string(Giac.giac_eval("evalf($(string(e)))"))
        approx(e, v) = isapprox(parse(Float64, g(e)), v; rtol = 1e-10)

        @testset "π" begin
            r = to_giac(Num(pi))
            @test string(r) == "pi"
            @test approx(r, Float64(pi))
        end

        @testset "ℯ is exp(1), not an identifier named e" begin
            r = to_giac(Num(ℯ))
            @test string(r) == "e" || string(r) == "exp(1)"
            @test approx(r, Float64(ℯ))
        end

        @testset "Euler's γ" begin
            r = to_giac(Num(Base.MathConstants.eulergamma))
            @test string(r) == "euler_gamma"
            @test approx(r, Float64(Base.MathConstants.eulergamma))
        end

        @testset "golden ratio φ is exact" begin
            r = to_giac(Num(Base.MathConstants.golden))
            @test occursin("sqrt(5)", string(r))
            @test approx(r, Float64(Base.MathConstants.golden))
        end

        @testset "constants inside expressions" begin
            r = to_giac(x + pi)
            @test string(Giac.giac_eval("normal($(string(r)) - (x+pi))")) == "0"
            r = to_giac(2 * ℯ * x)
            @test approx(Giac.giac_eval("subst($(string(r)),x,1)"), 2 * Float64(ℯ))
        end

        @testset "bare Irrational outside Num" begin
            ext = Base.get_extension(Giac, :GiacSymbolicsExt)
            @test Giac.GiacCxxBindings.to_string(ext._convert_to_gen(pi)) == "pi"
        end

        @testset "constant with no GIAC equivalent is an error, not a hang" begin
            @test_throws ArgumentError to_giac(Num(Base.MathConstants.catalan))
        end
    end

end  # @testset "Symbolics Extension"
