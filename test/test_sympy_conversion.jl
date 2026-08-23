# SymPy Conversion Extension Tests (080-sympy-bridge)
# Bidirectional tests: GiacExpr -> SymPy.jl (to_sympy) and
# SymPy.jl -> GiacExpr (to_giac(::Sym)).
#
# Modeled on test_mathjson_conversion.jl and test_symbolics_ext.jl, the two
# existing bidirectional third-party bridges in this package.

using SymPy
using Giac: to_sympy, to_giac

@testset "SymPy Conversion (to_sympy)" begin

    # ============================================================================
    # Basic numeric types
    # ============================================================================

    @testset "to_sympy - basic numeric types" begin
        # INT -> Sym
        expr = giac_eval("42")
        result = to_sympy(expr)
        @test result isa Sym
        @test result == Sym(42)

        # Negative integer
        expr = giac_eval("-7")
        result = to_sympy(expr)
        @test result == Sym(-7)

        # Zero
        expr = giac_eval("0")
        result = to_sympy(expr)
        @test result == Sym(0)

        # DOUBLE -> Sym (float)
        expr = giac_eval("3.14")
        result = to_sympy(expr)
        @test N(result) ≈ 3.14

        # ZINT -> Sym (arbitrary precision integer)
        expr = giac_eval("123456789012345678901234567890")
        result = to_sympy(expr)
        @test result == Sym(big"123456789012345678901234567890")
    end

    # ============================================================================
    # Identifiers and constants
    # ============================================================================

    @testset "to_sympy - identifiers and constants" begin
        # Variable x -> symbols("x")
        expr = giac_eval("x")
        result = to_sympy(expr)
        @test result isa Sym
        @test string(result) == "x"
        @test result == symbols("x")

        # Variable y -> symbols("y")
        expr = giac_eval("y")
        result = to_sympy(expr)
        @test string(result) == "y"

        # Constant pi -> SymPy's PI
        expr = giac_eval("pi")
        result = to_sympy(expr)
        @test result == SymPy.PI

        # Constant e: GIAC evaluates bare "e" to exp(1) (SYMB type, like
        # to_mathjson/to_symbolics do), which SymPy auto-simplifies to E.
        expr = giac_eval("e")
        result = to_sympy(expr)
        @test result == SymPy.E

        # Constant i: GIAC evaluates bare "i" to complex 0+1*i (CPLX type)
        expr = giac_eval("i")
        result = to_sympy(expr)
        @test result == SymPy.IM
    end

    # ============================================================================
    # Symbolic expressions
    # ============================================================================

    @testset "to_sympy - symbolic expressions" begin
        @giac_var x y

        # sin(x)
        expr = giac_eval("sin(x)")
        result = to_sympy(expr)
        @test result == sin(symbols("x"))

        # cos(x)
        expr = giac_eval("cos(x)")
        result = to_sympy(expr)
        @test result == cos(symbols("x"))

        # exp(x)
        expr = giac_eval("exp(x)")
        result = to_sympy(expr)
        @test result == exp(symbols("x"))

        # sqrt(x) - must stay symbolic, not evaluate numerically
        expr = giac_eval("sqrt(x)")
        result = to_sympy(expr)
        @test result == sqrt(symbols("x"))

        # ln(x) -> SymPy log(x) (GIAC "ln" <-> Julia/SymPy "log" name mapping,
        # mirrors GIAC_NAME_MAPPING in GiacSymbolicsExt)
        expr = giac_eval("ln(x)")
        result = to_sympy(expr)
        @test result == log(symbols("x"))

        # log10(x): GIAC evaluates log10 to the change-of-base form
        # ln(x)/ln(10), with ln(10) reduced to a Float. The SymPy result is
        # therefore log(x)/log(10) up to floating-point rounding; check
        # numerical equality at x=10 (log10(10) == 1) instead of structural
        # equality.
        xvar = symbols("x")
        expr = giac_eval("log10(x)")
        result = to_sympy(expr)
        @test isapprox(Float64(N(result.subs(xvar, 10))), 1.0; atol=1e-12)

        # x + 1
        expr = x + 1
        result = to_sympy(expr)
        @test result == symbols("x") + 1

        # x * y
        expr = x * y
        result = to_sympy(expr)
        @test result == symbols("x") * symbols("y")

        # x^2
        expr = x^2
        result = to_sympy(expr)
        @test result == symbols("x")^2

        # x - y
        expr = x - y
        result = to_sympy(expr)
        @test result == symbols("x") - symbols("y")

        # x / y
        expr = x / y
        result = to_sympy(expr)
        @test result == symbols("x") / symbols("y")
    end

    # ============================================================================
    # Rational and complex numbers
    # ============================================================================

    @testset "to_sympy - FRAC (rational)" begin
        expr = giac_eval("3/4")
        result = to_sympy(expr)
        @test result == Sym(3) / Sym(4)
    end

    @testset "to_sympy - CPLX (complex)" begin
        expr = giac_eval("3+4*i")
        result = to_sympy(expr)
        @test result == Sym(3) + Sym(4) * SymPy.IM
    end

    # ============================================================================
    # Deeply nested expressions
    # ============================================================================

    @testset "to_sympy - deeply nested expressions" begin
        expr = giac_eval("sin(cos(tan(x)))")
        result = to_sympy(expr)
        @test result == sin(cos(tan(symbols("x"))))

        # Factored polynomial structure survives the conversion (mirrors the
        # to_symbolics factor() test in test_symbolics_ext.jl)
        @giac_var z
        factored = Giac.Commands.factor(z^2 - 1)
        result = to_sympy(factored)
        @test SymPy.expand(result) == symbols("z")^2 - 1
    end

    # ============================================================================
    # Unsupported types
    # ============================================================================

    @testset "to_sympy - unsupported types" begin
        # String type should throw ErrorException, matching to_mathjson's
        # behavior (test_mathjson_conversion.jl's "unsupported types" test).
        # Deliberately not the looser `Exception` supertype: that would also
        # catch the interim stub's MethodError and pass vacuously before
        # to_sympy is implemented.
        expr = giac_eval("\"hello\"")
        @test_throws ErrorException to_sympy(expr)
    end

