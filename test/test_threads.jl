# GIAC from several tasks and threads at once, with the garbage collector
# freeing GIAC objects meanwhile.
#
# GIAC is not thread-safe and its objects share reference-counted parts.
# Finalizers run on whichever thread collects garbage, possibly while another
# thread is inside GIAC, so a finalizer only queues what is to be freed; the
# next task to take the GIAC lock frees it.
#
# Runs with any number of threads: with one thread the spawned tasks
# interleave on it, with several they run in parallel (`julia -t 4`).

@testset "Threads" begin
    @giac_var x y

    # Free whatever finalizers have queued so far
    drain!() = Giac.with_giac_lock(() -> nothing)

    @testset "a finalizer only queues an expression; the lock holder frees it" begin
        e = giac_eval("thr_a^2 + 1")
        id = UInt(e.ptr)
        lock(Giac.GIAC_LOCK)
        try
            finalize(e)                     # as a collecting thread would, GIAC busy
            @test e.ptr == C_NULL
            @test haskey(Giac._gen_objects, id)   # untouched while GIAC is in use
            @test Giac._DOOMED_COUNT[] > 0
        finally
            unlock(Giac.GIAC_LOCK)
        end
        drain!()
        @test !haskey(Giac._gen_objects, id)
        @test Giac._DOOMED_COUNT[] == 0
    end

    @testset "a finalizer only queues a context" begin
        ctx = GiacContext()
        id = UInt(ctx.ptr)
        lock(Giac.GIAC_LOCK)
        try
            finalize(ctx)
            @test ctx.ptr == C_NULL
            @test haskey(Giac._context_objects, id)
        finally
            unlock(Giac.GIAC_LOCK)
        end
        drain!()
        @test !haskey(Giac._context_objects, id)
    end

    @testset "C++ objects are destroyed under the lock, not by the collector" begin
        B = Giac.GiacCxxBindings
        g = Giac.with_giac_lock(() -> B.giac_eval("thr_b + 1"))
        v = Giac.with_giac_lock() do
            w = Giac.CxxWrap.StdVector{B.Gen}()
            push!(w, g)
            w
        end
        lock(Giac.GIAC_LOCK)
        try
            finalize(g)
            finalize(v)
            @test g.cpp_object != C_NULL    # queued, not yet destroyed
            @test v.cpp_object != C_NULL
        finally
            unlock(Giac.GIAC_LOCK)
        end
        drain!()
        @test g.cpp_object == C_NULL
        @test v.cpp_object == C_NULL
    end

    @testset "a matrix releases its expression when collected" begin
        m = GiacMatrix([1 2; 3 4])
        id = UInt(m.ptr)
        @test haskey(Giac._gen_objects, id)
        finalize(m)
        drain!()
        @test !haskey(Giac._gen_objects, id)
        # a matrix read from an expression borrows the expression's value
        e = giac_eval("[[1,2],[3,4]]")
        m2 = GiacMatrix(e)
        finalize(m2)
        drain!()
        @test string(e) == "[[1,2],[3,4]]"
    end

    @testset "a finalizer run from another task while GIAC is held does not block" begin
        e = giac_eval("thr_c + 2")
        id = UInt(e.ptr)
        lock(Giac.GIAC_LOCK)
        try
            t = Threads.@spawn finalize(e)
            @test timedwait(() -> istaskdone(t), 30.0) === :ok
            @test haskey(Giac._gen_objects, id)
        finally
            unlock(Giac.GIAC_LOCK)
        end
        drain!()
        @test !haskey(Giac._gen_objects, id)
    end

    @testset "concurrent arithmetic, simplification and typesetting" begin
        work(k) = begin
            ok = 0
            for j in 1:60
                e = Giac.Commands.expand((x + k + j)^2 - x^2)
                ok += string(Giac.Commands.normal(e - (2 * (k + j) * x + (k + j)^2))) == "0"
                ok += !isempty(sprint(show, MIME"text/latex"(), e + sin(y)^2 + cos(y)^2))
                ok += string(Giac.Commands.simplify(sin(y)^2 + cos(y)^2)) == "1"
                j % 20 == 0 && GC.gc(false)
            end
            ok
        end
        @test all(==(180), fetch.([Threads.@spawn(work(k)) for k in 1:8]))
    end

    @testset "freed objects are queued, then freed under the lock" begin
        for _ in 1:2000
            Giac.Commands.expand((x + 1)^3)
        end
        GC.gc()
        Giac.with_giac_lock(() -> nothing)          # empties the queue
        @test Giac._DOOMED_COUNT[] == 0
    end

    @testset "concurrent evaluation, with collections meanwhile" begin
        function work(k)
            ok = 0
            for j in 1:40
                n = k + j
                e = Giac.Commands.expand((x + n)^2 - x^2)
                ok += string(Giac.Commands.normal(e - (2n * x + n^2))) == "0"
                ok += string(Giac.Commands.diff(e, x)) == string(2n)
                ok += string(substitute(e, Dict(x => 1))) == string(2n + n^2)
                ok += !isempty(sprint(show, MIME"text/latex"(), e + sin(y)))
                ok += string(Giac.Commands.simplify(sin(y)^2 + cos(y)^2)) == "1"
                j % 10 == 0 && GC.gc(false)
            end
            return ok
        end
        tasks = [Threads.@spawn(work(k)) for k in 1:8]
        @test all(==(200), fetch.(tasks))
    end

    @testset "full collections while another task evaluates" begin
        worker = Threads.@spawn begin
            r = nothing
            for _ in 1:5
                r = Giac.Commands.factor(Giac.Commands.expand((x + y + 1)^12 - 1))
            end
            string(Giac.Commands.normal(Giac.Commands.expand(r) - (x + y + 1)^12 + 1))
        end
        while !istaskdone(worker)
            for i in 1:50
                giac_eval("thr_d + $i")     # garbage for the collector
            end
            GC.gc()
            yield()
        end
        @test fetch(worker) == "0"
        GC.gc()
        drain!()
        @test Giac._DOOMED_COUNT[] == 0
    end

    @testset "an explicit context is shared by every thread" begin
        ctx = GiacContext()
        giac_eval("thr_e := 7", ctx)
        seen = fetch.([Threads.@spawn(string(giac_eval("thr_e", ctx))) for _ in 1:8])
        @test all(==("7"), seen)
        fetch(Threads.@spawn giac_eval("thr_f := 11", ctx))
        @test string(giac_eval("thr_f", ctx)) == "11"
    end

    @testset "tasks on the calling thread share its default context" begin
        # `@async` tasks stay on the thread that starts them
        wait(@async giac_eval("thr_g := 13"))
        @test string(giac_eval("thr_g")) == "13"
        giac_eval("purge(thr_g)")
    end
end
