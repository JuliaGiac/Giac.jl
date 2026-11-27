"""
    Giac.Commands

A submodule containing all exportable GIAC commands as functions.

This module provides access to ~2000+ GIAC commands while keeping the main
`Giac` namespace clean. Commands can be accessed through three patterns:

# Access Patterns

1. **Qualified access** (cleanest namespace):
   ```julia
   using Giac
   Giac.Commands.factor(expr)
   Giac.Commands.diff(expr, x)
   ```

2. **Selective import** (recommended for most use cases):
   ```julia
   using Giac
   using Giac.Commands: factor, expand, diff
   factor(expr)  # Works directly
   ```

3. **Full import** (for interactive exploration):
   ```julia
   using Giac
   using Giac.Commands
   factor(expr)   # All ~2000+ commands available
   ifactor(expr)  # Works directly
   ```

# Conflicting Commands

Commands that conflict with Julia keywords, builtins, or standard library
functions (like `eval`, `sin`, `det`) are NOT exported from this module.
Use `invoke_cmd` to call them:

```julia
using Giac
invoke_cmd(:eval, expr)  # Works for any command
invoke_cmd(:sin, x)      # Including conflicting ones
```

# Exports

- `invoke_cmd`: Universal command invocation function
- All ~2000+ non-conflicting GIAC commands (runtime-generated)

# See also

- [`invoke_cmd`](@ref): Call any GIAC command by name
- [`Giac.JULIA_CONFLICTS`](@ref): Commands that conflict with Julia
- [`Giac.exportable_commands`](@ref): List of exportable commands
"""
module Commands

using ..Giac: GiacExpr, GiacMatrix, GiacInput, GiacError, giac_eval, with_giac_lock,
              VALID_COMMANDS, JULIA_CONFLICTS, CONFLICT_CATEGORIES, exportable_commands,
              suggest_commands, _format_suggestions, _warn_conflict,
              _arg_to_giac_string, _build_command_string, help, HelpResult,
              HeldCmd,
              _fastpath_disabled, _has_direct_gen, _invoke_cmd_direct,
              RENDER_COMMANDS, _hold_render_arg
import LinearAlgebra

import CommonSolve: solve

# ============================================================================
# Core Command Invocation (invoke_cmd)
# ============================================================================

