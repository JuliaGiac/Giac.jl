# Per-context evaluation.
#
# `GiacContext` is public and `giac_eval(expr, ctx)` has always taken one, but
# the context was ignored: every evaluation funnelled into one process-wide
# `giac::context`, so a `:=` binding made through one context was visible from
# every other and from the default. Tracked upstream as
# libgiac-julia-wrapper#3, and documented as a known limitation in #32.

@testset "Context isolation" begin

    @testset "a binding stays in its own context" begin
        c1 = GiacContext()
        c2 = GiacContext()
        giac_eval("zz1 := 7", c1)
        @test string(giac_eval("zz1", c1)) == "7"
        @test string(giac_eval("zz1", c2)) == "zz1"      # unbound elsewhere
    end

    @testset "contexts do not see each other" begin
        c1 = GiacContext()
        c2 = GiacContext()
        giac_eval("zz2 := 7", c1)
        giac_eval("zz2 := 99", c2)
        @test string(giac_eval("zz2", c1)) == "7"
        @test string(giac_eval("zz2", c2)) == "99"
    end

    @testset "a fresh context starts clean" begin
        c1 = GiacContext()
        giac_eval("zz3 := 42", c1)
        c2 = GiacContext()
        @test string(giac_eval("zz3", c2)) == "zz3"
    end

    @testset "the default context is unchanged" begin
        # Everything that does not name a context shares one process-wide
        # context, as before — the tier-1 paths and introspection re-parse
        # expressions there, so moving the default would split the package
        # in two.
        giac_eval("zz4 := 5")
        @test string(giac_eval("zz4")) == "5"
        @test string(giac_eval("zz4", Giac.DEFAULT_CONTEXT[])) == "5"
        # and an isolated context does not see it
        @test string(giac_eval("zz4", GiacContext())) == "zz4"
    end

    @testset "an isolated binding does not leak to the default" begin
        c = GiacContext()
        giac_eval("zz5 := 123", c)
        @test string(giac_eval("zz5")) == "zz5"
    end

    @testset "evaluation still works in an isolated context" begin
        c = GiacContext()
        @test string(giac_eval("factor(x^2-1)", c)) == "(x-1)*(x+1)"
        @test string(giac_eval("diff(x^3, x)", c)) == "3*x^2"
        giac_eval("f(t) := t^2", c)
        @test string(giac_eval("f(4)", c)) == "16"
    end

    @testset "this is what the MCP server needed" begin
        # `GiacMCPExt` advertises "each call is independent". With one shared
        # context that was aspirational: a user binding leaked into the next
        # call. A fresh context per call makes it true.
        call(expr) = string(giac_eval(expr, GiacContext()))
        call("yy := t*sin(2*t)/4")
        @test call("yy") == "yy"
        @test string(giac_eval("yy")) == "yy"
    end

    @testset "known limitation: a re-parse loses the context" begin
        # A GiacExpr carries its gen, not the context that produced it. An
        # operation that rebuilds it from its printed form resolves free
        # identifiers against the default context. Pinned here so that
        # lifting it is a deliberate change with a docs update, not a
        # silent one.
        giac_eval("ww := 100")
        c = GiacContext()
        giac_eval("ww := 7", c)

        # Eager substitution keeps the common case correct: `ww` is already
        # gone from the printed form, so nothing can re-resolve it.
        @test string(giac_eval("ww + x", c)) == "7+x"

        # But an identifier that survives evaluation is re-read in the
        # default context.
        f = giac_eval("quote(ww) + x", c)
        @test string(f) == "ww+x"
        @test string(Giac.Commands.simplify(f)) == "x+100"   # not x+7
    end

    @testset "contexts are released without taking the process down" begin
        # The C++ context is owned by the Julia object and freed by its
        # finalizer; churning through many of them must not crash or leak
        # unboundedly.
        for i in 1:200
            local c = GiacContext()
            giac_eval("w$i := $i", c)
        end
        GC.gc()
        @test true
    end
end
