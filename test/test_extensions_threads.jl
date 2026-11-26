# The package extensions from several tasks and threads at once, with GIAC
# evaluation and garbage collection going on meanwhile.
#
# Every call an extension makes into the C++ wrapper (`Giac.GiacCxxBindings`)
# must happen under the GIAC lock, like the calls in `src/`: GIAC is not
# thread-safe, and the free queue that finalizers fill is emptied by whichever
# task takes the lock next. A conversion walking or building GIAC objects
# without the lock could run inside GIAC at the same time as either.
#
# Runs with any number of threads: with one the tasks interleave on it, with
# several (`julia -t 4`) they run in parallel. The SymPy bridge is tested in
# test/test_sympy_conversion.jl, run by its own CI job.

using Test
using Giac
using Giac: to_giac, to_symbolics, to_mathjson, to_nemo
import Symbolics
import MathJSON
import Nemo
import LibPARI
import TermInterface
import ModelContextProtocol

# ---------------------------------------------------------------------------
# Static check: no wrapper call outside the lock
#
# Reads `ext/*.jl` as Julia code, not as text. A use of the wrapper is any
# reference to `GiacCxxBindings` (including through an alias such as
# `g = Giac.GiacCxxBindings`) or to `Giac._ptr_to_gen`, which hands out a
# wrapper object. A use is *locked* when it sits lexically inside a
# `with_giac_lock` call or do-block.
#
# A helper with an unlocked use requires its caller to hold the lock. That is
# propagated through the file's own helpers until nothing changes; an entry
# point (a method of another module's function, such as `Giac.to_giac` or
# `LibPARI.pari`) must not require the lock, and neither may top-level code.
# ---------------------------------------------------------------------------

module ExtLockCheck

const MARKERS = (:GiacCxxBindings, :_ptr_to_gen)

_is_lock_fn(f) = f === :with_giac_lock || f == :(Giac.with_giac_lock)
_is_lock_call(ex) = ex isa Expr && ex.head === :call && _is_lock_fn(ex.args[1])

# The name a definition defines, or `nothing` if `ex` defines no function
function _def_name(ex)
    ex isa Expr || return nothing
    if ex.head === :function || (ex.head === :(=) && _is_signature(ex.args[1]))
        sig = ex.args[1]
        while sig isa Expr && sig.head in (:where, :(::))
            sig = sig.args[1]
        end
        sig isa Expr && sig.head === :call || return nothing
        return string(sig.args[1])
    end
    return nothing
end

function _is_signature(sig)
    while sig isa Expr && sig.head in (:where, :(::))
        sig = sig.args[1]
    end
    return sig isa Expr && sig.head === :call
end

# Walk `ex`. Unlocked wrapper uses go to `uses` (with the line), and every symbol
# seen outside the lock goes to `refs`, so a helper's name used there is found.
function _scan!(uses, refs, ex, locked::Bool, line::Ref{Int})
    if ex isa LineNumberNode
        line[] = ex.line
    elseif ex isa Symbol
        locked || (ex in MARKERS ? push!(uses, line[]) : push!(refs, ex))
    elseif ex isa QuoteNode
        _scan!(uses, refs, ex.value, locked, line)
    elseif ex isa Expr
        if _is_lock_call(ex)
            foreach(a -> _scan!(uses, refs, a, true, line), ex.args)
        elseif ex.head === :do && _is_lock_call(ex.args[1])
            foreach(a -> _scan!(uses, refs, a, true, line), ex.args)
        else
            foreach(a -> _scan!(uses, refs, a, locked, line), ex.args)
        end
    end
    return nothing
end

# Top-level statements of a file, looking through `module` and doc strings
function _statements(ex, out = Any[])
    if ex isa Expr && ex.head in (:toplevel, :block)
        foreach(a -> _statements(a, out), ex.args)
    elseif ex isa Expr && ex.head === :module
        _statements(ex.args[3], out)
    elseif ex isa Expr && ex.head === :macrocall &&
           any(a -> _def_name(a) !== nothing, ex.args)
        foreach(a -> (a isa LineNumberNode || _def_name(a) !== nothing) && push!(out, a), ex.args)
    else
        push!(out, ex)
    end
    return out
end

