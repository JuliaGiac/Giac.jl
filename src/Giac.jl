"""
    Giac

A Julia wrapper for the GIAC computer algebra system.

Provides symbolic expression evaluation, calculus operations, polynomial
manipulation, and linear algebra with a Julia-native API.

# Core Exports
- `GiacExpr`: Symbolic expression type
- `GiacContext`: Evaluation context
- `GiacMatrix`: Symbolic matrix type
- `GiacError`: Exception type for GIAC errors
- `giac_eval`: Evaluate expression strings
- `@giac_var`: Create symbolic variables from Julia symbols
- `to_julia`: Convert GiacExpr to Julia types
- `invoke_cmd`: Universal command invocation (works for ALL commands)

# Command Access

GIAC commands are available through the `Giac.Commands` submodule:

```julia
using Giac

# Use invoke_cmd for any command (always available)
invoke_cmd(:factor, giac_eval("x^2-1"))
invoke_cmd(:sin, giac_eval("pi/6"))  # Works for conflicting commands too

# Import commands selectively (recommended)
using Giac.Commands: factor, expand, diff
factor(giac_eval("x^2-1"))

# Or import all ~2000+ commands
using Giac.Commands
factor(giac_eval("x^2-1"))
ifactor(giac_eval("120"))
```

# Quick Start
```julia
using Giac

# Declare symbolic variables with @giac_var macro
@giac_var x y

# Build and manipulate expressions using Giac.Commands
using Giac.Commands: factor, expand, diff
expr = giac_eval("x^2 + 2*x*y + y^2")
result = factor(expr)   # (x+y)^2

# Or use string-based evaluation directly
result = giac_eval("factor(x^2 - 1)")
println(result)  # (x-1)*(x+1)
```

# See also
- [`Giac.Commands`](@ref): Submodule with all exportable commands
- [`invoke_cmd`](@ref): Universal command invocation
"""
module Giac

using LinearAlgebra
using Tables

# Include source files
include("types.jl")
include("utils.jl")
include("wrapper.jl")
include("command_registry.jl")
include("command_utils.jl")
include("namespace_commands.jl")
include("api.jl")
include("operators.jl")
include("macros.jl")
include("decl.jl")
include("tables.jl")
include("substitute.jl")
include("build_function.jl")

# Differential operator (068-multivar-d-operator)
include("differential.jl")

# GenTypes module - Scoped enum for GIAC types (041-scoped-type-enum)
include("gen_types.jl")

# Output handling (029-output-handling)
include("introspection.jl")
include("conversion.jl")
include("iteration.jl")

# Held command display (055-held-cmd-display)
include("held_cmd.jl")

# Include Commands submodule (009-commands-submodule)
include("Commands.jl")


# Include Constants submodule (053-symbolic-pi-constant)
include("Constants.jl")

# Types
export GiacExpr, GiacContext, GiacMatrix, GiacError, HelpResult, GiacInput

# Derivative operator (035-derivative-operator)
# Differential is the canonical SciML-style form (068-multivar-d-operator).
# D is retained as a deprecated alias and will be removed in the next published release.
export D, Differential, DerivativeExpr, DerivativePoint, DerivativeCondition

# expand_derivatives — Symbolics.jl-compatible no-op / DerivativeExpr forcer.
export expand_derivatives

# Core functions
export giac_eval, to_julia, list_commands, help_count

# Macros (011-giac-symbol-macro, 012-giac-several-var)
export @giac_var, @giac_several_vars

# Command invocation (009-commands-submodule)
# invoke_cmd replaces giac_cmd - available from main module and Giac.Commands
export invoke_cmd
export search_commands, commands_in_category, command_info, list_categories, giac_help

# Command suggestions (005-nearest-command-suggestions)
export suggest_commands, set_suggestion_count, get_suggestion_count

# Description search (006-search-command-description)
export search_commands_by_description

# Tables.jl compatibility (025-tables-compatibility)
export commands_table, clear_commands_cache!, CommandsTable

# Substitute function (028-substitute-mechanism)
export substitute

# Build function (066-build-function)
export build_function

# Type introspection (029-output-handling, 041-scoped-type-enum)
# Legacy GIAC_* constants removed - use Giac.GenTypes: T, INT, DOUBLE, etc.
export giac_type, subtype
export is_integer, is_numeric, is_vector, is_symbolic, is_identifier
export is_fraction, is_complex, is_string, is_boolean
export numer, denom, real_part, imag_part
export symb_funcname, symb_argument

