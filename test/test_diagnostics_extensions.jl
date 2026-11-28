# The result and GIAC's messages, through the extensions: a conversion into Giac,
# a computation and a conversion back, inside evaluate_with_diagnostics, keep both
# the value (in the extension's own type) and what GIAC said while computing it.
# The MCP server is tested in test_mcp_ext.jl; SymPy and OpenMath, in their own
# jobs (test_sympy_conversion.jl, test_openmath_ext.jl).

using Test
using Giac
import Symbolics
import SymbolicUtils
using MathJSON

@testset "the result and GIAC's messages through the extensions" begin
    # integrating abs: GIAC assumes the sign constant by intervals, and says so
    integrate = Giac.Commands.integrate
    assumed(r) = any(d -> d.kind == :assumption, r.diagnostics)

    @testset "Symbolics" begin
        Symbolics.@variables x
        r = evaluate_with_diagnostics() do
            Giac.to_symbolics(integrate(Giac.to_giac(abs(x)), giac_eval("x")))
        end
        @test r.value isa Symbolics.Num
        @test occursin("sign", string(r.value))
        @test assumed(r)
    end

    @testset "SymbolicUtils" begin
        SymbolicUtils.@syms y::Real
        names = Dict(y => "y")
        r = evaluate_with_diagnostics() do
            to_symbolicutils(integrate(to_giac(abs(y); names), giac_eval("y"));
                             symbols = Dict("y" => y))
        end
        @test occursin("sign", string(r.value))
        @test assumed(r)
    end

    @testset "MathJSON" begin
        r = evaluate_with_diagnostics() do
            Giac.to_mathjson(integrate(Giac.to_giac(MathJSON.FunctionExpr(:Abs, [MathJSON.SymbolExpr("z")])),
                                       giac_eval("z")))
        end
        @test r.value isa MathJSON.AbstractMathJSONExpr
        @test assumed(r)
    end

    @testset "an error keeps the messages logged before it" begin
        # evaluate_with_diagnostics rethrows; catching inside it keeps the messages
        r = evaluate_with_diagnostics() do
            try
                giac_eval("integrate(abs(t),t)")
                giac_eval("inv([[1,2],[2,4]])")
            catch e
                e
            end
        end
        @test r.value isa Exception
        @test assumed(r)
    end
end