"""
    violations(code::AbstractString) -> Vector{String}

Entry points and top-level code of `code` that use the wrapper without the
GIAC lock, directly or through a helper.
"""
function violations(code::AbstractString)
    methods = Tuple{String, Int, Vector{Int}, Set{Symbol}}[]   # name, line, uses, refs
    toplevel = Int[]
    line = Ref(0)
    for st in _statements(Meta.parseall(code))
        st isa LineNumberNode && (line[] = st.line; continue)
        name = _def_name(st)
        uses, refs = Int[], Set{Symbol}()
        if name === nothing
            _scan!(uses, refs, st, false, line)
            append!(toplevel, uses)
        else
            start = line[]
            _scan!(uses, refs, st.args[2], false, line)    # the body only
            push!(methods, (name, start, uses, refs))
        end
    end
    needs = Set(m[1] for m in methods if !isempty(m[3]))
    changed = true
    while changed
        changed = false
        for (name, _, _, refs) in methods
            if !(name in needs) && any(r -> string(r) in needs, refs)
                push!(needs, name)
                changed = true
            end
        end
    end
    bad = String[]
    for (name, start, uses, refs) in methods
        occursin('.', name) || continue          # an entry point
        if !isempty(uses) || any(r -> string(r) in needs, refs)
            push!(bad, "$name (line $start)")
        end
    end
    append!(bad, ["top-level code (line $l)" for l in toplevel])
    return bad
end

end # module ExtLockCheck

# ---------------------------------------------------------------------------
# Hammering: conversions from several tasks, GIAC work and collections meanwhile
# ---------------------------------------------------------------------------

# Run `convert_one(k, j)::Bool` for j = 1:iters on `ntasks` spawned tasks while
# one task evaluates GIAC expressions and another collects garbage. Returns how
# many conversions of each task were right. `collect = false` turns the
# collector off for the duration instead (see the LibPARI testset).
function hammer_conversions(convert_one; ntasks = 4, iters = 25, collect = true)
    stop = Threads.Atomic{Bool}(false)
    gc_was = collect || GC.enable(false)
    noise = Threads.@spawn begin
        n = 0
        while !stop[]
            e = Giac.Commands.expand((giac_eval("thz") + n)^3)
            string(Giac.Commands.factor(e))
            n += 1
            n % 10 == 0 && GC.gc(false)
            yield()
        end
        n
    end
    collector = Threads.@spawn begin
        while !stop[]
            GC.gc()
            sleep(0.02)
        end
    end
    try
        tasks = [Threads.@spawn begin
                     ok = 0
                     for j in 1:iters
                         ok += convert_one(k, j)::Bool
                         j % 5 == 0 && GC.gc(false)
                     end
                     ok
                 end for k in 1:ntasks]
        return fetch.(tasks)
    finally
        stop[] = true
        wait(noise)
        wait(collector)
        collect || GC.enable(gc_was)
        Giac.with_giac_lock(() -> nothing)      # free what is left in the queue
    end
end

iszero_giac(d) = string(Giac.Commands.normal(d)) == "0"

