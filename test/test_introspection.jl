# Integration tests for 003-giac-introspection feature
# Tests for type introspection, to_julia conversions, Tier 1 functions, and typed accessors

@testset "Introspection (003-giac-introspection)" begin

    # ========================================================================
    # T-015: Scalar constructors and giac_eval
    # ========================================================================
    @testset "Scalar Constructors and giac_eval" begin
        # Integer evaluation
        result = giac_eval("42")
        @test string(result) == "42"
        @test to_julia(result) == 42

        # Float evaluation
        result = giac_eval("3.14159")
        @test occursin("3.14", string(result))

        # Expression evaluation
        result = giac_eval("2 + 3")
        @test string(result) == "5"
        @test to_julia(result) == 5

        # Symbolic evaluation
        result = giac_eval("x")
        @test string(result) == "x"

        # Complex expression
        result = giac_eval("x^2 + 2*x + 1")
        @test occursin("x", string(result))
    end

    # ========================================================================
    # T-079-084: to_julia conversions
    # ========================================================================
    @testset "to_julia Conversions" begin
        # T-079: Integer conversion
        @testset "Integer → Int64" begin
            result = giac_eval("42")
            julia_val = to_julia(result)
            @test julia_val == 42
            @test julia_val isa Integer
        end

        # T-080: Rational conversion
        @testset "Fraction → Rational" begin
            result = giac_eval("3/7")
            julia_val = to_julia(result)
            @test julia_val == 3//7
            @test julia_val isa Rational
        end

        # T-081: Complex conversion
        @testset "Complex → ComplexF64" begin
            result = giac_eval("2+3*i")
            julia_val = to_julia(result)
            @test real(julia_val) ≈ 2.0
            @test imag(julia_val) ≈ 3.0
            @test julia_val isa Complex
        end

        # T-082: Matrix - returns nested Vector
        @testset "Matrix" begin
            result = giac_eval("[[1,2],[3,4]]")
            julia_val = to_julia(result)
            # Matrices are converted to nested arrays
            @test julia_val isa Vector
            @test length(julia_val) == 2
            @test julia_val[1] isa Vector
            @test julia_val[1] == [1, 2]
            @test julia_val[2] == [3, 4]
        end

        # T-083: Identifier - currently returns GiacExpr (not yet implemented)
        @testset "Identifier" begin
            result = giac_eval("x")
            julia_val = to_julia(result)
            # Currently returns GiacExpr for identifiers
            @test julia_val isa GiacExpr
            @test string(julia_val) == "x"
        end

        # T-084: Symbolic expression returns GiacExpr
        @testset "Symbolic Expression" begin
            result = giac_eval("sin(x) + cos(y)")
            julia_val = to_julia(result)
            # Symbolic expressions return as GiacExpr
            @test julia_val isa GiacExpr
            @test occursin("sin", string(julia_val))
            @test occursin("cos", string(julia_val))
        end

        # Vector - returns Julia Vector
        @testset "Vector" begin
            result = giac_eval("[1, 2, 3, 4, 5]")
            julia_val = to_julia(result)
            # Vectors are converted to Julia arrays
            @test julia_val isa Vector
            @test julia_val == [1, 2, 3, 4, 5]
        end

        # Boolean (GIAC represents true as 1)
        @testset "Boolean" begin
            result = giac_eval("true")
            julia_val = to_julia(result)
            @test julia_val == 1
        end

        # String
        @testset "String" begin
            result = giac_eval("\"hello\"")
            julia_val = to_julia(result)
            # A STRNG converts to its characters — not to GIAC's printed
            # literal, which would carry the surrounding double quotes.
            @test julia_val isa String
            @test julia_val == "hello"
        end

        # Infinity
        @testset "Infinity" begin
            result = giac_eval("infinity")
            julia_val = to_julia(result)
            # Check if it's infinity or symbolic (GiacExpr)
            @test julia_val isa GiacExpr || (julia_val isa Number && isinf(julia_val))
        end

        # Large integers
        @testset "Large Integer" begin
            result = giac_eval("factorial(20)")
            julia_val = to_julia(result)
            @test julia_val == factorial(big(20))
        end
    end

    # ========================================================================
    # T-143-145: Tier 1 functions
    # ========================================================================
    @testset "Tier 1 Functions" begin
        # T-143: sin(x) returns sin(x)
        @testset "Trigonometric Functions" begin
            x = giac_eval("x")

            result = sin(x)
            @test occursin("sin", string(result))

            result = cos(x)
            @test occursin("cos", string(result))

            result = tan(x)
            @test occursin("tan", string(result))

            # Numeric evaluation
            result = sin(giac_eval("0"))
            @test to_julia(result) == 0

            result = cos(giac_eval("0"))
            @test to_julia(result) == 1
        end

        @testset "Exponential and Logarithm" begin
            x = giac_eval("x")

            result = exp(x)
            @test occursin("exp", string(result))

            result = log(x)
            @test occursin("ln", string(result)) || occursin("log", string(result))

            result = sqrt(x)
            @test occursin("sqrt", string(result))

            # Numeric
            result = exp(giac_eval("0"))
            @test to_julia(result) == 1

            result = sqrt(giac_eval("4"))
            @test to_julia(result) == 2
        end

        @testset "Arithmetic Functions" begin
            result = abs(giac_eval("-5"))
            @test to_julia(result) == 5

            result = sign(giac_eval("-5"))
            @test to_julia(result) == -1

            result = floor(giac_eval("3.7"))
            @test to_julia(result) == 3

            result = ceil(giac_eval("3.2"))
            @test to_julia(result) == 4
        end

        @testset "Complex Functions" begin
            z = giac_eval("2+3*i")

            result = real(z)
            @test to_julia(result) == 2

            result = imag(z)
            @test to_julia(result) == 3

            result = conj(z)
            @test occursin("2", string(result))
            @test occursin("-3", string(result)) || occursin("- 3", string(result))
        end

        # T-144: diff(sin(x^2), x) = 2*x*cos(x^2)
        @testset "Calculus - Differentiation" begin
            x = giac_eval("x")
            expr = sin(x^2)
            result = Giac.giac_cmd(:diff, expr, x)
            result_str = string(result)
            # Should contain 2, x, and cos
            @test occursin("2", result_str)
            @test occursin("cos", result_str)
        end

        @testset "Calculus - Integration" begin
            x = giac_eval("x")
            # integrate(x^2, x) = x^3/3
            result = Giac.giac_cmd(:integrate, x^2, x)
            result_str = string(result)
            @test occursin("3", result_str)  # x^3/3 contains 3
        end

        # T-145: Mixed-type operators
        @testset "Mixed-Type Operators" begin
            x = giac_eval("x")

            # GiacExpr + Integer
            result = x + 1
            @test occursin("x", string(result))
            @test occursin("1", string(result))

            # Integer * GiacExpr
            result = 2 * x
            @test occursin("2", string(result))
            @test occursin("x", string(result))

            # GiacExpr ^ Integer
            result = x^3
            @test occursin("x", string(result))
            @test occursin("3", string(result))

            # Numeric mixed operations
            result = giac_eval("5") + 3
            @test to_julia(result) == 8

            result = 2 * giac_eval("7")
            @test to_julia(result) == 14
        end
    end

    # ========================================================================
    # T-102-105: Typed accessors and predicates
    # ========================================================================
    @testset "Typed Accessors" begin
        # T-102: frac_num/frac_den (tested via to_julia)
        @testset "Fraction Accessors" begin
            result = giac_eval("5/7")
            julia_val = to_julia(result)
            @test numerator(julia_val) == 5
            @test denominator(julia_val) == 7
        end

        # T-103: vect_size/vect_at (tested via string representation)
        @testset "Vector Accessors" begin
            result = giac_eval("[10, 20, 30]")
            result_str = string(result)
            @test occursin("10", result_str)
            @test occursin("20", result_str)
            @test occursin("30", result_str)
        end

        # T-104: symb_sommet_name (via string representation)
        @testset "Symbolic Accessors" begin
            result = giac_eval("sin(x)")
            result_str = string(result)
            @test occursin("sin", result_str)
            @test occursin("x", result_str)
        end
    end

    # ========================================================================
    # CxxWrap Gen type tests (when library available)
    # ========================================================================
    @testset "CxxWrap Gen Type" begin
        if Giac.GiacCxxBindings._have_library
            # Use fully qualified names to avoid polluting Main namespace
            # (which would conflict with Giac.is_integer for GiacExpr)
            GCB = Giac.GiacCxxBindings
            cxx_eval = GCB.giac_eval
            to_string = GCB.to_string

            @testset "Gen Type Information" begin
                # Integer type
                g = cxx_eval("42")
                @test GCB.type(g) == GCB.GENTYPE_INT

                # Symbolic type
                g = cxx_eval("x")
                @test GCB.type(g) == GCB.GENTYPE_IDNT

                # Expression type
                g = cxx_eval("x + 1")
                @test GCB.type(g) == GCB.GENTYPE_SYMB
            end

            @testset "Gen Predicates" begin
                @test GCB.is_zero(cxx_eval("0")) == true
                @test GCB.is_zero(cxx_eval("1")) == false
                @test GCB.is_one(cxx_eval("1")) == true
                @test GCB.is_one(cxx_eval("0")) == false
                @test GCB.is_integer(cxx_eval("42")) == true
                @test GCB.is_integer(cxx_eval("3.14")) == false
            end

            @testset "Gen Tier 1 Direct Wrappers" begin
                x = cxx_eval("x")

                result = GCB.giac_sin(x)
                @test occursin("sin", to_string(result))

                result = GCB.giac_cos(x)
                @test occursin("cos", to_string(result))

                # Differentiation
                result = GCB.giac_diff(cxx_eval("x^2"), x)
                @test occursin("2", to_string(result))
                @test occursin("x", to_string(result))
            end
        else
            @warn "Skipping CxxWrap Gen type tests - library not available"
            @test_broken false
        end
    end

    # ========================================================================
    # Function listing and help
    # ========================================================================
    @testset "Function Listing" begin
        @testset "help_count" begin
            hc = Giac.help_count()
            @test hc >= 2200
            @test hc isa Integer
        end

        @testset "VALID_COMMANDS" begin
            vc = length(Giac.VALID_COMMANDS)
            @test vc >= 2000
            @test :sin in Giac.VALID_COMMANDS
            @test :cos in Giac.VALID_COMMANDS
            @test :diff in Giac.VALID_COMMANDS
            @test :integrate in Giac.VALID_COMMANDS
            @test :factor in Giac.VALID_COMMANDS
        end
    end

    # ========================================================================
    # Boolean Predicate (030-to-julia-bool-conversion)
    # ========================================================================
    @testset "Boolean Predicate" begin
        @testset "is_boolean returns true for boolean literals" begin
            @test Giac.is_boolean(giac_eval("true")) == true
            @test Giac.is_boolean(giac_eval("false")) == true
        end

        @testset "is_boolean returns true for comparison results" begin
            @test Giac.is_boolean(giac_eval("1==1")) == true
            @test Giac.is_boolean(giac_eval("1==0")) == true
            @test Giac.is_boolean(giac_eval("2>1")) == true
            @test Giac.is_boolean(giac_eval("1<0")) == true
        end

        @testset "is_boolean returns false for integers" begin
            @test Giac.is_boolean(giac_eval("1")) == false
            @test Giac.is_boolean(giac_eval("0")) == false
            @test Giac.is_boolean(giac_eval("42")) == false
        end

        @testset "is_boolean returns false for other types" begin
            @test Giac.is_boolean(giac_eval("3.14")) == false
            @test Giac.is_boolean(giac_eval("x")) == false
            @test Giac.is_boolean(giac_eval("[1,2,3]")) == false
        end
    end

    # ========================================================================
    # TermInterface names
    # ========================================================================
    @testset "terminterface names" begin
        @test length(Giac.arguments(giac_eval("a*b*c"))) == 3
        @test Giac.arguments(sin(giac_eval("x"))) == [giac_eval("x")]

        @test Giac.operation(giac_eval("a*b*c")) == *
        @test Giac.operation(sin(giac_eval("x"))) == sin
        @test Giac.operation(giac_eval("Gamma(x)")) == Giac.Commands.Gamma

        @test Giac.iscall(giac_eval("x")) == false
        @test Giac.iscall(giac_eval("pi")) == false
        @test Giac.iscall(giac_eval("sin(x)")) == true

        @test Giac.maketerm(GiacExpr, ^, (giac_eval("2"), giac_eval("3")), nothing) == 8
    end

    # ========================================================================
    # Constant expressions
    # ========================================================================
    @testset "constant expressions" begin
        @test Giac.is_constant(giac_eval("sin(pi)"))
        @test !Giac.is_constant(giac_eval("sin(x)"))
        @test Giac.unwrap_const(giac_eval("sin(pi/2)")) ≈ 1
        @test Giac.unwrap_const(giac_eval("sin(x)")) == giac_eval("sin(x)")


        # Issue #19: `infinity` and `undef` are GIAC atoms with no free
        # symbols, so is_constant must report them as constants. The
        # compound infinity forms (`+infinity`, `-infinity`, `inf`,
        # `-inf`) wrap the bare `infinity` IDNT and reduce to it via
        # hasmatch recursion. `unsigned_inf` is a GIAC alias that parses
        # to the same `infinity` atom.
        @test Giac.is_constant(giac_eval("infinity"))
        @test Giac.is_constant(giac_eval("inf"))
        @test Giac.is_constant(giac_eval("+inf"))
        @test Giac.is_constant(giac_eval("-inf"))
        @test Giac.is_constant(giac_eval("+infinity"))
        @test Giac.is_constant(giac_eval("-infinity"))
        @test Giac.is_constant(giac_eval("unsigned_inf"))
        @test Giac.is_constant(giac_eval("undef"))
        @test to_julia(giac_eval("inf")) isa GiacExpr
        @test to_julia(giac_eval("undef")) isa GiacExpr

        # Compound expressions built from the special atoms remain
        # constant when no free variable is introduced.
        @test Giac.is_constant(giac_eval("infinity^2"))
        @test Giac.is_constant(giac_eval("1/infinity"))

        # Negative cases: names that *look* like special atoms but are
        # actually parsed by GIAC as ordinary free identifiers (they
        # behave just like `xyz`). `nan + 1` yields `nan+1`, the same
        # shape as `xyz + 1` — so they must NOT be recognized as
        # constant.
        @test !Giac.is_constant(giac_eval("nan"))
        @test !Giac.is_constant(giac_eval("NaN"))
        @test !Giac.is_constant(giac_eval("undefined"))
        @test !Giac.is_constant(giac_eval("unsigned_infinity"))
    end

    # ========================================================================
    # float conversion
    # ========================================================================
    @testset "float conversion" begin
        @test float(giac_eval("1")) == 1.0
        @test float(giac_eval("1.2")) == 1.2
        @test float(giac_eval("1 + i")) == 1.0 + 1.0*im
        @test float(giac_eval("1/2")) == 0.5
        @test float(giac_eval("[1,2,3]")) == [1.0, 2.0, 3.0]
    end

    # ========================================================================
    # Constants.is_giac_constant — recognized symbolic constants
    # ========================================================================
    @testset "Constants.is_giac_constant" begin
        # Existing pi/e/i.
        @test Giac.Constants.is_giac_constant(giac_eval("pi"))
        @test Giac.Constants.is_giac_constant(giac_eval("e"))
        @test Giac.Constants.is_giac_constant(giac_eval("i"))

        # Issue #19: real GIAC atoms `infinity` and `undef`.
        @test Giac.Constants.is_giac_constant(giac_eval("infinity"))
        @test Giac.Constants.is_giac_constant(giac_eval("undef"))

        # Negative cases — including names that look special but are
        # plain free identifiers in GIAC.
        @test !Giac.Constants.is_giac_constant(giac_eval("x"))
        @test !Giac.Constants.is_giac_constant(giac_eval("1"))
        @test !Giac.Constants.is_giac_constant(giac_eval("sin(x)"))
        @test !Giac.Constants.is_giac_constant(giac_eval("nan"))
        @test !Giac.Constants.is_giac_constant(giac_eval("NaN"))
        @test !Giac.Constants.is_giac_constant(giac_eval("undefined"))
        @test !Giac.Constants.is_giac_constant(giac_eval("unsigned_infinity"))
    end

    # ========================================================================
    # Free symbols
    # ========================================================================
    @testset "free symbols" begin
        @test length(Giac.free_symbols(giac_eval("sin(2)"))) == 0
        @test length(Giac.free_symbols(giac_eval("sin(x)"))) == 1
        @test length(Giac.free_symbols(giac_eval("sin(pi*x)"))) == 1
        @test length(Giac.free_symbols(giac_eval("sin(x + y)"))) == 2
    end

    # ========================================================================
    # to_julia auto-evalf for free-variable-free expressions (Issue #3)
    # When a symbolic expression has no free variables, to_julia reduces it
    # numerically (via evalf) and returns a Julia number. Symbolic
    # expressions with at least one free variable pass through unchanged.
    # ========================================================================
    @testset "to_julia auto-evalf (Issue #3)" begin
        @giac_var x y

        # The canonical Issue #3 case.
        r = to_julia(substitute(sin(x), x => 2))
        @test r isa Float64
        @test r ≈ 0.909297426825682

        # Constants reduce numerically.
        @test to_julia(giac_eval("pi"))         isa Float64
        @test to_julia(giac_eval("sqrt(2)"))    isa Float64
        @test to_julia(giac_eval("sin(pi/4)"))  ≈ sqrt(2)/2

        # Free-variable expressions pass through unchanged.
        @test to_julia(x)                === x
        @test to_julia(sin(x))           isa GiacExpr
        @test to_julia(x + 1)            isa GiacExpr
        @test to_julia(substitute(sin(x), y => 2)) isa GiacExpr   # x still free

        # Pre-existing numeric / boolean / vector paths are untouched.
        @test to_julia(giac_eval("42"))  === 42
        @test to_julia(giac_eval("3/4")) === 3//4
        @test to_julia(giac_eval("true"))
        @test to_julia(giac_eval("[1,2,3]")) == [1, 2, 3]
    end

end
