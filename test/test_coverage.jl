# Additional tests to improve code coverage for uncovered but valid code paths

# ============================================================================
# 1. Iteration edge cases (src/iteration.jl)
# ============================================================================
@testset "Iteration Coverage" begin
    @testset "Scalar iteration" begin
        # Iterating over a non-vector GiacExpr yields itself once
        x = giac_eval("42")
        # Use iterate directly since collect may use getindex which throws for scalars
        result = iterate(x)
        @test result !== nothing
        @test string(result[1]) == "42"
        # Second call should return nothing (single element)
        result2 = iterate(x, result[2])
        @test result2 === nothing
    end

    @testset "Scalar length and size" begin
        x = giac_eval("42")
        @test length(x) == 1
        @test size(x) == (1,)
        @test firstindex(x) == 1
        @test lastindex(x) == 1
        @test collect(eachindex(x)) == [1]
    end

    @testset "Vector iteration" begin
        v = giac_eval("[1,2,3]")
        collected = collect(v)
        @test length(collected) == 3
        @test string(collected[1]) == "1"
        @test string(collected[2]) == "2"
        @test string(collected[3]) == "3"
    end

    @testset "giac_matrix iteration" begin
        v1 = giac_eval("matrix[[1],[2]]")      # 2×1 matrix
        v2 = giac_eval("matrix[[1, 2]]")       # 1×2 matrix
        v3 = giac_eval("matrix[[1, 2],[3,4]]") # 2×2 matrix
        v4 = giac_eval("matrix[]")             # 0×0 matrix

        # check for matrix subtype of VECT
        # where is this valuedocumented?
        @test is_vector(v1) && Giac.Commands.subtype(v1) == 11
        @test is_vector(v2) && Giac.Commands.subtype(v2) == 11
        @test is_vector(v3) && Giac.Commands.subtype(v3) == 11
        @test is_vector(v4) && Giac.Commands.subtype(v4) == 11

        @test size(v1) == (2, 1)
        @test size(v2) == (1, 2)
        @test size(v3) == (2, 2)
        @test size(v4) == (0, 0)

        @test [v1[i] for i in eachindex(v1)] == [v2[i] for i in eachindex(v2)]
        @test collect(GiacExpr, v1) != collect(GiacExpr, v2)

        @test size(collect(GiacExpr, v1)) == (2,1)
        @test size(collect(GiacExpr, v2)) == (1,2)
        @test size(collect(GiacExpr, v3)) == (2,2)
        @test size(collect(GiacExpr, v4)) == (0,0)

        @test [to_julia(x) for x in v1] == [1;2;;]
        @test [to_julia(x) for x in v2] == [1 2]
        @test [to_julia(x) for x in v3] == [1 2; 3 4]
        @test isempty([to_julia(x) for x in v4])

    end


    @testset "Scalar in operator" begin
        # in() on a non-vector compares string representations
        x = giac_eval("42")
        @test giac_eval("42") in x
        @test !(giac_eval("43") in x)
    end

    @testset "Vector keys/values/pairs" begin
        v = giac_eval("[10,20,30]")
        ks = collect(keys(v))
        @test ks == [1, 2, 3]
        vs = collect(values(v))
        @test length(vs) == 3
        @test string(vs[2]) == "20"
        ps = collect(pairs(v))
        @test ps[1][1] == 1
        @test string(ps[1][2]) == "10"
    end

    @testset "Vector slicing" begin
        v = giac_eval("[1,2,3,4,5]")
        sliced = v[2:4]
        @test length(sliced) == 3
        @test string(sliced[1]) == "2"

        all_elems = v[:]
        @test length(all_elems) == 5
    end

    @testset "Indexing errors" begin
        x = giac_eval("42")
        @test_throws ErrorException x[1]

        v = giac_eval("[1,2,3]")
        @test_throws BoundsError v[0]
        @test_throws BoundsError v[4]

        # Range indexing on non-vector
        @test_throws ErrorException x[1:2]
    end

    @testset "broadcast over collections" begin

        λ(x) = x + 1

        # broadcasting scalars:
        x = giac_eval("42")
        @test λ.(x) == 43

        # is_vector
        x = [42, 44, 21]
        lst = giac_eval("$(repr(x))")
        @test λ.(lst) == GiacExpr[(x .+ 1)...]
        @test lst .* lst == x .* x
        @test lst .* lst' == x .* x'
        @test lst .* lst'' != lst .* lst
        @test lst .* lst'' == hcat(lst .* lst) # lst'' is a matrix, not vector
        @test lst .* lst'' == lst .* lst''''   # lst'' == lst'''

        # same as map
        u = giac_eval("[1,2,3]")
        @test map(first, u) == first.(u)
        @test map(+, u, u) == u .+ u

        # vector of vectors
        u = giac_eval("[[1,2],[3,4]]")
        @test map(first, u) == first.(u)

        # GiacMatrix
        N = [1 2; 3 4]
        M = GiacMatrix(N)
        @test sin.(M) == collect(GiacExpr, map(sin, M))
        @test M .* M' == N .* N'
        @test Base.Broadcast.broadcast(+, GiacMatrix([1 0; 0 1]), giac_eval("[1, 4]")) == [2 1; 4 5]
        @test Base.Broadcast.broadcast(+, GiacMatrix([1  0]), giac_eval("[1, 4]")) == [2 1; 5 4]
        @test Base.Broadcast.broadcast(+, GiacMatrix([1 0]), 2) == [3 2]

        # lots of splatting
        let x = giac_eval("[[1, 4], [2, 5], [3, 6]]")
            @test .+(x..., .*(x..., x...)..., x[1]..., x[2]..., x[3]...) == [14463, 14472]
        end

        # over nested scalar operations
        a = zeros(GiacExpr, 2)
        a .= 1 .// (1 + 2)
        @test a == [1//3, 1//3]
        a .= 1 .// (1 .+ 3)
        @test a == [1//4, 1//4]
    end

    @testset "broadcastable" begin
        @giac_var x
        @test Base.Broadcast.broadcastable(x)[] == x

        x = [1,2,3]
        u = giac_eval("$(repr(x))")
        @test Base.Broadcast.broadcastable(u) == x

        x = [[1,2], [3,4], [5,6]]
        u = giac_eval("$(repr(x))")
        @test to_julia.(Base.Broadcast.broadcastable(u)) == x

        u = giac_eval("matrix($(repr(x)))")
        @test Base.Broadcast.broadcastable(u) == mapreduce(permutedims, vcat,x)

        x = [1 2; 3 4]
        u = GiacMatrix(x)
        @test Base.Broadcast.broadcastable(u) == x
    end
end

# ============================================================================
# 2. Introspection edge cases (src/introspection.jl)
# ============================================================================
@testset "Introspection Edge Cases" begin
    @testset "numer on integer" begin
        n = giac_eval("5")
        result = Giac.numer(n)
        @test string(result) == "5"
    end

    @testset "denom on integer" begin
        n = giac_eval("5")
        result = Giac.denom(n)
        @test string(result) == "1"
    end

    @testset "numer/denom on fraction" begin
        f = giac_eval("3/7")
        @test string(Giac.numer(f)) == "3"
        @test string(Giac.denom(f)) == "7"
    end

    @testset "real_part on real number" begin
        r = giac_eval("3")
        @test string(Giac.real_part(r)) == "3"
    end

    @testset "imag_part on real number" begin
        r = giac_eval("3")
        @test string(Giac.imag_part(r)) == "0"
    end

    @testset "real_part/imag_part on complex" begin
        c = giac_eval("3+4*i")
        @test string(Giac.real_part(c)) == "3"
        @test string(Giac.imag_part(c)) == "4"
    end

    @testset "Type predicates" begin
        @test Giac.is_integer(giac_eval("42"))
        @test !Giac.is_integer(giac_eval("3.14"))
        @test Giac.is_numeric(giac_eval("42"))
        @test Giac.is_numeric(giac_eval("3.14"))
        @test !Giac.is_numeric(giac_eval("x"))
        @test Giac.is_vector(giac_eval("[1,2,3]"))
        @test !Giac.is_vector(giac_eval("42"))
        @test Giac.is_symbolic(giac_eval("sin(x)"))
        @test !Giac.is_symbolic(giac_eval("42"))
        @test Giac.is_identifier(giac_eval("x"))
        @test !Giac.is_identifier(giac_eval("42"))
        @test Giac.is_fraction(giac_eval("3/4"))
        @test !Giac.is_fraction(giac_eval("42"))
        @test Giac.is_boolean(giac_eval("true"))
        @test Giac.is_boolean(giac_eval("false"))
        @test !Giac.is_boolean(giac_eval("1"))
    end

    @testset "symb_funcname and symb_argument" begin
        s = giac_eval("sin(x)")
        @test Giac.symb_funcname(s) == "sin"
        arg = Giac.symb_argument(s)
        @test string(arg) == "x"
    end

    @testset "Error on non-fraction numer/denom" begin
        x = giac_eval("x")
        @test_throws GiacError Giac.numer(x)
        @test_throws GiacError Giac.denom(x)
    end

    @testset "Error on non-symbolic symb_funcname/symb_argument" begin
        n = giac_eval("42")
        @test_throws GiacError Giac.symb_funcname(n)
        @test_throws GiacError Giac.symb_argument(n)
    end
end

# ============================================================================
# 3. HeldCmd LaTeX edge cases (src/held_cmd.jl)
# ============================================================================
@testset "HeldCmd LaTeX Coverage" begin
    @giac_var x t s n k

    @testset "Directional limits" begin
        # Left limit (dir = -1)
        lim_left = hold_cmd(:limit, giac_eval("1/x"), x, giac_eval("0"), giac_eval("-1"))
        latex_left = sprint(show, MIME("text/latex"), lim_left)
        @test occursin("\\lim", latex_left)
        @test occursin("^-", latex_left)

        # Right limit (dir = 1)
        lim_right = hold_cmd(:limit, giac_eval("1/x"), x, giac_eval("0"), giac_eval("1"))
        latex_right = sprint(show, MIME("text/latex"), lim_right)
        @test occursin("\\lim", latex_right)
        @test occursin("^+", latex_right)
    end

    @testset "Limit with fewer args" begin
        # 2 args
        lim2 = hold_cmd(:limit, giac_eval("1/x"), x)
        latex2 = sprint(show, MIME("text/latex"), lim2)
        @test occursin("\\lim", latex2)

        # 1 arg
        lim1 = hold_cmd(:limit, giac_eval("1/x"))
        latex1 = sprint(show, MIME("text/latex"), lim1)
        @test occursin("\\lim", latex1)
    end

    @testset "Sum and product" begin
        h_sum = hold_cmd(:sum, giac_eval("k^2"), k, giac_eval("1"), giac_eval("10"))
        latex_sum = sprint(show, MIME("text/latex"), h_sum)
        @test occursin("\\sum", latex_sum)

        h_prod = hold_cmd(:product, giac_eval("k"), k, giac_eval("1"), giac_eval("5"))
        latex_prod = sprint(show, MIME("text/latex"), h_prod)
        @test occursin("\\prod", latex_prod)
    end

    @testset "Sum/product with fewer args" begin
        # 2 args
        h2 = hold_cmd(:sum, giac_eval("k^2"), k)
        latex2 = sprint(show, MIME("text/latex"), h2)
        @test occursin("\\sum", latex2)

        # 1 arg
        h1 = hold_cmd(:sum, giac_eval("k^2"))
        latex1 = sprint(show, MIME("text/latex"), h1)
        @test occursin("\\sum", latex1)
    end

    @testset "HeldEquation with Number" begin
        eq = HeldEquation(giac_eval("x^2"), 0)
        latex_str = sprint(show, MIME("text/latex"), eq)
        @test occursin("=", latex_str)
        @test occursin("0", latex_str)
    end

    @testset "HeldEquation with HeldCmd on left" begin
        held = hold_cmd(:integrate, giac_eval("x^2"), x)
        eq = HeldEquation(held, giac_eval("x^3/3"))
        latex_str = sprint(show, MIME("text/latex"), eq)
        @test occursin("\\int", latex_str)
        @test occursin("=", latex_str)
    end

    @testset "HeldEquation with HeldCmd on both sides" begin
        lhs = hold_cmd(:diff, giac_eval("x^3/3"), x)
        rhs = hold_cmd(:integrate, giac_eval("x"), x)
        eq = HeldEquation(lhs, rhs)
        latex_str = sprint(show, MIME("text/latex"), eq)
        @test occursin("\\frac{d}{dx}", latex_str)
        @test occursin("=", latex_str)
    end

    @testset "HeldEquation plain text" begin
        held = hold_cmd(:factor, giac_eval("x^2-1"))
        eq = HeldEquation(held, giac_eval("(x-1)*(x+1)"))
        txt = sprint(show, eq)
        @test occursin("=", txt)
        @test occursin("factor", txt)

        txt_plain = sprint(show, MIME("text/plain"), eq)
        @test occursin("=", txt_plain)
    end

    @testset "Tilde operator creates HeldEquation" begin
        held = hold_cmd(:factor, giac_eval("x^2-1"))
        eq1 = held ~ giac_eval("(x-1)*(x+1)")
        @test eq1 isa HeldEquation

        eq2 = giac_eval("x^2") ~ held
        @test eq2 isa HeldEquation

        held2 = hold_cmd(:diff, x, x)
        eq3 = held ~ held2
        @test eq3 isa HeldEquation

        eq4 = held ~ 42
        @test eq4 isa HeldEquation

        eq5 = 42 ~ held
        @test eq5 isa HeldEquation
    end

    @testset "LaTeX: ilaplace alias" begin
        h = hold_cmd(:ilaplace, giac_eval("1/s"), s, t)
        latex = sprint(show, MIME("text/latex"), h)
        @test occursin("\\mathcal{L}^{-1}", latex)
    end

    @testset "LaTeX: ztransform alias" begin
        # Use HeldCmd constructor directly to test LaTeX rendering without command validation
        h = HeldCmd(:ztransform, (giac_eval("n"), n, giac_eval("z")))
        latex = sprint(show, MIME("text/latex"), h)
        @test occursin("\\mathcal{Z}", latex)
    end

    @testset "LaTeX: invztransform alias" begin
        h = HeldCmd(:invztransform, (giac_eval("1/z"), giac_eval("z"), n))
        latex = sprint(show, MIME("text/latex"), h)
        @test occursin("\\mathcal{Z}^{-1}", latex)
    end

    @testset "LaTeX: transform with fewer args" begin
        # 1 arg
        h1 = hold_cmd(:laplace, giac_eval("sin(t)"))
        latex1 = sprint(show, MIME("text/latex"), h1)
        @test occursin("\\mathcal{L}", latex1)

        # 0 args (edge case)
        h0 = hold_cmd(:laplace)
        latex0 = sprint(show, MIME("text/latex"), h0)
        @test occursin("\\mathcal{L}", latex0)

        # inv with 1 arg
        h1i = hold_cmd(:invlaplace, giac_eval("1/s"))
        latex1i = sprint(show, MIME("text/latex"), h1i)
        @test occursin("\\mathcal{L}^{-1}", latex1i)

        # inv with 0 args
        h0i = hold_cmd(:invlaplace)
        latex0i = sprint(show, MIME("text/latex"), h0i)
        @test occursin("\\mathcal{L}^{-1}", latex0i)
    end

    @testset "LaTeX: integrate with 1 arg" begin
        h = hold_cmd(:integrate, giac_eval("x^2"))
        latex = sprint(show, MIME("text/latex"), h)
        @test occursin("\\int", latex)
    end

    @testset "LaTeX: diff with 1 arg" begin
        h = hold_cmd(:diff, giac_eval("x^2"))
        latex = sprint(show, MIME("text/latex"), h)
        @test occursin("\\frac{d}{d?}", latex)
    end

    @testset "HeldCmd text/plain show" begin
        h = hold_cmd(:factor, giac_eval("x^2-1"))
        txt = sprint(show, MIME("text/plain"), h)
        @test occursin("HeldCmd:", txt)
        @test occursin("factor", txt)
    end

    @testset "_arg_to_latex edge cases" begin
        # Symbol arg
        h = hold_cmd(:diff, giac_eval("x^2"), :x)
        latex = sprint(show, MIME("text/latex"), h)
        @test occursin("dx", latex)

        # String arg in generic command
        h_str = HeldCmd(:foo, ("hello",))
        latex_str = sprint(show, MIME("text/latex"), h_str)
        @test occursin("\\text{hello}", latex_str)

        # Vector arg in generic command
        h_vec = HeldCmd(:bar, ([1, 2, 3],))
        latex_vec = sprint(show, MIME("text/latex"), h_vec)
        @test occursin("[1, 2, 3]", latex_vec)
    end

    @testset "Generic fallback with no args" begin
        h = HeldCmd(:foo, ())
        latex = sprint(show, MIME("text/latex"), h)
        @test occursin("\\mathrm{foo}", latex)
        @test occursin("()", latex)
    end
end

# ============================================================================
# 4. GiacExpr method syntax (src/types.jl)
# ============================================================================
@testset "GiacExpr Method Syntax" begin
    @testset "Method-style command access" begin
        expr = giac_eval("x^2 - 1")
        result = expr.factor()
        @test string(result) == "(x-1)*(x+1)"
    end

    @testset "Method-style with additional args" begin
        @giac_var x
        expr = giac_eval("x^2")
        result = expr.integrate(x)
        @test occursin("x^3", string(result))
    end

    @testset "propertynames" begin
        expr = giac_eval("42")
        @test propertynames(expr) == (:ptr,)
    end
end
