# Security posture regression tests.
#
# Giac is a programming language reached through `giac_eval`, not an expression
# calculator. Its own `secure_run` flag blocks the file-writing side of that
# language and is on by default — but only on builds not compiled with
# `-DNSPIRE`, so it is worth asserting rather than assuming. See SECURITY.md.
#
# Paths are built with `tempname()` and written with forward slashes: a Giac
# string literal eats the backslashes of a Windows path, which silently turns
# every probe into a test of nothing.

@testset "Security posture" begin

    # A guarded call raises rather than returning a value; the refusal is in
    # the message either way.
    function blocked(expr)
        try
            return occursin("secure mode", string(giac_eval(expr)))
        catch err
            return occursin("secure mode", sprint(showerror, err))
        end
    end

    giac_path(p) = replace(p, '\\' => '/')

    @testset "secure_run is active" begin
        # If these fail, libgiac was built with secure_run off and the
        # deployment advice in SECURITY.md no longer holds.
        probe = giac_path(tempname())
        @test blocked("cd(\"/tmp\")")
        @test blocked("write(\"$probe\", 0)")
        @test blocked("fopen(\"$probe\")")
        @test blocked("archive(\"$probe\", 1)")

        # `open` is the one that differs by platform: it reports secure mode
        # on Linux and macOS but not on Windows. What matters either way is
        # that nothing reaches the filesystem, so that is what is asserted
        # everywhere and the message only where it holds.
        if Sys.iswindows()
            try
                giac_eval("open(\"$probe\")")
            catch
            end
        else
            @test blocked("open(\"$probe\")")
        end

        @test !isfile(probe)
    end

    @testset "system() is not exposed" begin
        # On standard builds `system` is not a Giac command; it stays inert
        # rather than executing. It is only defined on calculator targets.
        @test occursin("system", string(giac_eval("system(\"id\")")))
    end

    @testset "the read family is NOT guarded — known upstream gap" begin
        # Pinned deliberately. `_read` has no `check_secure()` call, so it
        # reaches any file the process can read. If these start failing, Giac
        # has been fixed upstream and SECURITY.md must be updated.
        path = tempname()
        write(path, "SECRET42")
        gp = giac_path(path)
        try
            # `read16` returns the bytes — the clean exfiltration primitive.
            @test occursin("SECRET42", string(giac_eval("read16(\"$gp\")")))
            # `read` opens the file too, but evaluates it as Giac source
            # rather than returning it, so its content is not asserted.
            @test giac_eval("read(\"$gp\")") isa GiacExpr
        finally
            rm(path; force = true)
        end
    end

    # No timeout test here, deliberately. `caseval("timeout N")` does abort a
    # runaway computation, but the interrupt state is process-wide and sticky:
    # every later evaluation raises, and neither `restart` nor a fresh
    # GiacContext recovers it. Exercising it would poison the rest of the
    # suite. See the denial-of-service section of SECURITY.md.
end
