# assumptions(x): what GIAC assumes of a variable, as a structured record instead of the string
# `about(x)` prints (MathInterchange's feedback, point 6).

@testset "assumptions" begin
    C = Giac.Commands
    S = string
    ends(a) = [(S(i.lo), S(i.hi), i.lo_closed, i.hi_closed) for i in a.intervals]

    @testset "a free variable" begin
        @giac_var g
        a = assumptions(g)
        @test a isa Giac.Assumptions
        @test a.domain === nothing && isempty(a.intervals) && isempty(a.excluded) && a.value === nothing
        @test isempty(a)
        @test S(a.raw) == "g"
    end

    @testset "an interval, open at an excluded end" begin
        @giac_var a
        C.assume((a > 0) & (a <= 10))
        r = assumptions(a)
        @test r.domain === nothing
        @test ends(r) == [("0", "10", false, true)]           # ]0, 10]
        @test S.(r.excluded) == ["0"]
        @test S(r.raw) == "assume[[],[line[0,10]],[0]]"
        @test !isempty(r)
    end

    @testset "a closed end, and infinite ends are open" begin
        @giac_var r
        C.assume(r >= 1)
        @test ends(assumptions(r)) == [("1", "+infinity", true, false)]
    end

    @testset "a domain with a range" begin
        @giac_var b::(integer, >(2))
        r = assumptions(b)
        @test r.domain === :integer
        @test ends(r) == [("2", "+infinity", false, false)]
    end

    @testset "a domain alone" begin
        @giac_var d::real z::complex q::rational
        @test assumptions(d).domain === :real && isempty(assumptions(d).intervals)
        @test assumptions(z).domain === :complex
        @test assumptions(q).domain === :rational
    end

    @testset "a disjunction is a union of intervals" begin
        @giac_var c
        C.assume((c < 0) | (c > 10))
        @test ends(assumptions(c)) == [("-infinity", "0", false, false), ("10", "+infinity", false, false)]
    end

    @testset "a value" begin
        @giac_var f
        giac_eval("f:=5")
        r = assumptions(f)
        @test S(r.value) == "5" && r.domain === nothing && isempty(r.intervals)
        C.purge(f)
    end

    @testset "display" begin
        @giac_var p q n m u
        @test sprint(show, assumptions(p)) == "Assumptions(none)"
        C.assume((q > 0) & (q <= 10))
        @test sprint(show, assumptions(q)) == "Assumptions(]0, 10])"
        @giac_var n::(integer, >=(2))
        @test sprint(show, assumptions(n)) == "Assumptions(integer, [2, +infinity[)"
        C.assume((m < 0) | (m > 1))
        @test sprint(show, assumptions(m)) == "Assumptions(]-infinity, 0[ ∪ ]1, +infinity[)"
        giac_eval("u:=7")
        @test sprint(show, assumptions(u)) == "Assumptions(value 7)"
        C.purge(u)
    end

    @testset "a condition GIAC does not record is not in the record" begin
        # GIAC keeps no trace of x != 3: the record shows what reached it
        @giac_var h
        C.assume(h, "real")
        C.additionally(h != 3)
        r = assumptions(h)
        @test r.domain === :real && isempty(r.intervals) && isempty(r.excluded)
    end
end
