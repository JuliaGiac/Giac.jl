# SymPy Conversion Extension Tests (080-sympy-bridge)
# Tests GiacExpr -> SymPy.jl conversion (to_sympy).
#
# Scope: this file currently exercises only the Giac -> SymPy direction
# (`to_sympy`). The reverse direction (`to_giac(::SymPy.Sym)`) is tracked
# separately and is not covered here yet.
#
# Modeled on test_mathjson_conversion.jl and test_symbolics_ext.jl, the two
# existing bidirectional third-party bridges in this package.

using SymPy
using Giac: to_sympy

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
