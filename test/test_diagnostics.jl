# Capturing GIAC's informational messages (evaluate_with_diagnostics).
#
# GIAC writes some messages to its log stream (stderr by default) instead of
# returning them. Serret's integral is the motivating case: no closed form is
# found, the integral comes back unevaluated, and GIAC logs a numeric estimate
# `// ∫ ~= 0.272198261288`. `evaluate_with_diagnostics` returns that text
# separately from the value, which stays exactly what `integrate` returns.

using Test
using Giac
using Giac: GiacDiagnostic, GiacEvalResult, DiagnosticLevel

const SERRET_STR = "integrate(ln(1+x)/(1+x^2),x,0,1)"
const SERRET_HINT = "0.272198261288"

@testset "Diagnostics capture" begin

    @testset "log parsing" begin
        diags = Giac._parse_diagnostics(
            "// ∫ ~= 0.272198261288\nWarning, need to choose a branch\n\n" *
            "Error: Bad Argument Value\nChecking exact value of integral\n")
        @test length(diags) == 4
        @test diags[1] == GiacDiagnostic(DiagnosticLevel.INFO, "∫ ~= 0.272198261288",
                                         "// ∫ ~= 0.272198261288")
        @test diags[2].level == DiagnosticLevel.WARNING
        @test diags[2].text == "Warning, need to choose a branch"
        @test diags[3].level == DiagnosticLevel.ERROR
        @test diags[4].level == DiagnosticLevel.INFO
        @test diags[4].text == "Checking exact value of integral"
        @test isempty(Giac._parse_diagnostics(""))
        @test isempty(Giac._parse_diagnostics("\n  \n"))
        @test DiagnosticLevel.INFO isa DiagnosticLevel.T
    end

    @testset "what a message says: kind" begin
        kinds(log) = [d.kind for d in Giac._parse_diagnostics(log)]
        # GIAC's messages as it writes them (observed with GIAC 2.0)
        @test kinds("// ∫ ~= 0.272198261288\n") == [:estimate]
        @test kinds("Warning, integration of abs or sign assumes constant sign by intervals " *
                    "(correct if the argument is real):\nCheck [abs(x-1)]\n") == [:assumption, :assumption]
        @test kinds("No checks were made for singular points of antiderivative -exp(-x) for " *
                    "definite integration in [0,+infinity]\n") == [:unchecked]
        @test kinds("Warning, argument is not an equation, solving x^3+a*x+b=0\n") == [:interpretation]
        @test kinds("choosing root of [1,0,-184,0,9272] at parameters values [0]\n") == [:choice]
        @test kinds("Warning, need to choose a branch for the root of a polynomial with parameters\n") == [:choice]
        @test kinds("Trying integration by part\nWarning, something new\nError: Bad Argument Value\n") ==
              [:info, :warning, :error]
        # the 3-argument constructor classifies too
        @test GiacDiagnostic(DiagnosticLevel.INFO, "∫ ~= 1", "// ∫ ~= 1").kind === :estimate
    end

    # Both ways of capturing are tested: the wrapper's (libgiac_julia_jll 0.6 and later) and the
    # fallback that redirects stderr, used with an older wrapper.
    backends = Giac._log_capture_available() ? (:wrapper, :stderr) : (:stderr,)
    for backend in backends
        Giac._DIAGNOSTICS_BACKEND[] = backend
        @testset "captured by $backend" begin
            @test Giac._diagnostics_backend() === backend
            @giac_var x

            @testset "integrate keeps its value, message goes to diagnostics" begin
                out = evaluate_with_diagnostics() do
                    Giac.Commands.integrate(log(1 + x) / (1 + x^2), x, 0, 1)
                end
                @test out isa GiacEvalResult
                @test out.value isa GiacExpr
                @test occursin("integrate", string(out.value))
                @test length(out.diagnostics) == 1
                d = out.diagnostics[1]
                @test d.level == DiagnosticLevel.INFO
                @test startswith(d.text, "∫ ~=")
                @test occursin(SERRET_HINT, d.text)
                @test startswith(d.raw, "//")
                @test occursin(SERRET_HINT, out.log)
            end

            @testset "value is identical to the uncaptured call" begin
                plain = Giac.Commands.integrate(log(1 + x) / (1 + x^2), x, 0, 1)
                out = evaluate_with_diagnostics() do
                    Giac.Commands.integrate(log(1 + x) / (1 + x^2), x, 0, 1)
                end
                @test string(out.value) == string(plain)
            end

            @testset "string evaluation path" begin
                out = evaluate_with_diagnostics(() -> giac_eval(SERRET_STR))
                @test occursin(SERRET_HINT, out.log)
            end

            @testset "no message, no diagnostics" begin
                out = evaluate_with_diagnostics(() -> giac_eval("1+1"))
                @test string(out.value) == "2"
                @test isempty(out.diagnostics)
                @test out.log == ""
            end

            @testset "any return value is passed through" begin
                out = evaluate_with_diagnostics(() -> (giac_eval(SERRET_STR), 42))
                @test out.value[2] == 42
                @test occursin(SERRET_HINT, out.log)
            end

            @testset "nested captures both see the message" begin
                inner = Ref{Any}()
                outer = evaluate_with_diagnostics() do
                    inner[] = evaluate_with_diagnostics(() -> giac_eval(SERRET_STR))
                    nothing
                end
                @test occursin(SERRET_HINT, inner[].log)
                @test occursin(SERRET_HINT, outer.log)
            end

            @testset "the stream is restored when f throws" begin
                @test_throws ErrorException evaluate_with_diagnostics() do
                    giac_eval(SERRET_STR)
                    error("boom")
                end
                backend === :wrapper && @test Giac.GiacCxxBindings.log_capture_depth() == 0
                # Nothing from the failed capture leaks into the next one.
                @test evaluate_with_diagnostics(() -> giac_eval("1+1")).log == ""
            end

            @testset "a dedicated GiacContext" begin
                ctx = GiacContext()
                out = evaluate_with_diagnostics(context = ctx) do
                    giac_eval(SERRET_STR, ctx)
                end
                @test occursin("integrate", string(out.value))
                @test occursin(SERRET_HINT, out.log)
                if backend === :wrapper
                    @test Giac.GiacCxxBindings.log_capture_depth(Giac._get_context(ctx.ptr)) == 0
                    @test Giac.GiacCxxBindings.log_capture_depth() == 0
                end
            end
        end
    end
    Giac._DIAGNOSTICS_BACKEND[] = :auto

    @testset "the backend follows the wrapper" begin
        @test Giac._diagnostics_backend() === (Giac._log_capture_available() ? :wrapper : :stderr)
    end
end