"""
    invoke_cmd(cmd::Symbol, args...) -> GiacExpr

Invoke any GIAC command by name and return the result as a GiacExpr.

This is the core function for dynamic command invocation, enabling access to
all 2200+ GIAC commands through a uniform interface. It works for all commands,
including those that conflict with Julia builtins.

# Arguments
- `cmd::Symbol`: GIAC command name (e.g., `:factor`, `:sin`, `:integrate`)
- `args...`: Command arguments (GiacExpr, String, Number, or Symbol)

# Returns
- `GiacExpr`: Result of command execution

# Throws
- `GiacError(:eval)`: If command is unknown or execution fails
- `ArgumentError`: If arguments cannot be converted to GIAC format

# Examples
```julia
using Giac

# Single argument
expr = giac_eval("x^2 - 1")
result = invoke_cmd(:factor, expr)  # Returns (x-1)*(x+1)

# Multiple arguments
x = giac_eval("x")
derivative = invoke_cmd(:diff, expr, x)  # Returns 2*x

# Trigonometric functions (conflicts with Base)
result = invoke_cmd(:sin, giac_eval("pi/6"))  # Returns 1/2

# Evaluation (conflicts with Base.eval)
result = invoke_cmd(:eval, giac_eval("2+3"))  # Returns 5
```

# Rendering commands

The commands listed in [`Giac.RENDER_COMMANDS`](@ref) (`:latex`, `:mathml`)
typeset their argument rather than compute with it, so their `GiacExpr`
arguments are quoted before dispatch. Without that, GIAC would re-evaluate the
argument first and results that are not fixed points of evaluation would lose
their form — `ifactor(360)` is the product `2^3*3^2*5`, which evaluates back
to `360`:

```julia
f = invoke_cmd(:ifactor, 360)   # 2^3*3^2*5
invoke_cmd(:latex, f)           # "5\\cdot 2^{3}\\cdot 3^{2}", not "360"
```

# Performance

Since v0.14.2, `invoke_cmd` takes a direct-`Gen` fast path that bypasses the
GIAC parser when every argument has a direct `Gen` representation
(`GiacExpr`, `Int32`, Int32-fitting `Int64`, finite `Float64`). Otherwise it
falls back to the existing string-concatenation path. Geometric-mean
speed-up across the standard workload mix is ≈ 1.5×, with workloads
returning long symbolic expressions (`factor`, `expand`) seeing the largest
wins. Set `GIAC_INVOKE_CMD_STRING_PATH=1` to disable the fast path. See
`docs/src/developer/invoke_cmd_fastpath.md` for details.

# See also
- [`giac_eval`](@ref): Direct string evaluation
- [`Giac.search_commands`](@ref): Find available commands
- `giac_help`: Get raw help for a command
"""
function invoke_cmd(cmd::Symbol, args...)::GiacExpr
    # Validate command exists (using Symbol directly)
    if !isempty(VALID_COMMANDS) && cmd ∉ VALID_COMMANDS
        # Use suggest_commands from command_registry.jl (005-nearest-command-suggestions)
        suggestions = suggest_commands(cmd)
        suggestion_text = _format_suggestions(suggestions)
        throw(GiacError("Unknown command: $cmd.$suggestion_text", :eval))
    end

    # Warn about Julia conflicts (008-all-giac-commands, FR-010)
    # This helps users understand why certain commands can't be exported directly
    _warn_conflict(cmd)

    # Rendering commands (071-latex-render-form): GIAC re-evaluates command
    # arguments, which collapses results like ifactor(360) == 2^3*3^2*5 back to
    # 360. Quoting each GiacExpr argument keeps the expression as given.
    if cmd in RENDER_COMMANDS
        args = map(_hold_render_arg, args)
    end

    # GIAC's evalf to n digits of a rootof leaves epsilon at 10⁻ⁿ for the session, after which
    # numeric integrals return two estimates: epsilon is put back
    if cmd === :evalf && length(args) >= 2 && !get(task_local_storage(), :giac_evalf_kept, false)
        return parentmodule(@__MODULE__)._keeping_epsilon() do
            task_local_storage(() -> invoke_cmd(cmd, args...), :giac_evalf_kept, true)
        end
    end

    # Fast path (069-invoke-cmd-fastpath): bypass _arg_to_giac_string + giac_eval
    # when every argument has a direct Gen representation. Set
    # GIAC_INVOKE_CMD_STRING_PATH=1 to disable globally.
    if !_fastpath_disabled[] && all(_has_direct_gen, args)
        return _invoke_cmd_direct(cmd, args)
    end

    # Convert arguments to GIAC strings
    arg_strings = String[]
    for arg in args
        try
            push!(arg_strings, _arg_to_giac_string(arg))
        catch e
            if e isa ArgumentError
                rethrow()
            end
            throw(ArgumentError("Cannot convert argument of type $(typeof(arg)) to GIAC format"))
        end
    end

    # Build and execute command (convert Symbol to String only at C++ boundary)
    cmd_str = string(cmd)
    cmd_string = _build_command_string(cmd_str, arg_strings)

    @debug "invoke_cmd string path" cmd=cmd nargs=length(args)

    return with_giac_lock() do
        giac_eval(cmd_string)
    end
end

# String variant for convenience
invoke_cmd(cmd::String, args...)::GiacExpr = invoke_cmd(Symbol(cmd), args...)

# Export invoke_cmd
export invoke_cmd

# ============================================================================
# Held Command Display (055-held-cmd-display)
# ============================================================================