end

# ============================================================================
# SymPy -> Giac direction (to_giac(::Sym))
# ============================================================================

@testset "SymPy Conversion (to_giac)" begin

    # ----------------------------------------------------------------------------
    # Basic numeric types
    # ----------------------------------------------------------------------------
    @testset "to_giac - basic numeric types" begin
        # Integer
        @test to_giac(Sym(42)) == giac_eval("42")
        @test to_giac(Sym(-7)) == giac_eval("-7")
        @test to_giac(Sym(0)) == giac_eval("0")

        # Float
        @test to_julia(to_giac(Sym(3.14))) ≈ 3.14

        # Arbitrary precision integer
        big_n = big"123456789012345678901234567890"
        @test to_julia(to_giac(Sym(big_n))) == big_n
    end

    # ----------------------------------------------------------------------------
    # Identifiers and constants
    # ----------------------------------------------------------------------------
    @testset "to_giac - identifiers and constants" begin
        @test to_giac(symbols("x")) == giac_eval("x")
        @test to_giac(symbols("y")) == giac_eval("y")

        # pi
        @test to_giac(SymPy.PI) == giac_eval("pi")

        # e  -> GIAC evaluates identifier "e" to exp(1)
        @test to_giac(SymPy.E) == giac_eval("e")

        # i  -> GIAC evaluates identifier "i" to 0+1*i
        @test to_giac(SymPy.IM) == giac_eval("i")
    end

    # ----------------------------------------------------------------------------
    # Rational and complex
    # ----------------------------------------------------------------------------
    @testset "to_giac - rational and complex" begin
        @test to_giac(Sym(3) // Sym(4)) == giac_eval("3/4")

        # complex 3 + 4*I
        c = Sym(3) + Sym(4) * SymPy.IM
        @test to_giac(c) == giac_eval("3+4*i")
    end

    # ----------------------------------------------------------------------------
    # Symbolic expressions
    # ----------------------------------------------------------------------------
    @testset "to_giac - symbolic expressions" begin
        x = symbols("x")
        y = symbols("y")

        @test to_giac(sin(x)) == giac_eval("sin(x)")
        @test to_giac(cos(x)) == giac_eval("cos(x)")
        @test to_giac(exp(x)) == giac_eval("exp(x)")
        @test to_giac(sqrt(x)) == giac_eval("sqrt(x)")

        # log(x) -> GIAC ln(x)  (name mapping, reverse of to_sympy's ln->log)
        @test to_giac(log(x)) == giac_eval("ln(x)")

        @test to_giac(x + 1) == giac_eval("x+1")
        @test to_giac(x * y) == giac_eval("x*y")
        @test to_giac(x^2) == giac_eval("x^2")
        @test to_giac(x - y) == giac_eval("x-y")
        @test to_giac(x / y) == giac_eval("x/y")
    end

    # ----------------------------------------------------------------------------
    # Nested expressions
    # ----------------------------------------------------------------------------
    @testset "to_giac - nested expressions" begin
        x = symbols("x")
        @test to_giac(sin(cos(tan(x)))) == giac_eval("sin(cos(tan(x)))")
    end

    # ----------------------------------------------------------------------------
    # Round-trip: Giac -> SymPy -> Giac preserves the expression
    # ----------------------------------------------------------------------------
    @testset "to_giac - round-trip fidelity" begin
        for s in ["42", "x", "sin(x)", "ln(x)", "sqrt(x)", "x+1",
                  "x*y", "x^2", "3/4", "3+4*i", "pi", "sin(cos(tan(x)))"]
            original = giac_eval(s)
            roundtrip = to_giac(to_sympy(original))
            @test roundtrip == original
        end
    end

    # ----------------------------------------------------------------------------
    # Unsupported types
    # ----------------------------------------------------------------------------
    @testset "to_giac - unsupported types" begin
        # A SymPy matrix (Julia Matrix{Sym}) is not a scalar expression; the
        # scalar bridge refuses it with an ErrorException, mirroring to_sympy's
        # unsupported-type behaviour.
        x = symbols("x")
        M = [x 1; 1 x]
        @test_throws ErrorException to_giac(M)
    end

end
