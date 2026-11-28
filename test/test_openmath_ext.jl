# GiacOpenMathExt: GIAC expressions to OpenMath objects and back, through the
# giac-openmath table (https://github.com/JuliaGiac/giac-openmath), embedded in
# ext/giac_openmath_table.jl.
#
# Self-contained: OpenMath.jl is not registered, so it is not in the `test`
# target; run_openmath_tests.jl (and the CI-OpenMath job) builds a project with
# Giac, OpenMath and Symbolics and runs this file on its own.

using Test
using Giac
using OpenMath
using SHA
using Downloads
import Symbolics

const OMError = OpenMath.OpenMathConversionError
S(cd, name) = OMSymbol(cd, name)
V(name) = OMVariable(name)
I(n) = OMInteger(n)
lambda(v, body) = OMBinding(S("fns1", "lambda"), [OMBoundVariable(v)], body)
om(g) = OpenMath.to_openmath(g)
quoted(src) = giac_eval("'" * src * "'")        # GIAC's tree, not evaluated
# the same value in GIAC: their difference simplifies to 0 (0.0 for floats); relations,
# which have no difference, print the same
function same(a::GiacExpr, b::GiacExpr)
    relation = Giac.iscall(a) && Giac.symb_funcname(a) in ("=", "==", "!=", "<", ">", "<=", ">=")
    relation && return string(a) == string(b)
    return string(Giac.Commands.simplify(a - b)) in ("0", "0.0")
end
same(a::GiacExpr, b) = same(a, giac_eval(string(b)))

# the message of the error `f()` throws
function error_message(f)
    try
        f()
    catch e
        return sprint(showerror, e)
    end
    return ""
end

