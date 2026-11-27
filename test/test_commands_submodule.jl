# Tests for Giac.Commands submodule (009-commands-submodule)

@testset "Commands Submodule" begin
    @testset "Module Structure" begin
        # T008: Commands submodule exists
        @test isdefined(Giac, :Commands)
        @test typeof(Giac.Commands) == Module
    end

    @testset "invoke_cmd Function" begin
        # T011: invoke_cmd is exported from main Giac module
        @test isdefined(Giac, :invoke_cmd)

        # invoke_cmd is also available via Giac.Commands
        @test isdefined(Giac.Commands, :invoke_cmd)

        # Test invoke_cmd functionality
        # T008: Test Giac.Commands.factor via invoke_cmd
        expr = giac_eval("x^2 - 1")
        result = invoke_cmd(:factor, expr)
        @test string(result) == "(x-1)*(x+1)"

        # Test invoke_cmd with multiple arguments (like diff)
        x = giac_eval("x")
        expr2 = giac_eval("x^3")
        result2 = invoke_cmd(:diff, expr2, x)
        @test string(result2) == "3*x^2"

        # Test invoke_cmd with conflicting command (sin)
        result3 = invoke_cmd(:sin, giac_eval("0"))
        @test string(result3) == "0"
    end

    @testset "Commands Module Access" begin
        # T008: Test Giac.Commands.factor
        expr = giac_eval("x^2 - 1")
        result = Giac.Commands.factor(expr)
        @test string(result) == "(x-1)*(x+1)"

        # T009: Test Giac.Commands.diff
        x = giac_eval("x")
        expr2 = giac_eval("x^3")
        result2 = Giac.Commands.diff(expr2, x)
        @test string(result2) == "3*x^2"

        # Test other commands via qualified access
        expand_result = Giac.Commands.expand(giac_eval("(x+1)^2"))
        @test contains(string(expand_result), "x^2")
    end

    @testset "Clean Core API (US4)" begin
        # T010: factor is NOT directly exported from main Giac module
        # Note: We check that it's NOT in the exported names of Giac
        giac_exports = names(Giac)

        # These should NOT be in the main Giac exports
        @test :factor ∉ giac_exports
        @test :expand ∉ giac_exports
        @test :diff ∉ giac_exports

        # T011: invoke_cmd IS exported from main Giac
        @test :invoke_cmd ∈ giac_exports

        # giac_cmd should NOT be exported anymore
        @test :giac_cmd ∉ giac_exports

        # Core API should still be exported
        @test :GiacExpr ∈ giac_exports
        @test :giac_eval ∈ giac_exports
        @test :to_julia ∈ giac_exports
        # Note: help is no longer exported (027-remove-help-function)
        # Use ?cmd or Giac.giac_help(:cmd) instead
        @test :giac_help ∈ giac_exports

        # T012: Export count should be reasonable (not the ~2000+ commands)
        # Count only the non-private exports (those not starting with underscore)
        public_exports = filter(s -> !startswith(string(s), "_"), giac_exports)
        # Core API + utilities + output handling (029) + the symbolic-algebra helpers of the
        # ergonomics port (∇, jacobian, hessian, lhs, rhs, isolate, @giac_matrix, taylor,
        # collect_terms, assuming, with_settings, giac_settings, assumptions) + the engine
        # queries (giac_version, fresh_identifier, with_fresh_identifiers, is_free_identifier,
        # to_symbolicutils, evaluate_with_diagnostics) should be under 100 symbols (not
        # thousands). 100 leaves room for the symbolic matrices of the port (@matsym, MatExpr,
        # quadratic_form, differential, derivative, vectorize, vech).
        # Output handling adds: 13 type constants + 10 predicates + 6 accessors = ~29 exports
        @test length(public_exports) <= 100
    end

    @testset "Exportable Commands Generation" begin
        # Commands module should have many exported commands
        commands_exports = names(Giac.Commands)

        # Should have invoke_cmd
        @test :invoke_cmd ∈ commands_exports

        # Should have common math commands
        @test :factor ∈ commands_exports
        @test :expand ∈ commands_exports

        # Should NOT have conflicting commands exported
        @test :eval ∉ commands_exports
        @test :sin ∉ commands_exports
        @test :cos ∉ commands_exports

        # T026: Should have many commands (~2000+)
        # Note: The exact count depends on exportable_commands()
        if !isempty(Giac.VALID_COMMANDS)
            exportable_count = length(Giac.exportable_commands())
            @test exportable_count > 1500  # Should be ~2000+
        end
    end

    @testset "Selective Import (US2)" begin
        # T020, T021: Test selective import pattern
        # Note: We can't actually test `using Giac.Commands: factor` in runtime tests
        # because `using` is a compile-time operation. Instead, we verify the structure
        # supports it by checking that commands are properly exported.

        # Verify commands can be accessed directly from Commands
        @test isdefined(Giac.Commands, :factor)
        @test isdefined(Giac.Commands, :expand)
        @test isdefined(Giac.Commands, :diff)

        # T023: invoke_cmd can be selectively imported
        @test isdefined(Giac.Commands, :invoke_cmd)
    end

    @testset "Conflicting Commands via invoke_cmd" begin
        # Conflicting commands should work via invoke_cmd
        # These are in JULIA_CONFLICTS so not exported, but work via invoke_cmd

        # eval is a Julia builtin
        result = invoke_cmd(:eval, giac_eval("2+3"))
        @test string(result) == "5"

        # sin conflicts with Base.sin
        result2 = invoke_cmd(:sin, giac_eval("pi/2"))
        @test string(result2) == "1"
    end

    @testset "GiacCommand Type Compatibility" begin
        # GiacCommand should still work (uses giac_cmd internally)
        factor_cmd = GiacCommand(:factor)
        expr = giac_eval("x^2 - 1")
        result = factor_cmd(expr)
        @test string(result) == "(x-1)*(x+1)"
    end
end