# All commands access (008-all-giac-commands)
export JULIA_CONFLICTS, exportable_commands, is_valid_command, conflict_reason
export available_commands, reset_conflict_warnings!

# GiacCommand type (kept for compatibility, callable uses invoke_cmd internally)
export GiacCommand

# Held command display (055-held-cmd-display)
export HeldCmd, HeldEquation, hold_cmd, release

# Re-export invoke_cmd from Commands submodule (009-commands-submodule)
# This makes invoke_cmd available directly after `using Giac`
using .Commands: invoke_cmd

# Re-export hold_cmd and release from Commands submodule (055-held-cmd-display)
using .Commands: hold_cmd, release

# Conversion functions (extended by GiacSymbolicsExt, GiacMathJSONExt, GiacSymPyExt, and GiacNemoExt)
export to_giac, to_symbolics, to_mathjson, to_sympy, to_nemo

# MCP server entry point (extended by GiacMCPExt when ModelContextProtocol is loaded)
export giac_mcp_server

"""
    to_giac(expr)

Convert an expression to GiacExpr. Extended by GiacSymbolicsExt for Symbolics.Num types,
by GiacMathJSONExt for MathJSON.AbstractMathJSONExpr types, by GiacSymPyExt for
SymPy.Sym types, by GiacLibPARIExt for LibPARI.Gen types, and by GiacNemoExt for Nemo 
ring elements (ZZRingElem, QQFieldElem, polynomials, finite-field and number-field 
elements, matrices).
"""
function to_giac end

"""
    to_symbolics(expr::GiacExpr)

Convert a GiacExpr to a Symbolics.jl expression. Extended by GiacSymbolicsExt.
"""
function to_symbolics end

"""
    to_mathjson(expr::GiacExpr)
    to_mathjson(m::GiacMatrix)

Convert a GiacExpr or GiacMatrix to a MathJSON.jl expression. Extended by GiacMathJSONExt.
"""
function to_mathjson end

"""
    to_sympy(expr::GiacExpr)

Convert a GiacExpr to a SymPy.jl (`SymPy.Sym`) expression. Extended by GiacSymPyExt.

This function is **extended by `GiacSymPyExt` when `SymPy` is loaded**. Calling it
without first loading `SymPy` raises a `MethodError`.
"""
function to_sympy end

"""
    to_nemo(expr::GiacExpr, parent)

Convert a GiacExpr into a Nemo.jl element of the given parent ring
(`ZZ`, `QQ`, a univariate polynomial ring, an `AbsSimpleNumField`, an
`FqField`, or a `MatSpace`). Extended by `GiacNemoExt` when `Nemo` is
loaded.

The parent ring is required because Nemo elements are parent-typed while a
`GiacExpr` is an untyped symbolic tree. Calling this without first loading
`Nemo` raises a `MethodError`.
"""
function to_nemo end

"""
    giac_mcp_server(; name="giac-cas", version=string(pkgversion(Giac)), kwargs...) -> ModelContextProtocol.Server

Construct an MCP (Model Context Protocol) server exposing the Giac CAS engine
to LLM clients such as Claude Desktop, Claude Code, and Cursor. The returned
`Server` advertises two tools:

- `giac_eval` — evaluate any Giac/Xcas expression (string in → result out).
- `giac_search` — search Giac's ~2200 command catalogue by keyword.

The `version` default reflects the currently loaded Giac.jl version, so the
MCP `initialize` handshake's `serverInfo.version` stays in sync with the
package automatically.

This function is **extended by `GiacMCPExt` when `ModelContextProtocol` is loaded**.
Calling it without first loading `ModelContextProtocol` raises a `MethodError`
with Julia's standard weak-extension diagnostic — install and load
`ModelContextProtocol.jl` to activate the extension:

```julia
using Pkg; Pkg.add("ModelContextProtocol")
using Giac, ModelContextProtocol
start!(giac_mcp_server())   # blocks on STDIO transport
```

`kwargs...` are forwarded to `ModelContextProtocol.mcp_server`. See
`docs/src/extensions/mcp.md` for the full setup guide.
"""
function giac_mcp_server end

# Note: Calculus and algebra functions (giac_diff, giac_integrate, giac_factor, etc.)
# have been removed in favor of Giac.Commands equivalents.
# Use: Giac.Commands.diff, Giac.Commands.integrate, Giac.Commands.factor, etc.
# Or: invoke_cmd(:diff, ...), invoke_cmd(:integrate, ...), invoke_cmd(:factor, ...)