"""
    hold_cmd(cmd::Symbol, args...) -> HeldCmd

Create a held (unevaluated) representation of a GIAC command.

Like `invoke_cmd`, but does NOT execute the command. Instead, returns a
`HeldCmd` object that can be displayed with LaTeX rendering in notebooks
and executed later via `release`.

# Arguments
- `cmd::Symbol`: GIAC command name (e.g., `:integrate`, `:diff`, `:factor`)
- `args...`: Command arguments (GiacExpr, String, Number, Symbol, AbstractVector)

# Returns
- `HeldCmd`: An unevaluated command object with rich display

# Throws
- `GiacError(:eval)`: If command name is not a valid GIAC command

# Examples
```julia
using Giac
using Giac.Commands: hold_cmd, release

@giac_var x
h = hold_cmd(:integrate, x^2, x)  # No execution — returns HeldCmd
display(h)                          # Renders ∫ x² dx in notebooks
result = release(h)                 # Now executes: returns x³/3
```

# See also
- [`invoke_cmd`](@ref): Execute a command immediately
- [`release`](@ref): Execute a HeldCmd
- [`HeldCmd`](@ref): The held command type
"""
function hold_cmd(cmd::Symbol, args...)::HeldCmd
    # Validate command exists (same validation as invoke_cmd)
    if !isempty(VALID_COMMANDS) && cmd ∉ VALID_COMMANDS
        suggestions = suggest_commands(cmd)
        suggestion_text = _format_suggestions(suggestions)
        throw(GiacError("Unknown command: $cmd.$suggestion_text", :eval))
    end

    return HeldCmd(cmd, args)
end

# String variant for convenience
hold_cmd(cmd::String, args...)::HeldCmd = hold_cmd(Symbol(cmd), args...)

"""
    release(held::HeldCmd) -> GiacExpr

Execute a held command and return the result.

Takes a `HeldCmd` created by `hold_cmd` and executes it via `invoke_cmd`,
returning the computed `GiacExpr` result.

# Arguments
- `held::HeldCmd`: A held command to execute

# Returns
- `GiacExpr`: Result of executing the held command

# Examples
```julia
using Giac
using Giac.Commands: hold_cmd, release

@giac_var x
h = hold_cmd(:integrate, x^2, x)
result = release(h)  # Returns x³/3
```

# See also
- [`hold_cmd`](@ref): Create a HeldCmd
- [`invoke_cmd`](@ref): Direct command execution
"""
function release(held::HeldCmd)::GiacExpr
    return invoke_cmd(held.cmd, held.args...)
end

export hold_cmd, release

# ============================================================================
# Docstring Generation (026-julia-help-docstrings)
# ============================================================================

"""
Standard warning text appended to docstrings with examples.
Explains GIAC/Julia syntax differences.
"""
const GIAC_SYNTAX_WARNING = """

**Note**: Examples use GIAC syntax which may differ from Julia.
In Julia, use string expressions: `factor(giac_eval("x^4-1"))`
Or with symbolic variables: `@giac_var x; factor(x^4-1)`
"""

"""
    _build_docstring(cmd::Symbol; is_base_extension::Bool=false) -> String

Build a formatted Julia docstring for a GIAC command.

# Arguments
- `cmd::Symbol`: The GIAC command name
- `is_base_extension::Bool`: Whether this extends a Base function (adds note)

# Returns
- `String`: A properly formatted docstring for use with `@doc`

# Contract
- Includes command name in signature format
- Includes "GIAC command:" label
- Includes description from `help(cmd)`
- Includes related commands section if non-empty
- Includes examples section if non-empty
- Includes syntax warning when examples are present
- Includes Base extension note when `is_base_extension=true`
- Returns fallback message for commands without help
"""
function _build_docstring(cmd::Symbol; is_base_extension::Bool=false)::String
    cmd_str = string(cmd)

    # Get help information, suppressing any GIAC error output
    # Some commands (keywords like "alors", "then", "to") cause GIAC syntax errors
    hr = try
        redirect_stderr(devnull) do
            help(cmd)
        end
    catch
        # Fallback if help retrieval fails
        return """
    $cmd_str(args...)

GIAC command: `$cmd_str`

No detailed documentation available for this command.

Use `help(:$cmd_str)` for GIAC's built-in help system.
"""
    end

    # Build the docstring
    parts = String[]

    # Signature
    if is_base_extension
        push!(parts, "    Base.$cmd_str(expr::GiacExpr, args...)")
    else
        push!(parts, "    $cmd_str(expr::GiacInput, args...)")
    end
    push!(parts, "")

    # GIAC command label
    push!(parts, "GIAC command: `$cmd_str`")
    push!(parts, "")

    # Base extension note
    if is_base_extension
        push!(parts, "This method extends `Base.$cmd_str` for `GiacExpr` arguments.")
        push!(parts, "")
    end

    # Description
    if !isempty(hr.description) && !startswith(hr.description, "[No help found")
        push!(parts, hr.description)
        push!(parts, "")
    else
        push!(parts, "No detailed description available.")
        push!(parts, "")
    end

    # Related commands
    if !isempty(hr.related)
        push!(parts, "# Related Commands")
        for rel in hr.related
            push!(parts, "- `$rel`")
        end
        push!(parts, "")
    end

    # Examples
    if !isempty(hr.examples)
        push!(parts, "# Examples (GIAC syntax)")
        push!(parts, "```giac")
        for ex in hr.examples
            push!(parts, ex)
        end
        push!(parts, "```")
        push!(parts, GIAC_SYNTAX_WARNING)
    end

    return join(parts, "\n")
