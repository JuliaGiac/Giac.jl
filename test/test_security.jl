# Security posture regression tests.
#
# Giac is a programming language reached through `giac_eval`, not an expression
# calculator. Its own `secure_run` flag blocks the file-writing side of that
# language and is on by default — but only on builds that were not compiled
# with `-DNSPIRE`, so it is worth asserting rather than assuming. See
# SECURITY.md.

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

    @testset "secure_run is active" begin
        # If this fails, libgiac was built with secure_run off and the
        # deployment advice in SECURITY.md no longer holds.
        @test blocked("cd(\"/tmp\")")
        @test blocked("write(\"/tmp/giac_secure_probe\", 0)")
        @test blocked("open(\"/tmp/giac_secure_probe\")")
        @test blocked("fopen(\"/tmp/giac_secure_probe\")")
        @test blocked("archive(\"/tmp/giac_secure_probe\", 1)")
        # and nothing reached the filesystem
        @test !isfile("/tmp/giac_secure_probe")
    end

    @testset "system() is not exposed" begin
        # On standard builds `system` is not a Giac command; it stays inert
        # rather than executing. It is only defined on calculator targets.
        @test occursin("system", string(giac_eval("system(\"id\")")))
    end

    @testset "the read family is NOT guarded — known upstream gap" begin
        # Pinned deliberately. `_read` has no `check_secure()` call, so it
        # reaches any file the process can read. If these ever start failing,
        # Giac has been fixed upstream and SECURITY.md must be updated.
        path = tempname()
        write(path, "SECRET42")
        try
            # `read16` returns the bytes — the clean exfiltration primitive.
            @test occursin("SECRET42", string(giac_eval("read16(\"$path\")")))
            # `read` opens the file too, but evaluates it as Giac source
            # rather than returning it, so it is not asserted on content.
            @test giac_eval("read(\"$path\")") isa GiacExpr
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
