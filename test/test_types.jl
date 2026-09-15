@testset "Types" begin
    @testset "GiacInput type alias (032-vector-input-solve)" begin
        # T002: Test that AbstractVector is part of GiacInput union
        @test AbstractVector <: GiacInput
        @test Vector{GiacExpr} <: GiacInput
        @test Vector{Int} <: GiacInput
        @test Vector{Any} <: GiacInput
        # Verify existing types still work
        @test GiacExpr <: GiacInput
        @test Number <: GiacInput
        @test String <: GiacInput
        @test Symbol <: GiacInput
    end

    @testset "GiacError" begin
        # T007: Test GiacError exception type
        err = GiacError("test error", :parse)
        @test err isa Exception
        @test err.msg == "test error"
        @test err.category == :parse

        # Test error categories
        @test GiacError("", :eval).category == :eval
        @test GiacError("", :type).category == :type
        @test GiacError("", :memory).category == :memory
    end

    @testset "GiacExpr" begin
        # T007: Test GiacExpr type exists
        @test isdefined(Giac, :GiacExpr)

        # Test GiacExpr has required fields
        # Note: Actual construction requires wrapper to be working
    end

    @testset "GiacContext" begin
        # T007: Test GiacContext type exists
        @test isdefined(Giac, :GiacContext)

        # T034 [US2]: Test DEFAULT_CONTEXT is initialized
        @test isdefined(Giac, :DEFAULT_CONTEXT)
    end

    @testset "to_julia conversion" begin
        # T022 [US1]: Test to_julia numeric conversion
        # These tests will be expanded when giac_eval is working
    end

    # Callable GiacExpr Tests (034-callable-giacexpr)
    @testset "Callable GiacExpr - Helper Function" begin
        # T002: Test _arg_to_giac_string with GiacExpr argument
        @testset "_arg_to_giac_string with GiacExpr" begin
            x = giac_eval("x")
            @test Giac._arg_to_giac_string(x) == "x"
        end

        # T003: Test _arg_to_giac_string with Int argument
        @testset "_arg_to_giac_string with Int" begin
            @test Giac._arg_to_giac_string(42) == "42"
            @test Giac._arg_to_giac_string(0) == "0"
            @test Giac._arg_to_giac_string(-5) == "-5"
        end

        # T004: Test _arg_to_giac_string with Float64 argument
        @testset "_arg_to_giac_string with Float64" begin
            @test Giac._arg_to_giac_string(3.14) == "3.14"
            @test Giac._arg_to_giac_string(0.0) == "0.0"
        end

        # T005: Test _arg_to_giac_string with Symbol argument
        @testset "_arg_to_giac_string with Symbol" begin
            @test Giac._arg_to_giac_string(:x) == "x"
            @test Giac._arg_to_giac_string(:abc) == "abc"
        end

        # Test _extract_function_name helper
        @testset "_extract_function_name" begin
            # Simple function calls should extract the name
            @test Giac._extract_function_name("u(t)") == "u"
            @test Giac._extract_function_name("f(x,y)") == "f"
            @test Giac._extract_function_name("func(a,b,c)") == "func"

            # Simple identifiers should return nothing
            @test Giac._extract_function_name("x") === nothing
            @test Giac._extract_function_name("abc") === nothing

            # Expressions with operators should return nothing
            @test Giac._extract_function_name("a+b") === nothing
            @test Giac._extract_function_name("x^2") === nothing

            # GIAC operations should NOT be extracted (they are operations, not user functions)
            @test Giac._extract_function_name("diff(u,t)") === nothing
            @test Giac._extract_function_name("sin(x)") === nothing
            @test Giac._extract_function_name("integrate(f,x)") === nothing
        end
    end

    @testset "Callable GiacExpr - US1: Basic Function Evaluation" begin
        # T007: Test calling GiacExpr with single numeric argument
        @testset "u(0) with numeric argument" begin
            @giac_var u(t)
            result = u(0)
            @test result isa GiacExpr
            @test string(result) == "u(0)"
        end

        # T008: Test calling GiacExpr with GiacExpr argument
        @testset "f(x) with GiacExpr argument" begin
            @giac_var f(t) x
            result = f(x)
            @test result isa GiacExpr
            @test string(result) == "f(x)"
        end

        # T009: Test calling GiacExpr created by giac_eval
        @testset "callable on giac_eval result" begin
            u = giac_eval("u")
            result = u(0)
            @test result isa GiacExpr
            @test string(result) == "u(0)"
        end

        # T010: Test calling GiacExpr with zero arguments
        @testset "u() with zero arguments" begin
            @giac_var u(t)
            result = u()
            @test result isa GiacExpr
            # GIAC simplifies u() to just u
            @test string(result) == "u"
        end
    end

    @testset "Callable GiacExpr - US2: ODE Initial Conditions" begin
        # T014: Test u(0) ~ 1 creating valid equation
        @testset "u(0) ~ 1 creates equation" begin
            @giac_var u(t)
            eq = u(0) ~ 1
            @test eq isa GiacExpr
            # The equation should contain "u(0)=1" or equivalent
            eq_str = string(eq)
            @test occursin("u(0)", eq_str)
        end

        # T015: Test diff(u, t)(0) ~ 1 derivative condition
        @testset "diff(u, t)(0) ~ 1 derivative condition" begin
            @giac_var t u(t)
            du = invoke_cmd(:diff, u, t)
            du_at_0 = du(0)
            @test du_at_0 isa GiacExpr
            eq = du_at_0 ~ 1
            @test eq isa GiacExpr
        end

        # T016: Test diff(u, t, 2)(0) ~ 0 n-th derivative condition
        @testset "diff(u, t, 2)(0) n-th derivative" begin
            @giac_var t u(t)
            d2u = invoke_cmd(:diff, u, t, 2)
            d2u_at_0 = d2u(0)
            @test d2u_at_0 isa GiacExpr
        end

        # T017: Integration test with desolve
        @testset "desolve integration" begin
            @giac_var t u(t)
            # Simple ODE: u' = 0 with u(0) = 1 should give u = 1
            du = invoke_cmd(:diff, u, t)
            ode = du ~ 0
            initial = u(0) ~ 1
            # Just verify we can construct the problem
            @test ode isa GiacExpr
            @test initial isa GiacExpr
        end
    end

    @testset "Callable GiacExpr - US3: Multiple Arguments" begin
        # T020: Test f(0, 0) with two numeric arguments
        @testset "f(0, 0) with two numeric args" begin
            @giac_var f(x, y)
            result = f(0, 0)
            @test result isa GiacExpr
            @test string(result) == "f(0,0)"
        end

        # T021: Test f(a, b) with two GiacExpr arguments
        @testset "f(a, b) with two GiacExpr args" begin
            @giac_var f(x, y) a b
            result = f(a, b)
            @test result isa GiacExpr
            @test string(result) == "f(a,b)"
        end

        # T022: Test f(x, 1) with mixed argument types
        @testset "f(x, 1) mixed argument types" begin
            @giac_var f(x, y) x
            result = f(x, 1)
            @test result isa GiacExpr
            @test string(result) == "f(x,1)"
        end
    end

    @testset "Callable GiacExpr - Edge Cases" begin
        # T025: Test nested calls f(g(x))
        @testset "nested calls f(g(x))" begin
            @giac_var f(t) g(t) x
            g_of_x = g(x)
            f_of_g_of_x = f(g_of_x)
            @test f_of_g_of_x isa GiacExpr
            @test string(f_of_g_of_x) == "f(g(x))"
        end

        # T026: Test Rational argument u(1//2)
        @testset "Rational argument u(1//2)" begin
            @giac_var u(t)
            result = u(1//2)
            @test result isa GiacExpr
            # GIAC should interpret 1//2 appropriately
        end

        # T027: Test Float64 argument u(0.5)
        @testset "Float64 argument u(0.5)" begin
            @giac_var u(t)
            result = u(0.5)
            @test result isa GiacExpr
            @test string(result) == "u(0.5)"
        end

        # T028: Test invalid argument type raises ArgumentError
        @testset "invalid argument type raises error" begin
            @giac_var u(t)
            # Passing a Dict or other invalid type should raise ArgumentError
            @test_throws ArgumentError u(Dict())
        end

        # T029: Test null GiacExpr raises GiacError
        @testset "null GiacExpr raises error" begin
            # Create a null GiacExpr (for testing only)
            null_expr = GiacExpr(C_NULL)
            @test_throws GiacError null_expr(0)
        end

        # Additional edge cases: calling derivative-form and plain identifier expressions
        @testset "calling a derivative expression" begin
            @giac_var t u(t)
            du = invoke_cmd(:diff, u, t)
            result = du(0)
            @test result isa GiacExpr
            result_str = string(result)
            @test occursin("0", result_str)
        end

        @testset "calling plain identifier GiacExpr" begin
            @giac_var x
            sin_expr = giac_eval("sin")
            result = sin_expr(x)
            @test result isa GiacExpr
            @test string(result) == "sin(x)"
        end
    end

    @testset "LaTeX display (014-pluto-latex-notebook)" begin
        # Test that MIME"text/latex" show method is defined for GiacExpr
        @test hasmethod(Base.show, Tuple{IO, MIME"text/latex", GiacExpr})

        # Test that MIME"text/latex" show method is defined for GiacMatrix
        @test hasmethod(Base.show, Tuple{IO, MIME"text/latex", GiacMatrix})

        # Test actual LaTeX output for GiacExpr
        expr = giac_eval("2/(1-x)")
        io = IOBuffer()
        show(io, MIME"text/latex"(), expr)
        latex_output = String(take!(io))
        @test startswith(latex_output, "\$\$")
        @test endswith(latex_output, "\$\$")
        @test length(latex_output) > 4  # More than just "$$$$"

        # Test actual LaTeX output for GiacMatrix
        M = GiacMatrix([1 2; 3 4])
        io = IOBuffer()
        show(io, MIME"text/latex"(), M)
        latex_output = String(take!(io))
        @test startswith(latex_output, "\$\$")
        @test endswith(latex_output, "\$\$")
    end

    # ========================================================================
    # Derivative Operator D Tests (035-derivative-operator)
    # ========================================================================

    @testset "Derivative Operator D - Helper Function" begin
        # Test _parse_function_expr helper
        @testset "_parse_function_expr" begin
            # Simple function expressions
            @test Giac._parse_function_expr("u(t)") == ("u", "t")
            @test Giac._parse_function_expr("f(x,y)") == ("f", "x")
            @test Giac._parse_function_expr("func(a,b,c)") == ("func", "a")

            # Non-function expressions should return nothing
            @test Giac._parse_function_expr("x") === nothing
            @test Giac._parse_function_expr("a+b") === nothing

            # GIAC operations should return nothing
            @test Giac._parse_function_expr("diff(u,t)") === nothing
            @test Giac._parse_function_expr("sin(x)") === nothing

            # Unicode identifiers (issue reported by @tduretz)
            # GIAC C++ accepts Unicode names, so D() must too.
            @test Giac._parse_function_expr("ϕ(𝑧)") == ("ϕ", "𝑧")
            @test Giac._parse_function_expr("ψ(t)") == ("ψ", "t")
            @test Giac._parse_function_expr("α(β,γ)") == ("α", "β")
        end

        # spec 068: _parse_function_args returns full argument list
        @testset "_parse_function_args returns full arg list (068-multivar-d-operator)" begin
            @test Giac._parse_function_args("u(t)") == ("u", ["t"])
            @test Giac._parse_function_args("f(x,y)") == ("f", ["x", "y"])
            @test Giac._parse_function_args("g(a, b, c)") == ("g", ["a", "b", "c"])
            @test Giac._parse_function_args("h(  x  ,  y  )") == ("h", ["x", "y"])

            # Non-function expressions
            @test Giac._parse_function_args("x") === nothing
            @test Giac._parse_function_args("a+b") === nothing

            # GIAC operations are excluded
            @test Giac._parse_function_args("diff(u,t)") === nothing
            @test Giac._parse_function_args("sin(x)") === nothing

            # Unicode identifiers
            @test Giac._parse_function_args("ϕ(𝑧)") == ("ϕ", ["𝑧"])
            @test Giac._parse_function_args("α(β,γ)") == ("α", ["β", "γ"])
        end
    end

    @testset "Derivative Operator D - Unicode identifiers" begin
        # Regression test for @tduretz report: D(ϕ) used to fail because the
        # parser regex only accepted ASCII names.
        @giac_var 𝑧 ϕ(𝑧)
        dϕ = D(ϕ)
        @test dϕ isa DerivativeExpr
        @test dϕ.steps == [("𝑧", 1)]
        @test dϕ.funcname == "ϕ"

        d2ϕ = D(ϕ, 2)
        @test d2ϕ.steps == [("𝑧", 2)]
        @test d2ϕ.funcname == "ϕ"
    end

    @testset "Derivative Operator D - Basic Creation" begin
        @testset "D(u) creates first derivative" begin
            @giac_var u(t)
            du = D(u)
            @test du isa DerivativeExpr
            @test du.steps == [("t", 1)]
            @test du.funcname == "u"
        end

        @testset "D(u, 2) creates second derivative" begin
            @giac_var u(t)
            d2u = D(u, 2)
            @test d2u isa DerivativeExpr
            @test d2u.steps == [("t", 2)]
            @test d2u.funcname == "u"
        end

        @testset "D(D(u)) creates second derivative (steps collapsed)" begin
            @giac_var u(t)
            d2u = D(D(u))
            @test d2u isa DerivativeExpr
            @test d2u.steps == [("t", 2)]
        end

        @testset "D(u, 3) creates third derivative" begin
            @giac_var y(t)
            d3y = D(y, 3)
            @test d3y isa DerivativeExpr
            @test d3y.steps == [("t", 3)]
        end

        @testset "D on non-function raises error" begin
            @giac_var x
            @test_throws ArgumentError D(x)
        end
    end

    @testset "Derivative Operator D - Initial Conditions" begin
        @testset "D(u)(0) returns DerivativePoint" begin
            @giac_var u(t)
            result = D(u)(0)
            @test result isa DerivativePoint
            @test string(result) == "u'(0)"
        end

        @testset "D(u, 2)(0) returns DerivativePoint with double prime" begin
            @giac_var u(t)
            result = D(u, 2)(0)
            @test result isa DerivativePoint
            @test string(result) == "u''(0)"
        end

        @testset "D(D(u))(0) returns DerivativePoint with double prime" begin
            @giac_var u(t)
            result = D(D(u))(0)
            @test result isa DerivativePoint
            @test string(result) == "u''(0)"
        end

        @testset "D(u)(0) ~ 1 creates DerivativeCondition" begin
            @giac_var u(t)
            eq = D(u)(0) ~ 1
            @test eq isa DerivativeCondition
            @test string(eq) == "u'(0)=1"
        end

        @testset "D(u, 2)(0) ~ 0 creates DerivativeCondition" begin
            @giac_var u(t)
            eq = D(u, 2)(0) ~ 0
            @test eq isa DerivativeCondition
            @test string(eq) == "u''(0)=0"
        end
    end

    @testset "Derivative Operator D - Arithmetic" begin
        @testset "D(D(u)) + u produces diff notation" begin
            @giac_var u(t)
            result = D(D(u)) + u
            @test result isa GiacExpr
            # Should contain diff notation
            result_str = string(result)
            @test occursin("diff", result_str)
            @test occursin("u(t)", result_str)
        end

        @testset "D(D(u)) + u ~ 0 creates ODE" begin
            @giac_var u(t)
            ode = D(D(u)) + u ~ 0
            @test ode isa GiacExpr
            result_str = string(ode)
            @test occursin("diff", result_str)
            @test occursin("=0", result_str)
        end

        @testset "D(u) * 2 arithmetic" begin
            @giac_var u(t)
            result = 2 * D(u)
            @test result isa GiacExpr
        end
    end

    @testset "Derivative Operator D - Full ODE Solve" begin
        @testset "2nd order ODE: u'' + u = 0" begin
            using Giac.Commands: desolve
            @giac_var t u(t)

            # Build ODE and initial conditions
            ode = D(D(u)) + u ~ 0
            u0 = u(0) ~ 1
            du0 = D(u)(0) ~ 0

            # Solve - note: desolve requires just the function name :u, not u(t)
            result = desolve([ode, u0, du0], t, :u)
            result_str = string(result)

            # Should be cos(t)
            @test occursin("cos", result_str)
        end

        @testset "3rd order ODE: y''' - y = 0" begin
            using Giac.Commands: desolve
            @giac_var t y(t)

            # Build ODE and initial conditions
            ode = D(y, 3) - y ~ 0
            y0 = y(0) ~ 1
            dy0 = D(y)(0) ~ 1
            d2y0 = D(y, 2)(0) ~ 1

            # Solve - note: desolve requires just the function name :y, not y(t)
            result = desolve([ode, y0, dy0, d2y0], t, :y)
            result_str = string(result)

            # Should be exp(t)
            @test occursin("exp", result_str)
        end
    end

    @testset "Derivative Operator D - Display" begin
        @testset "show method displays primes" begin
            @giac_var u(t)
            io = IOBuffer()
            show(io, D(u))
            @test String(take!(io)) == "D: u'(t)"

            io = IOBuffer()
            show(io, D(u, 2))
            @test String(take!(io)) == "D: u''(t)"
        end

        # spec 068 — n-th derivative notation: switch from primes to ⁽ⁿ⁾ for n ≥ 4
        @testset "show method uses ⁽ⁿ⁾ for n ≥ 4 (068-multivar-d-operator)" begin
            @giac_var u(t)

            # Boundary: n = 3 still uses three primes
            io = IOBuffer()
            show(io, D(u, 3))
            @test String(take!(io)) == "D: u'''(t)"

            # Threshold: n = 4 switches to ⁽⁴⁾ notation
            io = IOBuffer()
            show(io, D(u, 4))
            @test String(take!(io)) == "D: u⁽⁴⁾(t)"

            # n = 5
            io = IOBuffer()
            show(io, D(u, 5))
            @test String(take!(io)) == "D: u⁽⁵⁾(t)"

            # Two-digit superscript
            io = IOBuffer()
            show(io, D(u, 12))
            @test String(take!(io)) == "D: u⁽¹²⁾(t)"
        end

        # spec 068 — DerivativePoint also uses the math-convention notation in show,
        # but Base.string keeps prime notation (GIAC consumes prime form).
        @testset "DerivativePoint show vs string (068-multivar-d-operator)" begin
            @giac_var u(t)

            # n = 1 — show and string agree (single prime)
            dp1 = D(u)(0)
            @test string(dp1) == "u'(0)"
            io = IOBuffer()
            show(io, dp1)
            @test String(take!(io)) == "u'(0)"

            # n = 4 — show uses ⁽⁴⁾, string keeps primes (for GIAC)
            dp4 = D(u, 4)(0)
            @test string(dp4) == "u''''(0)"  # GIAC-consumable
            io = IOBuffer()
            show(io, dp4)
            @test String(take!(io)) == "u⁽⁴⁾(0)"  # human-readable
        end
    end

    # spec 068 US5 — transitional D(f, x) alias overloads
    @testset "D transitional alias D(f, x) (068-multivar-d-operator US5)" begin
        @giac_var x y f(x, y)
        @giac_var t u(t)

        # D(f, x) ≡ Differential(x)(f), with depwarn
        d1 = D(f, x)
        d2 = Differential(x)(f)
        @test d1.steps == d2.steps
        @test d1.funcname == d2.funcname

        # D(f, x, 2) ≡ Differential(x)(Differential(x)(f))
        d3 = D(f, x, 2)
        d4 = Differential(x)(Differential(x)(f))
        @test d3.steps == d4.steps

        # D(D(f, x), y) ≡ Differential(y)(Differential(x)(f))
        d5 = D(D(f, x), y)
        d6 = Differential(y)(Differential(x)(f))
        @test d5.steps == d6.steps

        # D(u, t) ≡ Differential(t)(u)
        d7 = D(u, t)
        d8 = Differential(t)(u)
        @test d7.steps == d8.steps

        # D(u, t, 3) ≡ third-order derivative
        d9 = D(u, t, 3)
        @test d9.steps == [("t", 3)]

        # Each transitional alias emits a depwarn (shape check on D(f, x))
        @test_logs (:warn, r"D\(expr, var\) is deprecated.*Differential") match_mode=:any D(f, x)
    end

    # spec 068 US3 — D deprecation warnings + value-equivalence with Differential
    @testset "D deprecation (068-multivar-d-operator US3)" begin
        @giac_var t u(t)

        @testset "D(u) emits depwarn pointing to Differential(t)(u)" begin
            # @test_logs captures logs (including Base.depwarn) regardless of --depwarn flag.
            @test_logs (:warn, r"D\(u\) is deprecated.*Differential\(t\)\(u\)") match_mode=:any D(u)
        end

        @testset "D(u, 2) emits depwarn referencing Differential" begin
            @test_logs (:warn, r"D\(u, 2\) is deprecated.*Differential\(t\)") match_mode=:any D(u, 2)
        end

        @testset "D(D(u)) emits depwarn on the chained call" begin
            @test_logs (:warn, r"deprecated") match_mode=:any D(D(u))
        end

        @testset "deprecated D produces same value as canonical Differential" begin
            # Result equality bypasses depwarn-shape checks: just compare structures.
            d_via_D = D(u)
            d_via_Differential = Differential(t)(u)
            @test d_via_D.steps == d_via_Differential.steps
            @test d_via_D.funcname == d_via_Differential.funcname

            d2_via_D = D(u, 2)
            d2_via_Differential = Differential(t)(Differential(t)(u))
            @test d2_via_D.steps == d2_via_Differential.steps

            d2_chain_D = D(D(u))
            @test d2_chain_D.steps == d2_via_Differential.steps
        end

        @testset "warn-once-per-callsite (Base.depwarn dedupe)" begin
            # Base.depwarn deduplicates by (funcsym, file, line). Two calls from
            # the same Julia line produce only one warning per session. We rely on
            # Julia's documented Base.depwarn behavior; this test simply asserts
            # that repeated D calls at the same site return correct values without
            # error (warning emission shape covered by other tests above).
            f() = (D(u); D(u))
            d1, d2 = f(), f()
            @test d1 isa DerivativeExpr
            @test d2 isa DerivativeExpr
            @test d1.steps == d2.steps == [("t", 1)]
        end
    end

    # spec 068 US2 — multi-arg D(f) ambiguity guard
    @testset "D(f) ambiguity guard on multi-arg function (068-multivar-d-operator US2)" begin
        @giac_var x y f(x, y)
        # D(f) on multi-arg function must raise ArgumentError, not silently differentiate.
        err = nothing
        try
            D(f)
        catch e
            err = e
        end
        @test err isa ArgumentError
        msg = err.msg
        @test occursin("f", msg)
        @test occursin("x", msg)
        @test occursin("y", msg)
        @test occursin("Differential(x)(f)", msg)
        @test occursin("deprecated", msg)

        # D(f, n) on multi-arg also raises with the same shape
        err2 = nothing
        try
            D(f, 2)
        catch e
            err2 = e
        end
        @test err2 isa ArgumentError
        @test occursin("multiple arguments", err2.msg)
        @test occursin("Differential", err2.msg)

        # Three-variable case
        @giac_var a b c g(a, b, c)
        err3 = nothing
        try
            D(g)
        catch e
            err3 = e
        end
        @test err3 isa ArgumentError
        msg3 = err3.msg
        @test occursin("g", msg3)
        @test occursin("a", msg3)
        @test occursin("b", msg3)
        @test occursin("c", msg3)

        # Mono-var D(u) still succeeds (regression guard)
        @giac_var u(t)
        @test D(u) isa DerivativeExpr
    end

    # spec 068 — foundational refactor of DerivativeExpr (multi-step)
    @testset "DerivativeExpr multi-step (068-multivar-d-operator)" begin
        @giac_var x y f(x, y)

        @testset "manual multi-step construction → string is nested diff" begin
            d_xy = DerivativeExpr(f, "f", Tuple{String, Int}[("x", 1), ("y", 1)])
            @test string(d_xy) == "diff(diff(f(x,y),x),y)"

            d_x2y = DerivativeExpr(f, "f", Tuple{String, Int}[("x", 2), ("y", 1)])
            @test string(d_x2y) == "diff(diff(f(x,y),x,2),y)"
        end

        @testset "mono-step DerivativeExpr keeps single diff form" begin
            @giac_var u(t)
            @test string(D(u)) == "diff(u(t),t)"
            @test string(D(u, 2)) == "diff(u(t),t,2)"
        end

        @testset "multi-step show uses ∂-style notation (right-to-left)" begin
            # Convention: in ∂ⁿf/∂v₁…∂vₙ the rightmost variable is applied first,
            # the leftmost last — consistent with the operator product
            # (∂/∂v₁)·…·(∂/∂vₙ) f. Therefore `steps` (innermost-first) is
            # reversed in the denominator.
            d_xy = DerivativeExpr(f, "f", Tuple{String, Int}[("x", 1), ("y", 1)])
            io = IOBuffer()
            show(io, d_xy)
            @test String(take!(io)) == "D: ∂²f/∂y∂x"

            d_x2y = DerivativeExpr(f, "f", Tuple{String, Int}[("x", 2), ("y", 1)])
            io = IOBuffer()
            show(io, d_x2y)
            @test String(take!(io)) == "D: ∂³f/∂y∂x²"
        end

        @testset "(d::DerivativeExpr)(args...) raises on multi-step" begin
            d_xy = DerivativeExpr(f, "f", Tuple{String, Int}[("x", 1), ("y", 1)])
            @test_throws ArgumentError d_xy(0, 0)
        end

        @testset "D(::DerivativeExpr) raises on multi-step" begin
            d_xy = DerivativeExpr(f, "f", Tuple{String, Int}[("x", 1), ("y", 1)])
            @test_throws ArgumentError D(d_xy)
            @test_throws ArgumentError D(d_xy, 2)
        end

        @testset "_to_giac_expr on mono-step still works (arithmetic surface)" begin
            @giac_var u(t)
            # If this round-trips through giac_eval correctly, arithmetic ops keep working.
            result = D(u) + u
            @test result isa GiacExpr
            @test occursin("diff", string(result))
        end
    end
end