@testset "Extensions under concurrency" begin
    @testset "static check: no wrapper call outside the GIAC lock" begin
        @testset "the check itself" begin
            unlocked = """
            module M
            helper(g) = Giac.GiacCxxBindings.type(g)
            Giac.to_giac(x::Int) = helper(x)
            end
            """
            @test ExtLockCheck.violations(unlocked) == ["Giac.to_giac (line 3)"]
            locked = """
            module M
            helper(g) = Giac.GiacCxxBindings.type(g)
            function Giac.to_giac(x::Int)
                return Giac.with_giac_lock() do
                    helper(x)
                end
            end
            Giac.to_mathjson(x::Int) = Giac.with_giac_lock(() -> helper(x))
            end
            """
            @test isempty(ExtLockCheck.violations(locked))
            @test ExtLockCheck.violations("module M\nconst G = GiacCxxBindings.Gen(1)\nend") ==
                  ["top-level code (line 2)"]
            aliased = """
            function f(e)
                g = Giac.GiacCxxBindings
                return g.Gen(Int32(1))
            end
            LibPARI.pari(e::GiacExpr) = f(e)
            """
            @test ExtLockCheck.violations(aliased) == ["LibPARI.pari (line 5)"]
        end

        extdir = joinpath(pkgdir(Giac), "ext")
        for file in sort!(filter(endswith(".jl"), readdir(extdir)))
            @testset "$file" begin
                @test ExtLockCheck.violations(read(joinpath(extdir, file), String)) == String[]
            end
        end
    end

    @testset "Symbolics" begin
        Symbolics.@variables tha thb
        results = hammer_conversions() do k, j
            n = k * 100 + j
            s = tha^2 + n * thb - sin(tha) / 3 + (2 // 3) * tha + big(2)^70 + sqrt(thb)
            g = to_giac(s)
            ok = iszero_giac(g - giac_eval("tha^2+$n*thb-sin(tha)/3+2/3*tha+2^70+sqrt(thb)"))
            back = to_symbolics(giac_eval("cos(tha)^2 + $n*thb^3 + 2^80 + 3/7*tha"))
            ok &= iszero_giac(to_giac(back) - giac_eval("cos(tha)^2+$n*thb^3+2^80+3/7*tha"))
            ok
        end
        @test all(==(25), results)
    end

    @testset "MathJSON" begin
        results = hammer_conversions() do k, j
            n = k * 100 + j
            e = giac_eval("sin(tha)^2 + $n*thb^(1/2) - 3/4*exp(tha) + 2.5")
            ok = iszero_giac(to_giac(to_mathjson(e)) - e)
            v = giac_eval("[1, tha, 3/4, $n]")
            ok &= string(Giac.Commands.normal(to_giac(to_mathjson(v)) - v)) == "[0,0,0,0]"
            f = MathJSON.FunctionExpr(:Add, MathJSON.AbstractMathJSONExpr[
                MathJSON.SymbolExpr("tha"), MathJSON.NumberExpr(n),
                MathJSON.FunctionExpr(:Rational, MathJSON.AbstractMathJSONExpr[
                    MathJSON.NumberExpr(1), MathJSON.NumberExpr(3)])])
            ok &= iszero_giac(to_giac(f) - giac_eval("tha+$n+1/3"))
            ok &= to_mathjson(to_giac(MathJSON.NumberExpr(n))).value == n
            ok
        end
        @test all(==(25), results)
    end

    @testset "Nemo" begin
        R, t = Nemo.polynomial_ring(Nemo.QQ, "t")
        K, a = Nemo.number_field(t^2 - 2, "a")
        F, w = Nemo.finite_field(7, 3, "w")
        results = hammer_conversions() do k, j
            n = k * 100 + j
            p = 3t^3 - Nemo.QQ(n, 7) * t + big(2)^70
            ok = to_nemo(to_giac(p), R) == p
            ok &= to_nemo(to_giac(Nemo.ZZ(big(n)^20)), Nemo.ZZ) == Nemo.ZZ(big(n)^20)
            ok &= to_nemo(to_giac(Nemo.QQ(n, 11)), Nemo.QQ) == Nemo.QQ(n, 11)
            ok &= to_nemo(to_giac(n * a + 1), K) == n * a + 1
            ok &= to_nemo(to_giac(w^2 + n), F) == w^2 + n
            ok
        end
        @test all(==(25), results)
    end

    @testset "LibPARI" begin
        # A task on another thread runs on a secondary PARI context, which reads
        # a GP variable only once it is exported (LibPARI's docs/src/gp-state.md).
        #
        # With several threads the collector stays off here, and the PARI
        # objects are collected afterwards on this task alone: LibPARI 0.18.2's
        # `Gen` finalizer `put!`s onto a channel, which switches tasks inside a
        # finalizer when the channel is busy ("task switch not allowed from
        # inside gc finalizer", then a corrupted scheduler and a hang or a
        # crash) once another thread collects a PARI object. That is LibPARI's
        # bug, not this bridge's; the bridge itself makes no wrapper call.
        threaded = Threads.nthreads() > 1
        LibPARI.gp_eval("export(x)")
        try
            results = hammer_conversions(; collect = !threaded) do k, j
                n = k * 100 + j
                v = LibPARI.gp_eval("[3/$(n+1), 2^90 + $n, 2 + $n*I, 1.25]")
                m = LibPARI.gp_eval("[1, 2; 3, $n]")
                p = LibPARI.gp_eval("x^3 + $n*x - 1/7")
                LibPARI.pari(to_giac(v)) == v && LibPARI.pari(to_giac(m)) == m &&
                    LibPARI.pari(to_giac(p)) == p
            end
            @test all(==(25), results)
        finally
            LibPARI.gp_eval("unexport(x)")
            threaded && (GC.gc(); GC.gc())      # PARI garbage, with nothing else running
        end
    end

    @testset "TermInterface" begin
        results = hammer_conversions() do k, j
            n = k * 100 + j
            e = giac_eval("sin(tha) + $n*thb^2")
            args = TermInterface.arguments(e)
            rebuilt = TermInterface.maketerm(GiacExpr, TermInterface.operation(e), args, nothing)
            TermInterface.iscall(e) && length(TermInterface.children(e)) == length(args) &&
                iszero_giac(rebuilt - e)
        end
        @test all(==(25), results)
    end

    @testset "MCP" begin
        server = Giac.giac_mcp_server()
        tool = server.tools[findfirst(t -> t.name == "giac_eval", server.tools)]
        results = hammer_conversions() do k, j
            n = k * 100 + j
            r = tool.handler(Dict("expr" => "expand((tha+$n)^2)"))
            r isa ModelContextProtocol.TextContent &&
                iszero_giac(giac_eval(r.text) - giac_eval("(tha+$n)^2"))
        end
        @test all(==(25), results)
    end
end
