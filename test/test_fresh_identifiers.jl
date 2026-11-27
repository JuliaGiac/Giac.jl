# Fresh identifiers: Giac names that no value, assumption, command or reserved constant captures
# (MathInterchange's feedback, point 4).

@testset "fresh identifiers" begin
    C = Giac.Commands

    @testset "is_free_identifier" begin
        @test is_free_identifier("x_free_zz")
        @giac_var w::positive
        @test !is_free_identifier("w")                   # assumed
        giac_eval("zz_held := 5")
        @test !is_free_identifier("zz_held")             # assigned
        C.purge(giac_eval("zz_held"))
        for name in ("D", "i", "e", "pi", "sin", "Digits", "infinity")   # reserved or commands
            @test !is_free_identifier(name)
        end
        @test !is_free_identifier("_m")                  # a physical unit
        @test !is_free_identifier("1abc") && !is_free_identifier("a b")
    end

    @testset "fresh_identifier" begin
        a, b = fresh_identifier(), fresh_identifier()
        @test is_identifier(a) && is_identifier(b) && string(a) != string(b)
        @test string(C.about(a)) == string(a)
        @test startswith(string(fresh_identifier("mytmp")), "mytmp_")
        # a name taken in the meantime is skipped
        n = Giac._FRESH_COUNTER[] + 1
        giac_eval("gfr_$(n) := 1")
        t = fresh_identifier("gfr")
        @test string(t) != "gfr_$(n)"
        C.purge(giac_eval("gfr_$(n)"))
        @test_throws ArgumentError fresh_identifier("_unit")
        @test_throws ArgumentError fresh_identifier("1x")
    end

    @testset "with_fresh_identifiers" begin
        names = String[]
        r = with_fresh_identifiers(2) do u, v
            push!(names, string(u), string(v))
            C.assume(u > 0)
            C.simplify(sqrt(u^2)) + v
        end
        @test occursin(names[1], string(r))
        @test all(n -> string(C.about(giac_eval(n))) == n, names)   # purged afterwards
        @test_throws ErrorException with_fresh_identifiers(1) do u
            C.assume(u > 0)
            error("inside")
        end
    end

    @testset "isapprox does not depend on reserved temporary names" begin
        @giac_var x
        # a value bound to the names isapprox used before must not change its answer
        giac_eval("giacjl_isapprox_t1 := 100")
        @test isapprox(x + 0.1 + 0.2, x + 0.3)
        C.purge(giac_eval("giacjl_isapprox_t1"))
    end
end
