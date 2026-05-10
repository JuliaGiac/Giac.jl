# Spec 068 — multivar D operator
# Tests for Differential and the multi-variable derivative surface.
using Test
using Giac

@testset "spec 068 — multivar D operator" begin

    # ------------------------------------------------------------------
    # Foundational helpers: _append_step
    # ------------------------------------------------------------------
    @testset "_append_step collapses adjacent same-variable steps" begin
        T = Tuple{String, Int}

        # empty + step → singleton
        @test Giac._append_step(T[], ("x", 1)) == T[("x", 1)]

        # same-var adjacent → collapse
        @test Giac._append_step(T[("x", 1)], ("x", 1)) == T[("x", 2)]
        @test Giac._append_step(T[("x", 2)], ("x", 3)) == T[("x", 5)]

        # different var → append (no collapse)
        @test Giac._append_step(T[("x", 1)], ("y", 1)) == T[("x", 1), ("y", 1)]

        # non-adjacent same-var → append (no collapse)
        @test Giac._append_step(T[("x", 1), ("y", 1)], ("x", 1)) ==
              T[("x", 1), ("y", 1), ("x", 1)]

        # only the last step is collapsed against
        @test Giac._append_step(T[("y", 1), ("x", 1)], ("x", 1)) ==
              T[("y", 1), ("x", 2)]
    end

    # ------------------------------------------------------------------
    # US1 — canonical Differential, function-form mono-variable
    # ------------------------------------------------------------------
    @testset "Differential mono-variable function-form (US1)" begin
        @giac_var t u(t)
        Dt = Differential(t)
        du = Dt(u)
        @test du isa DerivativeExpr
        @test du.steps == [("t", 1)]
        @test du.funcname == "u"
        @test string(du) == "diff(u(t),t)"

        # Show on Differential prints variable
        io = IOBuffer()
        show(io, Dt)
        @test String(take!(io)) == "Differential(t)"
    end

    # ------------------------------------------------------------------
    # US1 — multi-variable function-form (partials, cross, higher-order)
    # ------------------------------------------------------------------
    @testset "Differential multi-variable function-form (US1)" begin
        @giac_var x y f(x, y)
        Dx = Differential(x)
        Dy = Differential(y)

        # Simple partials
        df_dx = Dx(f)
        @test df_dx isa DerivativeExpr
        @test df_dx.steps == [("x", 1)]
        @test df_dx.funcname == "f"
        @test string(df_dx) == "diff(f(x,y),x)"

        df_dy = Dy(f)
        @test df_dy.steps == [("y", 1)]
        @test string(df_dy) == "diff(f(x,y),y)"

        # Higher-order (same var) — adjacent steps collapse
        d2f_dx2 = Dx(Dx(f))
        @test d2f_dx2.steps == [("x", 2)]
        @test string(d2f_dx2) == "diff(f(x,y),x,2)"

        # Cross partial — distinct vars don't collapse
        d2f_dxdy = Dy(Dx(f))
        @test d2f_dxdy.steps == [("x", 1), ("y", 1)]
        @test string(d2f_dxdy) == "diff(diff(f(x,y),x),y)"
    end

    # ------------------------------------------------------------------
    # US1 — three-variable composition + value equivalence
    # ------------------------------------------------------------------
    @testset "Differential three-variable composition + value (US1)" begin
        @giac_var x y z g(x, y, z)
        d_xyz = Differential(z)(Differential(y)(Differential(x)(g)))
        @test d_xyz.steps == [("x", 1), ("y", 1), ("z", 1)]
        @test string(d_xyz) == "diff(diff(diff(g(x,y,z),x),y),z)"

        # Value equivalence: ∂/∂x of (x^2*y + sin(y)) → 2*x*y
        @giac_var a b
        Dx = Differential(a)
        # bare-expression form lands in US4 — for now, build through the function-form
        # by declaring the expression as a function.
        @giac_var h(a, b)
        # We can't redefine h to equal a specific expression, but we can verify
        # that string(Differential(a)(h)) is "diff(h(a,b),a)" — value-side check
        # of the bare-expression flavor lands in US4.
        @test string(Dx(h)) == "diff(h(a,b),a)"
    end

    # ------------------------------------------------------------------
    # US4 — bare-expression differentiation (Differential matches SymPy/Symbolics)
    # ------------------------------------------------------------------
    @testset "Differential on bare expressions (US4)" begin
        @giac_var x y z

        # ∂/∂x of x^2 + y*x = 2x + y
        result = Differential(x)(x^2 + y*x)
        @test result isa GiacExpr
        @test !(result isa DerivativeExpr)
        # Compare via simplification: 2*x + y
        s = string(result)
        # GIAC may return "2*x+y" or "y+2*x" depending on canonicalization; check both terms.
        @test occursin("2*x", s) && occursin("y", s)

        # ∂/∂x of sin(x) is cos(x) (round-trip through GIAC's diff)
        result_sin = Differential(x)(sin(x))
        @test result_sin isa GiacExpr
        @test occursin("cos", string(result_sin))

        # ∂²/∂x² of x^3 = 6*x   (GIAC may print as "3*2*x" without auto-simplifying;
        # use simplify to canonicalize before comparing)
        result_x3 = Differential(x)(Differential(x)(x^3))
        @test result_x3 isa GiacExpr
        simplified_x3 = Giac.Commands.simplify(result_x3)
        @test occursin("6*x", string(simplified_x3))

        # Cross partial: ∂²/∂x∂y of x*y^2 = 2*y
        result_xy = Differential(y)(Differential(x)(x*y^2))
        @test result_xy isa GiacExpr
        simplified_xy = Giac.Commands.simplify(result_xy)
        @test occursin("2*y", string(simplified_xy))

        # Absent variable → 0 (CAS convention)
        result_zero = Differential(z)(x^2 + y)
        @test result_zero isa GiacExpr
        @test string(result_zero) == "0"
    end

    # ------------------------------------------------------------------
    # Differential(var, n) — Symbolics.jl-style n-th order constructor
    # ------------------------------------------------------------------
    @testset "Differential(var, n) constructor (068-multivar-d-operator)" begin
        @giac_var x y t f(x, y) u(t)

        @testset "constructor + show" begin
            D1 = Differential(x)
            @test D1.order == 1
            io = IOBuffer(); show(io, D1)
            @test String(take!(io)) == "Differential(x)"

            D2 = Differential(x, 2)
            @test D2.order == 2
            io = IOBuffer(); show(io, D2)
            @test String(take!(io)) == "Differential(x, 2)"

            # invalid orders
            @test_throws ArgumentError Differential(x, 0)
            @test_throws ArgumentError Differential(x, -1)
        end

        @testset "function-form: Differential(x, n)(f) ≡ Dx applied n times" begin
            # Order 2 same-var
            d_via_n = Differential(x, 2)(f)
            d_via_chain = Differential(x)(Differential(x)(f))
            @test d_via_n.steps == d_via_chain.steps == [("x", 2)]

            # Order 3 mono-variable
            d3 = Differential(t, 3)(u)
            @test d3.steps == [("t", 3)]
            @test string(d3) == "diff(u(t),t,3)"
        end

        @testset "function-form: composition with Differential(_, n)" begin
            # Differential(x, 2) on top of an existing Differential(y)(f)
            mid = Differential(y)(f)         # steps = [("y", 1)]
            full = Differential(x, 2)(mid)   # append ("x", 2) — distinct var, no collapse
            @test full.steps == [("y", 1), ("x", 2)]

            # Same-variable: Differential(y, 2) on top of Differential(y)(f) collapses
            mid2 = Differential(y)(f)        # steps = [("y", 1)]
            full2 = Differential(y, 2)(mid2) # append ("y", 2) — collapses to ("y", 3)
            @test full2.steps == [("y", 3)]
        end

        @testset "bare-expression: Differential(x, n)(expr)" begin
            # Differential(x, 2)(x^3) = 6*x  (after simplify)
            result = Differential(x, 2)(x^3)
            @test result isa GiacExpr
            @test !(result isa DerivativeExpr)
            simplified = Giac.Commands.simplify(result)
            @test occursin("6*x", string(simplified))
        end
    end

    @testset "Return-type discipline: function-form vs bare (US4)" begin
        @giac_var x y f(x, y)
        # function-form → DerivativeExpr
        @test Differential(x)(f) isa DerivativeExpr
        # bare-expression → plain GiacExpr (NOT DerivativeExpr)
        @test Differential(x)(x^2 + y*x) isa GiacExpr
        @test !(Differential(x)(x^2 + y*x) isa DerivativeExpr)
    end

    # ------------------------------------------------------------------
    # US1 — ODE workflow (Differential composes with desolve)
    # ------------------------------------------------------------------
    @testset "Differential ODE workflow with desolve (US1)" begin
        using Giac.Commands: desolve
        @giac_var t u(t)
        Dt = Differential(t)

        # u'' + u = 0, u(0) = 1, u'(0) = 0  →  cos(t)
        ode = Dt(Dt(u)) + u ~ 0
        @test ode isa GiacExpr
        @test occursin("diff", string(ode))

        u0 = u(0) ~ 1
        du0 = Dt(u)(0) ~ 0
        @test du0 isa DerivativeCondition
        @test string(du0) == "u'(0)=0"

        result = desolve([ode, u0, du0], t, :u)
        @test occursin("cos", string(result))
    end

end