end

# ============================================================================
# Helper Functions for Conflict Resolution (023-conflicts-multidispatch)
# ============================================================================

"""
    _extendable_conflicts() -> Set{Symbol}

Return the set of JULIA_CONFLICTS commands that CAN be extended via multiple dispatch.

This excludes Julia keywords (`:if`, `:for`, `:while`, etc.) which cannot be used
as function names. The remaining conflicts (builtins, math functions, linear algebra)
can have new methods added for GiacExpr types.

# Returns
- `Set{Symbol}`: Commands from JULIA_CONFLICTS that are valid GIAC commands and
  are not Julia keywords.

# Example
```julia
extendable = Giac.Commands._extendable_conflicts()
:zeros in extendable  # true (builtin, can be extended)
:if in extendable     # false (keyword, cannot be extended)
```

# See also
- [`JULIA_CONFLICTS`](@ref): All conflicting commands
- [`CONFLICT_CATEGORIES`](@ref): Categorization by conflict type
"""
function _extendable_conflicts()::Set{Symbol}
    # Get all non-keyword conflicts
    keywords = CONFLICT_CATEGORIES[:keyword]
    extendable = setdiff(JULIA_CONFLICTS, keywords)

    # Filter to only valid GIAC commands
    if !isempty(VALID_COMMANDS)
        extendable = intersect(extendable, VALID_COMMANDS)
    end

    return extendable
end

"""
    _has_giac_method(cmd::Symbol) -> Bool

Check if a GiacExpr method already exists for the given command.

This is used to detect Tier 1 wrappers (defined in command_utils.jl) which should
not be overridden by the slower invoke_cmd-based methods.

# Arguments
- `cmd::Symbol`: Command name to check

# Returns
- `true` if a method `Base.\$cmd(::GiacExpr, ...)` already exists
- `false` otherwise

# Example
```julia
_has_giac_method(:sin)   # true (Tier 1 wrapper exists)
_has_giac_method(:zeros) # false (no existing method)
```
"""
function _has_giac_method(cmd::Symbol)::Bool
    # Check if the command exists in Base or LinearAlgebra
    local func
    if isdefined(Base, cmd)
        func = getfield(Base, cmd)
    elseif isdefined(LinearAlgebra, cmd)
        func = getfield(LinearAlgebra, cmd)
    else
        return false
    end

    if !(func isa Function)
        return false
    end

    # Check if there's a method for GiacExpr
    return hasmethod(func, Tuple{GiacExpr})
end

# ============================================================================
# Runtime Function Generation
# ============================================================================

