# GiacOpenMathExt on the format 2 table: Content Dictionary statuses, bases,
# requests, and the shared corpus of giac-openmath (giac_openmath_corpus.jl). Included by
# test_openmath_ext.jl, whose helpers (S, V, I, lambda, om, quoted, same,
# error_message, OMError) it uses.

using JSON

const PB = "https://juliagiac.github.io/giac-openmath/cd"   # JuliaGiac's CDs

@testset "format 2" begin
    x = V("x")
    sign_x = OMSymbol("giac_math1", "sign"; cdbase = PB)(x)

    @testset "only official CDs, unless the caller enables others" begin
        @test_throws OMError Giac.giac_source(sign_x)
        @test occursin("private", error_message(() -> Giac.giac_source(sign_x)))
        @test Giac.giac_source(sign_x; enable = ["giac_math1"]) == "sign(x)"
        @test same(Giac.from_openmath(sign_x; enable = ["giac_math1"]), "sign(x)")
        @test_throws ArgumentError Giac.giac_source(x; enable = ["no_such_cd"])
    end

    @testset "each symbol at its CD's base, inherited" begin
        inherited = OMApplication(S("giac_math1", "sign"), [x]; cdbase = PB)
        @test Giac.giac_source(inherited; enable = ["giac_math1"]) == "sign(x)"
        @test Giac.giac_source(OMObject(S("giac_math1", "sign")(x); cdbase = PB); enable = ["giac_math1"]) == "sign(x)"
        # giac_math1 at OpenMath's base is another dictionary
        @test occursin("base", error_message(() -> Giac.giac_source(S("giac_math1", "sign")(x); enable = ["giac_math1"])))
        @test occursin("base", error_message(() ->
            Giac.giac_source(OMSymbol("transc1", "ln"; cdbase = "http://example.org/cd")(x))))
    end

    @testset "requests: only in scscp1.procedure_call, not evaluated yet" begin
        factor = OMSymbol("giac_procedures1", "factor"; cdbase = PB)(x)
        @test occursin("procedure_call", error_message(() -> Giac.giac_source(factor; enable = ["giac_procedures1"])))
        call = S("scscp1", "procedure_call")(factor)
        @test occursin("experimental", error_message(() -> Giac.giac_source(call)))
        @test occursin("does not evaluate requests",
                       error_message(() -> Giac.giac_source(call; enable = ["scscp1", "giac_procedures1"])))
        assignment = S("prog1", "assignment")(V("a"), I(1))
        @test occursin("procedure_call", error_message(() -> Giac.giac_source(assignment; enable = ["prog1"])))
    end

    @testset "bound variables named as GIAC constants are renamed" begin
        sum_i = S("arith1", "sum")(S("interval1", "integer_interval")(I(1), V("n")),
                                   lambda("i", S("arith1", "power")(V("i"), I(2))))
        src = Giac.giac_source(sum_i)
        @test occursin("i_1", src) && !occursin(r"\bi\b", src)
        @test same(Giac.from_openmath(sum_i), "n*(n+1)*(2*n+1)/6")
        # the fresh name avoids the object's names
        sum_i1 = S("arith1", "sum")(S("interval1", "integer_interval")(I(1), V("n")),
                                    lambda("i", S("arith1", "plus")(V("i"), V("i_1"))))
        @test occursin("i_2", Giac.giac_source(sum_i1))
        # a free i is still refused
        free = OMApplication(S("calculus1", "diff")(lambda("i", S("arith1", "power")(V("i"), I(2)))), [V("i")])
        @test occursin("constant", error_message(() -> Giac.giac_source(free)))
    end

    @testset "GIAC to OpenMath: other CDs only when enabled, at their base" begin
        @test_throws OMError om(quoted("sign(x)"))
        @test occursin("private", error_message(() -> om(quoted("sign(x)"))))
        o = OpenMath.to_openmath(quoted("sign(x)"); enable = ["giac_math1"])
        @test o.applicant.cd == "giac_math1" && o.applicant.cdbase == PB
        @test Giac.giac_source(o; enable = ["giac_math1"]) == "sign(x)"
    end

    @testset "exact refuses floats" begin
        @test_throws OMError Giac.giac_source(OMFloat(0.5); exact = true)
        @test Giac.giac_source(OMFloat(0.5)) == "0.5"
    end
end

@testset "the shared corpus of giac-openmath" begin
    ext = Base.get_extension(Giac, :GiacOpenMathExt)
    include(joinpath(@__DIR__, "giac_openmath_corpus.jl"))
    corpus = JSON.parse(CORPUS_JSON)
    @test corpus["format"] == 1
    @test !isempty(corpus["cases"])
    # cases about the JSON encoding itself, for readers of JSON text: Giac.jl reads
    # OpenMath.jl's objects, where an integer is exact
    json_only = Set(["unsafe JSON integer is refused"])
    # the same value: printed alike (infinities, relations), or their difference is 0
    agrees(r, v) = string(r) == string(giac_eval(v)) || same(r, v)
    kw(c) = (o = get(c, "options", Dict());
             (; enable = String.(get(o, "enable", String[])), exact = get(o, "exact", false)))
    for c in corpus["cases"]
        c["name"] in json_only && continue
        @testset "$(c["name"])" begin
            node = try
                # OpenMath.jl reads a document: the corpus's root object in an OMOBJ
                OpenMath.read_json(JSON.json(Dict("kind" => "OMOBJ", "object" => c["om"])))
            catch e
                e isa OpenMath.OpenMathError || rethrow()
                nothing
            end
            if haskey(c, "value")
                @test node !== nothing
                node === nothing || @test agrees(Giac.from_openmath(node; kw(c)...), c["value"])
            elseif node !== nothing
                # (OpenMath.jl may refuse it already while reading.) Giac.jl's errors
                # carry no JSON path, so the reason and the symbol are compared
                msg = error_message(() -> Giac.giac_source(node; kw(c)...))
                @test !isempty(msg)
                r = c["refused"]
                haskey(r, "reason_contains") && @test occursin(r["reason_contains"], msg)
                haskey(r, "symbol") && @test occursin(r["symbol"], msg)
            end
        end
    end
end
