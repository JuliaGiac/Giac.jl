using Test
using Giac
using LinearAlgebra

@testset "Giac.jl" begin
    # Module loading test (US2)
    @testset "Module Loading" begin
        @test isdefined(Giac, :GiacExpr)
        @test isdefined(Giac, :GiacContext)
        @test isdefined(Giac, :GiacError)
        @test isdefined(Giac, :giac_eval)
    end

    # Include individual test files
    include("test_types.jl")
    include("test_wrapper.jl")
    include("test_api.jl")
    include("test_operators.jl")
    include("test_mathops.jl")
    include("test_issue71.jl")
    include("test_calculus.jl")
    include("test_algebra.jl")
    include("test_linalg.jl")
    include("test_matrix_iteration.jl")
    include("test_memory.jl")

    # Command invocation tests (003-giac-commands)
    include("test_commands.jl")
    include("test_command_registry.jl")

    # Namespace command access tests (007-giac-namespace-commands)
    include("test_namespace_commands.jl")

    # Commands submodule tests (009-commands-submodule)
    include("test_commands_submodule.jl")

    # CommonSolve integration (PR #7)
    include("test_commonsolve.jl")


    # Macro tests (011-giac-symbol-macro)
    include("test_macros.jl")

    # Multivar derivative operator tests (068-multivar-d-operator)
    include("test_differential.jl")

    # Matrix display tests (011-giacmatrix-display)
    include("test_matrix_display.jl")

    # Introspection tests (003-giac-introspection)
    include("test_introspection.jl")

    # Type conversion tests (022-julia-type-conversion)
    include("test_type_conversion.jl")

    include("test_float_conversion.jl")

    include("test_conversion_constructors.jl")

    include("test_context_isolation.jl")

    include("test_security.jl")

    include("test_to_julia_precision.jl")

    # Multiple dispatch for conflicts tests (023-conflicts-multidispatch)
    include("test_conflicts_multidispatch.jl")

    # Equation syntax tests (024-equation-syntax)
    include("test_equation_syntax.jl")

    # Comparison operators tests (064-symbolic-comparison-operators)
    include("test_comparison_operators.jl")

    # Tables.jl compatibility tests (025-tables-compatibility)
    include("test_tables.jl")

    # Julia help system integration tests (026-julia-help-docstrings)
    include("test_docstrings.jl")

    # Substitute function tests (028-substitute-mechanism)
    include("test_substitute.jl")

    # build_function tests (066-build-function)
    include("test_build_function.jl")

    # build_function tier 3 (Symbolics backend) tests (067-build-function-tier3)
    include("test_build_function_tier3.jl")

    # invoke_cmd fast path tests (069-invoke-cmd-fastpath)
    include("test_invoke_cmd_fastpath.jl")

    # LaTeX/MathML rendering form-preservation tests (071-latex-render-form)
    include("test_latex_render.jl")

    # Output handling tests (029-output-handling)
    include("test_output_handling.jl")

    # ============================================================================
    # Domain Documentation Tests (036-domain-docs-tests)
    # Verifies that all code examples in documentation work correctly
    # ============================================================================

    # Mathematics domain documentation tests
    include("test_docs_math_calculus.jl")
    include("test_docs_math_algebra.jl")
    include("test_docs_math_linalg.jl")
    include("test_docs_math_odes.jl")
    include("test_docs_math_trig.jl")

    # Physics domain documentation tests
    include("test_docs_physics_mechanics.jl")
    include("test_docs_physics_em.jl")

    # ============================================================================
    # UnitRange Indices Support Tests (037-unitrange-indices)
    # Verifies UnitRange support in GiacMatrix and @giac_several_vars
    # ============================================================================
    include("test_unitrange_indices.jl")

    # ============================================================================
    # Inf and -Inf Support Tests (038-inf-support)
    # Verifies Julia Inf/-Inf conversion to GIAC inf/-inf
    # ============================================================================
    include("test_inf_support.jl")

    # ============================================================================
    # Z-Transform Function Tests (039-z-transform)
    # Verifies z-transform and inverse z-transform functions
    # ============================================================================
    include("test_ztransform.jl")

    # ============================================================================
    # Laplace Transform Function Tests (040-laplace-transform)
    # Verifies Laplace transform and inverse Laplace transform functions
    # ============================================================================
    include("test_laplace.jl")

    # ============================================================================
    # GenTypes Module Tests (041-scoped-type-enum)
    # Verifies T enum for GIAC expression types
    # ============================================================================
    include("test_gen_types.jl")

    # ============================================================================
    # Symbolics Extension Tests (042-preserve-symbolic-sqrt)
    # Verifies symbolic expression preservation in to_symbolics
    # ============================================================================
    include("test_symbolics_ext.jl")

    # ============================================================================
    # Constants Module Tests (053-symbolic-pi-constant)
    # Verifies symbolic constants (pi, e, i) work correctly
    # ============================================================================
    include("test_constants.jl")

    # ============================================================================
    # Held Command Display Tests (055-held-cmd-display)
    # Verifies HeldCmd type, hold_cmd, release, LaTeX and plain text display
    # ============================================================================
    include("test_held_cmd.jl")

    # ============================================================================
    # Additional Coverage Tests
    # Targets uncovered code paths in iteration, introspection, held_cmd, types
    # ============================================================================
    include("test_coverage.jl")

    # ============================================================================
    # MathJSON Conversion Extension Tests (054-mathjson-conversion)
    # Verifies bidirectional conversion between GiacExpr and MathJSON types
    # ============================================================================
    include("test_mathjson_conversion.jl")

    # ============================================================================
    # TermInterface Extension Tests (Issue #3 task 3)
    # Verifies TermInterface.iscall / operation / arguments / maketerm dispatch
    # ============================================================================
    include("test_terminterface_ext.jl")

    # ============================================================================
    # MCP Server Extension Tests (070-mcp-server-integration)
    # Verifies the GiacMCPExt extension exposes giac_mcp_server with two tools
    # ============================================================================
    include("test_mcp_ext.jl")

    # ============================================================================
    # LibPARI Extension Tests (071-libpari-bridge)
    # Verifies to_giac(::LibPARI.Gen) / LibPARI.pari(::GiacExpr) round trips,
    # the refusal list and the documented limitations.
    # A dedicated CI job also runs this file standalone, against a project
    # holding only Giac and LibPARI.
    # ============================================================================
    include("test_libpari_ext.jl")

    # The SymPy bridge is deliberately absent from this suite. SymPy.jl reaches
    # Python through PyCall, so its extension cannot precompile unless the
    # Python `sympy` module is importable — and with SymPy in the `test`
    # target, every cell of the main matrix failed at precompile time over a
    # missing Python package. It has its own job, which provisions Python and
    # runs test/test_sympy_conversion.jl standalone; see
    # .github/workflows/CI-SymPy.yml.

    # ============================================================================
    # Nemo Extension Tests (081-nemo-oscar-bridge)
    # Bidirectional Giac <-> Nemo bridge: to_giac(::Nemo.RingElem) and
    # to_nemo(::GiacExpr, parent), with the documented refusal list.
    # ============================================================================
    include("test_nemo_conversion.jl")

    # ============================================================================
    # Doctests
    # Runs jldoctest blocks in Giac docstrings via Documenter.doctest
    # ============================================================================
    include("test_doctests.jl")
end

# Aqua.jl package quality tests
using Aqua
@testset "Aqua.jl" begin
    Aqua.test_all(Giac; ambiguities=false)
end