@testset "GiacOpenMathExt" begin
    ext = Base.get_extension(Giac, :GiacOpenMathExt)
    @test ext !== nothing

    @testset "the embedded table is giac-openmath's, at its commit" begin
        @test ext.TABLE["format"] == 2
        @test length(ext.TABLE_COMMIT) == 40
        @test bytes2hex(sha256(ext.TABLE_TOML)) == ext.TABLE_SHA256
        # the same bytes as the file in JuliaGiac/giac-openmath at that commit
        url = "https://raw.githubusercontent.com/JuliaGiac/giac-openmath/$(ext.TABLE_COMMIT)/giac-openmath.toml"
        upstream = try
            String(take!(Downloads.download(url, IOBuffer())))
        catch
            nothing
        end
        if upstream === nothing
            @warn "giac-openmath not reachable; the embedded table was not compared with it"
        else
            @test upstream == ext.TABLE_TOML
        end
    end

    @testset "leaves" begin
        @test om(giac_eval("42")) == I(42)
        @test om(giac_eval("-7")) == I(-7)
        @test om(giac_eval("2^100")) == I(big(2)^100)
        @test om(giac_eval("1/2")) == S("nums1", "rational")(I(1), I(2))
        @test om(giac_eval("-3/4")) == S("nums1", "rational")(I(-3), I(4))
        @test om(giac_eval("x")) == V("x")
        @test om(giac_eval("pi")) == S("nums1", "pi")
        @test om(giac_eval("i")) == S("nums1", "i")
        @test om(giac_eval("3+4*i")) == S("complex1", "complex_cartesian")(I(3), I(4))
        @test om(giac_eval("euler_gamma")) == S("nums1", "gamma")
        @test om(giac_eval("true")) == S("logic1", "true")
        @test om(giac_eval("false")) == S("logic1", "false")
        @test om(giac_eval("1.5")) == OMFloat(1.5)
    end

    @testset "GIAC to OpenMath" begin
        x, y = V("x"), V("y")
        @test om(giac_eval("x+y+1")) == S("arith1", "plus")(x, y, I(1)) ||
              om(giac_eval("x+y+1")) == S("arith1", "plus")(I(1), x, y)
        @test om(quoted("x-y")) == S("arith1", "plus")(x, S("arith1", "unary_minus")(y))
        @test om(giac_eval("x/y")) == S("arith1", "times")(x, S("arith1", "divide")(I(1), y))
        @test om(quoted("x/y")) == S("arith1", "divide")(x, y)
        @test om(giac_eval("x^y")) == S("arith1", "power")(x, y)
        @test om(quoted("sqrt(x)")) == S("arith1", "root")(x, I(2))
        @test om(giac_eval("ln(x)")) == S("transc1", "ln")(x)
        @test om(giac_eval("log(x)")) == S("transc1", "ln")(x)                 # GIAC's log is ln
        @test om(quoted("log10(x)")) == S("transc1", "log")(I(10), x)
        @test om(quoted("logb(x, 2)")) == S("transc1", "log")(I(2), x)
        @test om(giac_eval("asin(x)")) == S("transc1", "arcsin")(x)
        @test om(giac_eval("x=y")) == S("relation1", "eq")(x, y)
        @test om(giac_eval("x>y")) == S("relation1", "gt")(x, y)
        @test om(quoted("max(x, y)")) == S("minmax1", "max")(S("set1", "set")(x, y))
        @test om(giac_eval("floor(x)")) == S("rounding1", "floor")(x)
        @test om(giac_eval("+infinity")) == S("nums1", "infinity")
        @test om(giac_eval("-infinity")) == S("arith1", "unary_minus")(S("nums1", "infinity"))
        @test om(quoted("not(a)")) == S("logic1", "not")(V("a"))
    end

    @testset "functions of a bound variable" begin
        x = V("x")
        f = S("arith1", "power")(x, I(2))
        @test om(quoted("integrate(x^2, x)")) ==
              OMApplication(S("calculus1", "int")(lambda("x", f)), [x])
        @test om(quoted("integrate(x^2, x, 0, 1)")) ==
              S("calculus1", "defint")(S("interval1", "interval")(I(0), I(1)), lambda("x", f))
        @test om(quoted("diff(x^2, x)")) ==
              OMApplication(S("calculus1", "diff")(lambda("x", f)), [x])
        @test om(quoted("limit(x^2, x, 0, 1)")) ==
              S("limit1", "limit")(I(0), S("limit1", "above"), lambda("x", f))
        @test om(quoted("limit(x^2, x, 0)")) ==
              S("limit1", "limit")(I(0), S("limit1", "both_sides"), lambda("x", f))
        @test om(quoted("sum(k^2, k, 1, n)")) ==
              S("arith1", "sum")(S("interval1", "integer_interval")(I(1), V("n")),
                                 lambda("k", S("arith1", "power")(V("k"), I(2))))
    end

    @testset "refused, with the table's reason" begin
        @test_throws OMError om(quoted("irem(a, b)"))
        @test occursin("dividend", error_message(() -> om(quoted("irem(a, b)"))))
        @test_throws OMError om(quoted("x mod 3"))
        @test occursin("residue class", error_message(() -> om(quoted("x mod 3"))))
        @test_throws OMError om(giac_eval("infinity"))         # unsigned
        @test_throws OMError om(giac_eval("undef"))
        @test_throws OMError om(giac_eval("x -> x^2"))
        # not in the table at all
        @test_throws OMError om(quoted("gbasis([x^2], [x])"))
        @test occursin("gbasis", error_message(() -> om(quoted("gbasis([x^2], [x])"))))
        @test_throws OMError om(giac_eval("[1, 2]"))            # lists are not mapped yet
        @test_throws OMError om(giac_eval("\"text\""))
    end

    @testset "OpenMath to GIAC" begin
        x = V("x")
        @test same(Giac.from_openmath(I(3)), 3)
        @test same(Giac.from_openmath(S("nums1", "rational")(I(1), I(2))), "1/2")
        @test same(Giac.from_openmath(S("arith1", "plus")(x, I(1))), "x+1")
        @test same(Giac.from_openmath(S("arith1", "minus")(x, I(1))), "x-1")
        @test same(Giac.from_openmath(S("transc1", "ln")(x)), "ln(x)")
        @test same(Giac.from_openmath(S("transc1", "log")(I(2), x)), "ln(x)/ln(2)")
        @test same(Giac.from_openmath(S("arith1", "root")(x, I(2))), "sqrt(x)")
        @test same(Giac.from_openmath(S("nums1", "pi")), "pi")
        @test same(Giac.from_openmath(S("nums1", "e")), "exp(1)")
        @test string(Giac.from_openmath(S("nums1", "infinity"))) == "+infinity"
        @test same(Giac.from_openmath(S("minmax1", "max")(S("set1", "set")(I(2), I(5)))), 5)
        @test same(Giac.from_openmath(S("complex1", "complex_cartesian")(I(3), I(4))), "3+4*i")
        @test string(Giac.from_openmath(S("logic1", "true"))) == "true"
        @test same(Giac.from_openmath(OMFloat(0.25)), "0.25")
        # GIAC evaluates what it receives
        f = S("arith1", "power")(x, I(2))
        @test same(Giac.from_openmath(S("calculus1", "defint")(S("interval1", "interval")(I(0), I(1)),
                                                             lambda("x", f))), "1/3")
        @test same(Giac.from_openmath(OMApplication(S("calculus1", "int")(lambda("x", f)), [x])), "x^3/3")
        @test same(Giac.from_openmath(OMApplication(S("calculus1", "diff")(lambda("x", f)), [x])), "2*x")
    end

    @testset "the result and GIAC's messages" begin
        # GIAC evaluates what from_openmath gives it; evaluate_with_diagnostics keeps
        # both the value and what GIAC said meanwhile
        x = V("x")
        o = OMApplication(S("calculus1", "int")(lambda("x", S("arith1", "abs")(x))), [x])
        r = evaluate_with_diagnostics(() -> Giac.from_openmath(o))
        @test r.value isa GiacExpr
        @test same(Giac.Commands.diff(r.value, giac_eval("x")), "abs(x)")
        @test any(d -> d.kind == :assumption, r.diagnostics)
    end

    @testset "giac_source: the GIAC input, not evaluated" begin
        x = V("x")
        src = Giac.giac_source(S("calculus1", "defint")(S("interval1", "interval")(I(0), I(1)),
                                                       lambda("x", S("arith1", "power")(x, I(2)))))
        @test occursin("integrate(", src)
        @test same(giac_eval(src), "1/3")
        @test Giac.giac_source(S("arith1", "plus")(x, I(1))) == "(x) + (1)"
    end

    @testset "OpenMath refused or out of the table" begin
        x, y = V("x"), V("y")
        @test_throws OMError Giac.from_openmath(S("integer1", "remainder")(I(7), I(3)))
        # the table refuses integer1.remainder as the false friend of GIAC's % (x mod n)
        @test occursin("residue class", error_message(() -> Giac.from_openmath(S("integer1", "remainder")(I(7), I(3)))))
        @test_throws OMError Giac.from_openmath(S("linalg1", "determinant")(x))
        # an antiderivative applied at another variable than its own
        @test_throws OMError Giac.from_openmath(OMApplication(S("calculus1", "int")(lambda("x", x)), [y]))
        # minmax1.max of something else than a set
        @test_throws OMError Giac.from_openmath(S("minmax1", "max")(x))
        # a variable named as a GIAC constant would change meaning
        @test_throws OMError Giac.from_openmath(V("e"))
        @test_throws OMError Giac.from_openmath(V("pi"))
        @test_throws OMError Giac.from_openmath(V("_x"))             # a GIAC unit, not a name
        @test_throws OMError Giac.from_openmath(OMString("text"))
    end

    @testset "round trips through OpenMath" begin
        for src in ["x^2+3*x-1", "sin(x)*exp(-x)", "ln(x)/(1+x^2)", "atan(x)+acos(x)",
                    "abs(x-1)+floor(x)", "sqrt(2)*x", "x^(1/3)", "(x+1)/(x-1)", "pi*x/2",
                    "factorial(n)", "x>=0", "max(x,y)"]
            g = giac_eval(src)
            back = Giac.from_openmath(om(g))
            @test same(back, g)
        end
    end

    @testset "against OpenMath.jl's Symbolics phrasebook" begin
        # The same expression written to OpenMath by OpenMath.jl from Symbolics, and read into
        # GIAC by this phrasebook, is what Giac.jl's own Symbolics bridge gives
        Symbolics.@variables x y
        for s in [x^2 + 3x - 1, sin(x) * exp(x), log(x) + cos(x)^2, x / (1 + y), sqrt(x) + abs(y),
                  x^(1 // 3), exp(-x^2), atan(x) - asin(y)]
            from_symbolics = Giac.from_openmath(OpenMath.to_openmath(s))
            @test same(from_symbolics, Giac.to_giac(s))
        end
        # and what this phrasebook writes, OpenMath.jl's phrasebook reads back
        p = OpenMath.symbolics_phrasebook()
        for src in ["x^2+3*x-1", "sin(x)*exp(x)", "ln(x)+cos(x)^2", "sqrt(x)+abs(x)"]
            g = giac_eval(src)
            s = OpenMath.interpret(p, om(g))
            @test same(Giac.to_giac(Symbolics.Num(s)), g)
        end
    end

    include(joinpath(@__DIR__, "test_openmath_format2.jl"))
end