# Default context (initialized in __init__)
const DEFAULT_CONTEXT = Ref{GiacContext}()

"""
    __init__()

Initialize the Giac module at runtime. Sets up the default context,
loads the GIAC library, and initializes the command registry.

# Initialization Steps
1. Initialize the GIAC library and default context
2. Populate the command registry from GIAC's help database
3. Generate wrapper functions for all exportable commands in Giac.Commands

# Performance
- Total initialization typically completes in < 5 seconds
- Runtime function generation adds ~1 second for ~2000 functions

# Note
Command generation is triggered here (not in Commands.__init__) because nested
module __init__ functions run BEFORE parent module __init__ in Julia.
"""
function __init__()
    try
        init_giac_library()
        DEFAULT_CONTEXT[] = GiacContext(Val(:shared))
        # Initialize command registry (003-giac-commands)
        _init_command_registry()
        # Generate command functions in Commands submodule (009-commands-submodule)
        # Note: This must happen here because nested module __init__ runs BEFORE parent __init__
        Commands._generate_command_functions()
        # Initialize symbolic constants (053-symbolic-pi-constant)
        Constants._init_constants()
    catch e
        @error "Failed to initialize GIAC library" exception=e
        rethrow()
    end
end

"""
    list_commands()

Return a vector of all available GIAC command names.

# Example
```julia
cmds = list_commands()
println("Number of commands: ", length(cmds))
println("First 10: ", cmds[1:10])
```
"""
function list_commands()
    if GiacCxxBindings._have_library
        cmds_str = GiacCxxBindings.list_commands()
        return split(cmds_str, '\n')
    end
    return String[]
end

"""
    help_count()

Return the number of commands in the GIAC help database.
"""
function help_count()
    if GiacCxxBindings._have_library
        return GiacCxxBindings.help_count()
    end
    return 0
end

# ============================================================================
# LaTeX Display Support (014-pluto-latex-notebook)
# ============================================================================

"""
    Base.show(io::IO, ::MIME"text/latex", expr::GiacExpr)

Display a GiacExpr as LaTeX. Enables automatic LaTeX rendering in Pluto notebooks
and other environments that support the `text/latex` MIME type.

# Example
In Pluto, simply evaluating a GiacExpr will render it as formatted mathematics:
```julia
using Giac
f = giac_eval("2/(1-x)")  # Renders as LaTeX fraction in Pluto
```
"""
function Base.show(io::IO, ::MIME"text/latex", expr::GiacExpr)
    latex_result = invoke_cmd(:latex, expr)
    latex_str = string(latex_result)
    if length(latex_str) > 2
        print(io, "\$\$", latex_str[2:end-1], "\$\$")  # Remove surrounding quotes from GIAC's LaTeX output
    else
        # Fallback to default display if LaTeX conversion fails
        print(io, string(expr))
    end
end

"""
    Base.show(io::IO, ::MIME"text/latex", m::GiacMatrix)

Display a GiacMatrix as LaTeX. Enables automatic LaTeX rendering in Pluto notebooks
and other environments that support the `text/latex` MIME type.

# Example
In Pluto, simply evaluating a GiacMatrix will render it as a formatted matrix:
```julia
using Giac
M = GiacMatrix([1 2; 3 4])  # Renders as LaTeX matrix in Pluto
```
"""
function Base.show(io::IO, ::MIME"text/latex", m::GiacMatrix)
    # Build matrix string in GIAC format: [[a,b],[c,d]]
    rows_str = String[]
    for i in 1:m.rows
        row_elements = String[]
        for j in 1:m.cols
            push!(row_elements, string(m[i, j]))
        end
        push!(rows_str, "[" * join(row_elements, ",") * "]")
    end
    matrix_str = "[" * join(rows_str, ",") * "]"

    # Call latex command on the matrix string
    matrix_expr = giac_eval(matrix_str)
    latex_result = invoke_cmd(:latex, matrix_expr)
    latex_str = string(latex_result)
    if length(latex_str) > 2
        print(io, "\$\$", latex_str[2:end-1], "\$\$")  # Remove surrounding quotes from GIAC's LaTeX output
    else
        # Fallback to default display if LaTeX conversion fails
        print(io, string(m))
    end
end

end # module Giac