"""
    _generate_command_functions()

Generate wrapper functions at runtime for all exportable GIAC commands.

This function is called during module initialization to create Julia functions
for each command in `exportable_commands()`. The functions are exported from
`Giac.Commands` for use with `using Giac.Commands` or selective imports.

# Implementation Notes

- Uses `@eval` to define functions at runtime
- Each generated function calls `invoke_cmd` internally
- Only generates functions for commands not in `JULIA_CONFLICTS`
- Exports all generated functions

# Performance

- Called once during module load
- Generates ~2000 functions in typically < 1 second
- No impact on command execution performance
"""
# `GiacMatrix` is an `AbstractMatrix`: functions that Julia's array code relies on (or that
# return Julia values for any symbolic matrix, like `rank`) keep their generic meaning for it
# rather than becoming GIAC commands. Ported from Kahli Burke's `ergonomics` branch.
const _ARRAY_PROTOCOL = Set([:axes, :copy, :cat, :stack, :reverse, :repeat, :sort, :sortperm,
                             :cumsum, :extrema, :zeros, :rank, :nullspace, :dot, :⋅, :cross, :×])
_giac_matrix_method(cmd::Symbol) = cmd ∉ _ARRAY_PROTOCOL

function _generate_command_functions()
    # Skip generation during precompilation of extensions to avoid
    # "Evaluation into closed module" errors. The functions will be
    # generated when the package is actually loaded at runtime.
    if ccall(:jl_generating_output, Cint, ()) != 0
        @debug "Skipping command function generation during precompilation"
        return
    end

    for cmd in exportable_commands()  # exportable_commands() returns Vector{Symbol}
        # Skip if already defined IN THIS MODULE (not inherited from Base)
        # We check parentmodule to distinguish our definitions from Base bindings
        if isdefined(@__MODULE__, cmd)
            binding = getfield(@__MODULE__, cmd)
            # Only skip if it's a function we defined in this module
            if binding isa Function && parentmodule(binding) === @__MODULE__
                continue
            end
            # Otherwise, we want to shadow the Base binding with our GIAC command
        end

        # Generate the wrapper function with docstring (026-julia-help-docstrings)
        # For Base-extended functions: Keep GiacExpr constraint to avoid method ambiguity
        # For new functions: Use GiacInput to accept native Julia types (022-julia-type-conversion)
        if isdefined(Base, cmd)
            # Extend Base function - adds method to existing function
            # Keep GiacExpr constraint to avoid conflicts with Base methods
            # e.g., Base.sin(Float64) should not be overridden by our method
            docstring = _build_docstring(cmd; is_base_extension=true)
            @eval @doc $docstring function Base.$(cmd)(first_arg::GiacExpr, rest...)::GiacExpr
                invoke_cmd($(QuoteNode(cmd)), first_arg, rest...)
            end
            # GiacMatrix support (058-commands-matrix-support)
            _giac_matrix_method(cmd) && @eval function Base.$(cmd)(first_arg::GiacMatrix, rest...)::GiacExpr
                invoke_cmd($(QuoteNode(cmd)), first_arg, rest...)
            end
            # Note: Don't export Base-extended functions - they're already accessible
            # via Base and exporting undefined local symbols causes Aqua warnings
        else
            # Create new function with GiacInput type constraint
            # This enables native Julia type usage: ifactor(1000), isprime(17), etc.
            docstring = _build_docstring(cmd; is_base_extension=false)
            # Skip GiacMatrix method if cmd collides with a LinearAlgebra Type (e.g., LQ, LU, QR, SVD)
            _skip_matrix = isdefined(LinearAlgebra, cmd) && getfield(LinearAlgebra, cmd) isa Type
            if _skip_matrix
                @eval begin
                    @doc $docstring function $(cmd)(first_arg::GiacInput, rest...)::GiacExpr
                        invoke_cmd($(QuoteNode(cmd)), first_arg, rest...)
                    end
                    export $(cmd)
                end
            else
                @eval begin
                    @doc $docstring function $(cmd)(first_arg::GiacInput, rest...)::GiacExpr
                        invoke_cmd($(QuoteNode(cmd)), first_arg, rest...)
                    end
                    # GiacMatrix support (058-commands-matrix-support)
                    function $(cmd)(first_arg::GiacMatrix, rest...)::GiacExpr
                        invoke_cmd($(QuoteNode(cmd)), first_arg, rest...)
                    end
                    # a Julia matrix of expressions, as products and slices of a Giac matrix give
                    function $(cmd)(first_arg::AbstractMatrix{GiacExpr}, rest...)::GiacExpr
                        invoke_cmd($(QuoteNode(cmd)), GiacMatrix(first_arg), rest...)
                    end
                    export $(cmd)
                end
            end
        end
    end

    @debug "Generated and exported command functions in Giac.Commands"

    # ========================================================================
    # Generate Base extensions for extendable JULIA_CONFLICTS (023-conflicts-multidispatch)
    # ========================================================================
    # These are commands that conflict with Julia but CAN be extended via multiple dispatch
    # (excludes keywords like :if, :for which cannot be function names)

    conflict_count = 0
    for cmd in _extendable_conflicts()
        # Skip if method already exists (Tier 1 wrappers in command_utils.jl)
        if _has_giac_method(cmd)
            @debug "Skipping $cmd - Tier 1 wrapper exists"
            continue
        end

        # Check if this is a Base, LinearAlgebra, or standalone function
        if isdefined(Base, cmd)
            func = getfield(Base, cmd)
            if func isa Core.Builtin || func isa Core.IntrinsicFunction
                @debug "Skipping $cmd - Julia builtin"
                continue
            end
            if func isa Function
                # Generate docstring for Base extension (026-julia-help-docstrings)
                docstring = _build_docstring(cmd; is_base_extension=true)
                @eval @doc $docstring function Base.$(cmd)(first_arg::GiacExpr, rest...)::GiacExpr
                    invoke_cmd($(QuoteNode(cmd)), first_arg, rest...)
                end
                # GiacMatrix support (058-commands-matrix-support)
                _giac_matrix_method(cmd) && @eval function Base.$(cmd)(first_arg::GiacMatrix, rest...)::GiacExpr
                    invoke_cmd($(QuoteNode(cmd)), first_arg, rest...)
                end
                conflict_count += 1
            end
        elseif isdefined(LinearAlgebra, cmd) && getfield(LinearAlgebra, cmd) isa Function
            # LinearAlgebra function extension (058-commands-matrix-support)
            docstring = _build_docstring(cmd; is_base_extension=true)
            @eval @doc $docstring function LinearAlgebra.$(cmd)(first_arg::GiacExpr, rest...)::GiacExpr
                invoke_cmd($(QuoteNode(cmd)), first_arg, rest...)
            end
            _giac_matrix_method(cmd) && @eval function LinearAlgebra.$(cmd)(first_arg::GiacMatrix, rest...)::GiacExpr
                invoke_cmd($(QuoteNode(cmd)), first_arg, rest...)
            end
            conflict_count += 1
        else
            # Skip if cmd collides with a Type in LinearAlgebra (e.g., LQ, LU, QR, SVD)
            if isdefined(LinearAlgebra, cmd) && getfield(LinearAlgebra, cmd) isa Type
                @debug "Skipping $cmd - conflicts with LinearAlgebra type"
                continue
            end
            # Skip if cmd is already imported from parent Giac module (e.g., help)
            if isdefined(@__MODULE__, cmd)
                @debug "Skipping $cmd - already defined in Commands (imported from parent)"
                continue
            end
            # Command not in Base or LinearAlgebra (e.g., trace)
            # Safe to create GiacMatrix-only methods via multiple dispatch (058-commands-matrix-support)
            docstring = _build_docstring(cmd; is_base_extension=false)
            @eval begin
                @doc $docstring function $(cmd)(first_arg::GiacMatrix, rest...)::GiacExpr
                    invoke_cmd($(QuoteNode(cmd)), first_arg, rest...)
                end
                export $(cmd)
            end
            conflict_count += 1
        end
    end

    @debug "Generated $conflict_count Base extensions for JULIA_CONFLICTS commands"
end

# ============================================================================
# Module Initialization
# ============================================================================

# Note: __init__() removed because nested module __init__ runs BEFORE parent module __init__
# Command generation is now triggered by Giac.__init__() after VALID_COMMANDS is populated.
# See: https://docs.julialang.org/en/v1/manual/modules/#Module-initialization-and-precompilation

end # module Commands
