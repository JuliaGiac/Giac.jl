# Command registry for Giac.jl
# Metadata, categories, discovery, and validation for GIAC commands

# ============================================================================
# Suggestion Configuration (005-nearest-command-suggestions)
# ============================================================================

"""
Default number of command suggestions to display.
"""
const DEFAULT_SUGGESTION_COUNT = 4

# ============================================================================
# Search Configuration (006-search-command-description)
# ============================================================================

"""
Default maximum number of search results to return.
"""
const DEFAULT_SEARCH_LIMIT = 20

"""
Global configuration for the number of suggestions to return.
Use `set_suggestion_count(n)` to modify and `get_suggestion_count()` to read.
"""
const _suggestion_count = Ref{Int}(DEFAULT_SUGGESTION_COUNT)

# ============================================================================
# HelpResult Type (004-formatted-help-output)
# ============================================================================

"""
    HelpResult

A structured representation of parsed GIAC command help information.

# Fields
- `command::String`: The command name being documented
- `description::String`: Description text from GIAC help
- `related::Vector{String}`: List of related command names
- `examples::Vector{String}`: List of individual example expressions

# Example
```julia
# Use Julia's help system for interactive help:
# ?factor (after using Giac.Commands: factor)

# For programmatic access, use Giac.help (internal) or giac_help:
result = Giac.help(:factor)
result.command      # "factor"
result.description  # "Factorizes a polynomial."
result.related      # ["ifactor", "partfrac", "normal"]
result.examples     # ["factor(x^4-1)", "factor(x^4-4,sqrt(2))", ...]
```

# See also
- [`giac_help`](@ref): Get raw help string
"""
struct HelpResult
    command::String
    description::String
    related::Vector{String}
    examples::Vector{String}
end

# ============================================================================
# HelpResult Display Methods (004-formatted-help-output)
# ============================================================================

"""
    Base.show(io::IO, ::MIME"text/plain", result::HelpResult)

Formatted multi-line display for REPL and notebooks.
"""
function Base.show(io::IO, ::MIME"text/plain", result::HelpResult)
    # Command name with Unicode underline
    println(io, result.command)
    println(io, repeat('═', length(result.command)))
    println(io)

    # Description section
    if isempty(result.description)
        println(io, "Description:")
        println(io, "  [No description available]")
    else
        println(io, "Description:")
        println(io, "  ", result.description)
    end

    # Related section (omit if empty)
    if !isempty(result.related)
        println(io)
        println(io, "Related:")
        println(io, "  ", join(result.related, ", "))
    end

    # Examples section (omit if empty)
    if !isempty(result.examples)
        println(io)
        println(io, "Examples:")
        for ex in result.examples
            println(io, "  • ", ex)
        end
    end
end

"""
    Base.show(io::IO, result::HelpResult)

Compact single-line representation.
"""
function Base.show(io::IO, result::HelpResult)
    print(io, "HelpResult(:$(result.command), $(length(result.related)) related, $(length(result.examples)) examples)")
end

# ============================================================================
# HelpResult Parsing (004-formatted-help-output)
# ============================================================================

"""
    _parse_help(raw::String, cmd::String) -> HelpResult

Parse raw GIAC help text into a structured HelpResult.

# Arguments
- `raw`: Raw help text from GIAC
- `cmd`: Command name (for the result)

# Returns
- `HelpResult` with parsed fields

# Parsing Algorithm
1. Extract "Description: ..." line
2. Extract "Related: ..." line and split by ", "
3. Extract "Examples:" section and split by ";"
"""
function _parse_help(raw::String, cmd::String)::HelpResult
    description = ""
    related = String[]
    examples = String[]

    if isempty(raw)
        return HelpResult(cmd, description, related, examples)
    end

    lines = split(raw, '\n')

    for (i, line) in enumerate(lines)
        line_str = String(line)

        # Extract description
        if startswith(line_str, "Description: ")
            description = strip(line_str[14:end])
        # Extract related commands
        elseif startswith(line_str, "Related: ")
            related_str = strip(line_str[10:end])
            if !isempty(related_str)
                related = [strip(r) for r in split(related_str, ",")]
                # Filter out empty entries
                related = filter(!isempty, related)
            end
        # Extract examples
        elseif startswith(line_str, "Examples:")
            # Examples may be on the same line or following lines
            examples_text = strip(line_str[10:end])
            # Also gather any following lines
            for j in (i+1):length(lines)
                next_line = strip(String(lines[j]))
                if !isempty(next_line) && !startswith(next_line, "Description:") && !startswith(next_line, "Related:")
                    examples_text *= next_line
                end
            end
            # Split by semicolon
            if !isempty(examples_text)
                examples = [strip(e) for e in split(examples_text, ";")]
                # Filter out empty entries
                examples = filter(!isempty, examples)
            end
            break  # We've processed examples, which is typically last
        end
    end

    return HelpResult(cmd, description, related, examples)
end

# ============================================================================
# CommandInfo Type
# ============================================================================

"""
    CommandInfo

Metadata about a single GIAC command.

# Fields
- `name::String`: Command name (e.g., "factor", "sin")
- `category::Symbol`: Primary category (e.g., `:algebra`, `:trigonometry`)
- `aliases::Vector{String}`: Alternative names for the command
- `doc::String`: Documentation string from GIAC help system

# Example
```julia
info = command_info(:factor)
println(info.name)      # "factor"
println(info.category)  # :algebra
```
"""
struct CommandInfo
    name::String
    category::Symbol
    aliases::Vector{String}
    doc::String
end

# ============================================================================
# Command Categories
# ============================================================================

"""
    COMMAND_CATEGORIES

Dictionary mapping category symbols to lists of command names (as Symbols).
Categories are based on mathematical domains.
"""
const COMMAND_CATEGORIES = Dict{Symbol, Vector{Symbol}}(
    :trigonometry => [
        :sin, :cos, :tan, :asin, :acos, :atan, :atan2,
        :sinh, :cosh, :tanh, :asinh, :acosh, :atanh,
        :cot, :sec, :csc, :acot, :asec, :acsc,
        :sinc, :sincos
    ],
    :calculus => [
        :diff, :integrate, :int, :limit, :series, :taylor,
        :derivative, :antiderivative, :gradient, :divergence, :curl,
        :laplacian, :hessian, :jacobian
    ],
    :algebra => [
        :factor, :expand, :simplify, :solve, :gcd, :lcm,
        :collect, :normal, :ratnormal, :horner, :canonical_form,
        :quo, :rem, :quorem, :proot, :cfactor
    ],
    :number_theory => [
        :ifactor, :isprime, :nextprime, :prevprime, :euler, :phi,
        :gcd, :lcm, :mod, :irem, :iquo, :isqrt, :icrt,
        :chinese, :jacobi, :legendre, :divisors, :sigma
    ],
    :linear_algebra => [
        :det, :inv, :trace, :transpose, :tran, :eigenvalues, :eigenvectors,
        :rank, :kernel, :image, :lu, :qr, :svd, :cholesky,
        :rref, :identity, :diag, :jordanblock
    ],
    :special_functions => [
        :gamma, :beta, :erf, :erfc, :zeta, :Ai, :Bi,
        :Si, :Ci, :Ei, :li, :digamma, :polygamma,
        :BesselJ, :BesselY, :BesselI, :BesselK
    ],
    :polynomials => [
        :degree, :coeff, :lcoeff, :tcoeff, :coeffs, :roots,
        :pcoeff, :poly2symb, :symb2poly, :resultant, :discriminant,
        :sturm, :sturmab, :realroot
    ],
    :combinatorics => [
        :binomial, :factorial, :perm, :comb, :fib, :fibonacci,
        :lucas, :stirling1, :stirling2, :bell, :catalan,
        :partition, :compositions
    ],
    :statistics => [
        :mean, :variance, :stddev, :median, :quartiles,
        :covariance, :correlation, :histogram, :boxwhisker,
        :normald, :binomial_cdf, :poisson
    ],
    :logic => [
        :and, :or, :not, :xor, :implies, :equiv,
        Symbol("true"), Symbol("false"), :assume, :about
    ],
    :geometry => [
        :point, :line, :circle, :polygon, :distance,
        :midpoint, :perpendicular, :parallel, :tangent,
        :inter, :area, :perimeter
    ],
    :other => Symbol[]  # Populated dynamically for uncategorized commands
)

"""
    CATEGORY_LOOKUP

Reverse lookup: command name (Symbol) → category symbol.
Populated by `_init_command_registry()`.
"""
const CATEGORY_LOOKUP = Dict{Symbol, Symbol}()

# ============================================================================
# Julia Conflicts Registry (008-all-giac-commands)
# ============================================================================

"""
    JULIA_CONFLICTS

Set of GIAC command names (as Symbols) that conflict with Julia keywords, builtins, or
standard library functions. These commands cannot be safely exported as
top-level functions but remain accessible via `invoke_cmd(:name, args...)`.

# Conflict Categories
- **Julia keywords**: `if`, `for`, `while`, `end`, `in`, `or`, `and`, etc.
- **Base builtins**: `eval`, `float`, `sum`, `prod`, `div`, `mod`, `abs`, etc.
- **Base math functions**: `sin`, `cos`, `tan`, `exp`, `log`, `sqrt`, etc.
- **LinearAlgebra**: `det`, `inv`, `trace`, `rank`, `transpose`, etc.

# Example
```julia
:eval in JULIA_CONFLICTS  # true
:factor in JULIA_CONFLICTS  # false

# Conflicting commands still work via invoke_cmd
invoke_cmd(:eval, giac_eval("2+3"))  # Returns 5
```

# See also
- [`exportable_commands`](@ref): Commands safe to export
- [`conflict_reason`](@ref): Get the conflict category for a command
"""
const JULIA_CONFLICTS = Set{Symbol}([
    # Julia keywords (reserved words)
    :if, :else, :elseif, :for, :while, :end, :begin,
    :try, :catch, :finally, :return, :break, :continue,
    :function, :macro, :module, :import, :export, :using,
    :let, :local, :global, :const, :do, :in, :isa,
    :where, Symbol("true"), Symbol("false"), :nothing, :missing,
    :struct, :mutable, :abstract, :primitive, :quote,
    :baremodule, :type, :immutable, :bitstype, :typealias,

    # GIAC keywords that overlap
    :or, :and, :not, :xor, :mod, :div,

    # Base builtins that would shadow
    :eval, :float, :sum, :prod, :rem, :Int, :Text,
    :min, :max, :abs, :sign, :round, :floor, :ceil,
    :real, :imag, :conj, :angle,
    :length, :size, :zeros, :ones, :fill, :push, :pop,
    :first, :last, :sort, :reverse, :map, :filter, :reduce,
    :zip, :enumerate, :collect, :copy, :deepcopy,
    :print, :println, :display, :show, :string, :parse,
    :read, :write, :open, :close, :flush,
    :error, :throw, :rethrow, :assert,
    :typeof, :isa, :convert, :promote,
    :get, :set, :delete, :keys, :values, :pairs,
    :union, :intersect, :setdiff, :issubset,
    :any, :all, :count, :findall, :findfirst, :findlast,
    :range, :step, :start, :stop,
    :time, :sleep, :wait, :notify,
    :rand, :randn, :seed,

    # Base math functions (defined in Base or often imported)
    :sin, :cos, :tan, :asin, :acos, :atan, :atan2,
    :sinh, :cosh, :tanh, :asinh, :acosh, :atanh,
    :sec, :csc, :cot, :asec, :acsc, :acot,
    :sech, :csch, :coth, :asech, :acsch, :acoth,
    :sinc, :sincos, :sinpi, :cospi,
    :exp, :exp2, :exp10, :expm1,
    :log, :log2, :log10, :log1p,
    :sqrt, :cbrt, :hypot,
    :gcd, :lcm, :gcdx,
    :factorial, :binomial,
    :isnan, :isinf, :isfinite, :isinteger, :isreal,
    :iseven, :isodd, :ispow2,
    :nextpow, :prevpow,
    :sign, :signbit, :copysign, :flipsign,
    :clamp, Symbol("clamp!"),
    :muladd, :fma,
    :modf, :rem, :mod, :divrem, :fldmod,
    :numerator, :denominator,

    # LinearAlgebra conflicts
    :det, :inv, :trace, :rank, :transpose, :adjoint,
    :norm, :normalize, :dot, :cross,
    :eigen, :eigvals, :eigvecs,
    :svd, :svdvals,
    :lu, :qr, :cholesky, :schur, :hessenberg,
    :diag, :diagm, :diagind,
    :tril, :triu, Symbol("tril!"), Symbol("triu!"),
    :I, :eye, :identity,
    :kron, :kronsum,
    :nullspace, :pinv,
    :cond, :opnorm, :factorize,
    :ishermitian, :issymmetric, :isposdef, :istriu, :istril,
    :lyap, :sylvester,

    # Statistics conflicts
    :mean, :median, :var, :std, :cov, :cor,
    :quantile, :percentile,

    # Other common conflicts
    :pi, :e, :im, :Inf, :NaN,
    :ans, :help,
])

"""
    CONFLICT_CATEGORIES

Mapping of conflict category symbols to the commands (as Symbols) in that category.
Used by `conflict_reason()` to determine why a command conflicts.
"""
const CONFLICT_CATEGORIES = Dict{Symbol, Set{Symbol}}(
    :keyword => Set{Symbol}([
        :if, :else, :elseif, :for, :while, :end, :begin,
        :try, :catch, :finally, :return, :break, :continue,
        :function, :macro, :module, :import, :export, :using,
        :let, :local, :global, :const, :do, :in, :isa,
        :where, Symbol("true"), Symbol("false"), :nothing, :missing,
        :struct, :mutable, :abstract, :primitive, :quote,
        :baremodule, :type, :immutable, :bitstype, :typealias,
        :or, :and, :not, :xor, :mod, :div,
    ]),
    :builtin => Set{Symbol}([
        :eval, :float, :sum, :prod, :rem, :Int, :Text,
        :min, :max, :abs, :sign, :round, :floor, :ceil,
        :real, :imag, :conj, :angle,
        :length, :size, :zeros, :ones, :fill, :push, :pop,
        :first, :last, :sort, :reverse, :map, :filter, :reduce,
        :zip, :enumerate, :collect, :copy, :deepcopy,
        :print, :println, :display, :show, :string, :parse,
        :read, :write, :open, :close, :flush,
        :error, :throw, :rethrow, :assert,
        :typeof, :isa, :convert, :promote,
        :get, :set, :delete, :keys, :values, :pairs,
        :union, :intersect, :setdiff, :issubset,
        :any, :all, :count, :findall, :findfirst, :findlast,
        :range, :step, :start, :stop,
        :time, :sleep, :wait, :notify,
        :rand, :randn, :seed,
        :pi, :e, :im, :Inf, :NaN, :ans, :help,
    ]),
    :base_math => Set{Symbol}([
        :sin, :cos, :tan, :asin, :acos, :atan, :atan2,
        :sinh, :cosh, :tanh, :asinh, :acosh, :atanh,
        :sec, :csc, :cot, :asec, :acsc, :acot,
        :sech, :csch, :coth, :asech, :acsch, :acoth,
        :sinc, :sincos, :sinpi, :cospi,
        :exp, :exp2, :exp10, :expm1,
        :log, :log2, :log10, :log1p,
        :sqrt, :cbrt, :hypot,
        :gcd, :lcm, :gcdx,
        :factorial, :binomial,
        :isnan, :isinf, :isfinite, :isinteger, :isreal,
        :iseven, :isodd, :ispow2,
        :nextpow, :prevpow,
        :sign, :signbit, :copysign, :flipsign,
        :clamp, Symbol("clamp!"),
        :muladd, :fma,
        :modf, :rem, :mod, :divrem, :fldmod,
        :numerator, :denominator,
    ]),
    :linear_algebra => Set{Symbol}([
        :det, :inv, :trace, :rank, :transpose, :adjoint,
        :norm, :normalize, :dot, :cross,
        :eigen, :eigvals, :eigvecs,
        :svd, :svdvals,
        :lu, :qr, :cholesky, :schur, :hessenberg,
        :diag, :diagm, :diagind,
        :tril, :triu, Symbol("tril!"), Symbol("triu!"),
        :I, :eye, :identity,
        :kron, :kronsum,
        :nullspace, :pinv,
        :cond, :opnorm, :factorize,
        :ishermitian, :issymmetric, :isposdef, :istriu, :istril,
        :lyap, :sylvester,
    ]),
    :statistics => Set{Symbol}([
        :mean, :median, :var, :std, :cov, :cor,
        :quantile, :percentile,
    ]),
)

# ============================================================================
# Valid Commands Registry
# ============================================================================

"""
    VALID_COMMANDS

Set of all valid GIAC command names (as Symbols). Populated at module initialization
from `list_commands()`.
"""
const VALID_COMMANDS = Set{Symbol}()

# ============================================================================
# Conflict Warning System (008-all-giac-commands, FR-010)
# ============================================================================

"""
    _warned_conflicts

Set of conflict commands (as Symbols) that have already been warned about in this session.
Each conflict is warned only once to avoid spam.
"""
const _warned_conflicts = Set{Symbol}()

"""
    _warn_conflict(cmd::Symbol) -> Bool

Warn the user when they use a GIAC command that conflicts with Julia.

This function is called by `giac_cmd` when a conflicting command is used.
Each conflict is warned only once per session to avoid spam.

Since feature 023-conflicts-multidispatch, non-keyword conflicts (like `zeros`,
`sin`, `det`) work with GiacExpr via multiple dispatch, so warnings are
suppressed for those. Only true keyword conflicts (`:if`, `:for`, etc.)
still trigger warnings since they cannot be used as function names.

# Arguments
- `cmd`: Command name (as Symbol) to check

# Returns
- `true` if a warning was issued (first use of a keyword conflict)
- `false` if no warning needed (not a conflict, already warned, or non-keyword conflict)

# Example (internal use)
```julia
_warn_conflict(:if)      # First call: warns, returns true (keyword conflict)
_warn_conflict(:if)      # Second call: no warning, returns false (already warned)
_warn_conflict(:zeros)   # No warning, returns false (works via multiple dispatch)
_warn_conflict(:factor)  # Not a conflict: returns false
```
"""
function _warn_conflict(cmd::Symbol)::Bool
    # Only warn for actual conflicts that haven't been warned yet
    if cmd in JULIA_CONFLICTS && cmd ∉ _warned_conflicts
        # Don't warn for non-keyword conflicts - they work with GiacExpr via multiple dispatch
        # (023-conflicts-multidispatch feature)
        # Only keywords (:if, :for, etc.) truly can't be used as function names
        if cmd ∉ CONFLICT_CATEGORIES[:keyword]
            return false
        end

        push!(_warned_conflicts, cmd)
        reason = conflict_reason(cmd)
        reason_text = isnothing(reason) ? "" : " ($reason)"
        @warn "GIAC command '$cmd' conflicts with Julia$reason_text. " *
              "Use invoke_cmd(:$cmd, args...) to call it."
        return true
    end
    return false
end

"""
    reset_conflict_warnings!()

Reset the conflict warning tracker, allowing warnings to be shown again.

This is primarily useful for testing.

# Example
```julia
giac_cmd(:eval, expr)  # Shows warning
giac_cmd(:eval, expr)  # No warning (already shown)
reset_conflict_warnings!()
giac_cmd(:eval, expr)  # Shows warning again
```
"""
function reset_conflict_warnings!()
    empty!(_warned_conflicts)
    return nothing
end

"""
    _init_command_registry()

Initialize the command registry at module load time.
Populates VALID_COMMANDS from list_commands() and builds CATEGORY_LOOKUP.
"""
function _init_command_registry()
    # Populate VALID_COMMANDS (convert Strings from list_commands() to Symbols)
    empty!(VALID_COMMANDS)
    for cmd in list_commands()
        if !isempty(cmd)
            push!(VALID_COMMANDS, Symbol(cmd))
        end
    end

    # Build reverse category lookup (commands are now Symbols)
    empty!(CATEGORY_LOOKUP)
    for (category, commands) in COMMAND_CATEGORIES
        for cmd in commands
            CATEGORY_LOOKUP[cmd] = category
        end
    end

    @debug "Command registry initialized with $(length(VALID_COMMANDS)) commands"
end

# ============================================================================
# Discovery Functions
# ============================================================================

"""
    search_commands(pattern::String) -> Vector{Symbol}

Search for commands matching a string prefix.

# Arguments
- `pattern::String`: Prefix to match

# Returns
- `Vector{Symbol}`: List of matching command names (as Symbols), sorted alphabetically

# Example
```julia
search_commands("sin")  # Returns [:sin, :sinc, :sincos, :sinh, ...]
```
"""
function search_commands(pattern::String)::Vector{Symbol}
    results = Symbol[]
    for cmd in VALID_COMMANDS
        if startswith(string(cmd), pattern)
            push!(results, cmd)
        end
    end
    return sort!(results, by=string)
end

"""
    search_commands(pattern::Regex) -> Vector{Symbol}

Search for commands matching a regular expression.

# Arguments
- `pattern::Regex`: Regular expression to match

# Returns
- `Vector{Symbol}`: List of matching command names (as Symbols), sorted alphabetically

# Example
```julia
search_commands(r"^a.*n\$")  # Returns commands starting with 'a' and ending with 'n'
```
"""
function search_commands(pattern::Regex)::Vector{Symbol}
    results = Symbol[]
    for cmd in VALID_COMMANDS
        if occursin(pattern, string(cmd))
            push!(results, cmd)
        end
    end
    return sort!(results, by=string)
end

"""
    list_categories() -> Vector{Symbol}

List all available command categories.

# Returns
- `Vector{Symbol}`: Category names, sorted alphabetically

# Example
```julia
cats = list_categories()
# [:algebra, :calculus, :combinatorics, :geometry, ...]
```
"""
function list_categories()::Vector{Symbol}
    return sort(collect(keys(COMMAND_CATEGORIES)))
end

"""
    commands_in_category(category::Symbol) -> Vector{Symbol}

Get all commands in a specific category.

# Arguments
- `category::Symbol`: Category name (e.g., `:trigonometry`, `:algebra`)

# Returns
- `Vector{Symbol}`: List of command names (as Symbols) in the category, sorted alphabetically

# Throws
- `ArgumentError`: If the category does not exist

# Example
```julia
trig = commands_in_category(:trigonometry)
# [:acos, :asin, :atan, :cos, :sin, :tan, ...]
```
"""
function commands_in_category(category::Symbol)::Vector{Symbol}
    if !haskey(COMMAND_CATEGORIES, category)
        valid_cats = join(sort(collect(keys(COMMAND_CATEGORIES))), ", ")
        throw(ArgumentError("Unknown category: $category. Valid categories: $valid_cats"))
    end
    return sort(copy(COMMAND_CATEGORIES[category]), by=string)
end

"""
    command_info(cmd::Symbol) -> Union{CommandInfo, Nothing}

Get metadata about a specific command.

# Arguments
- `cmd::Symbol`: Command name

# Returns
- `CommandInfo`: Metadata about the command
- `nothing`: If the command is not found

# Example
```julia
info = command_info(:factor)
if info !== nothing
    println(info.name)      # "factor"
    println(info.category)  # :algebra
end
```
"""
function command_info(cmd::Symbol)::Union{CommandInfo, Nothing}
    if cmd ∉ VALID_COMMANDS && !isempty(VALID_COMMANDS)
        return nothing
    end

    # Lookup category (using Symbol key)
    category = get(CATEGORY_LOOKUP, cmd, :other)

    # Get documentation from GIAC help system
    doc = giac_help(cmd)

    return CommandInfo(string(cmd), category, String[], doc)
end

"""
    giac_help(cmd::Union{Symbol, String}) -> String

Get GIAC help text for a command.

# Arguments
- `cmd`: Command name as Symbol or String

# Returns
- `String`: Help text from GIAC, or empty string if not found

# Example
```julia
help = giac_help(:factor)
println(help)  # "factor(Expr) - Factor a polynomial..."
```
"""
function giac_help(cmd::Union{Symbol, String})::String
    cmd_str = string(cmd)

    # Use giac_eval to get help
    try
        result = with_giac_lock() do
            giac_eval("help($cmd_str)")
        end
        raw_str = string(result)
        # Clean up the string: remove outer quotes and unescape
        return _clean_help_string(raw_str)
    catch
        return ""
    end
end

"""
    _clean_help_string(s::String) -> String

Clean up a GIAC help string by removing outer quotes and unescaping.
"""
function _clean_help_string(s::String)::String
    # Remove outer quotes if present
    if startswith(s, '"') && endswith(s, '"') && length(s) >= 2
        s = s[2:end-1]
    end
    # Unescape common escape sequences
    s = replace(s, "\\n" => "\n")
    s = replace(s, "\\\"" => "\"")
    s = replace(s, "\\\\" => "\\")
    return s
end

"""
    help(cmd::Union{Symbol, String}) -> HelpResult

Internal function to get formatted help for a GIAC command.

**Note**: This function is not exported. For interactive help, use Julia's
native help system: `?factor` after importing the command. For programmatic
access to raw help, use the exported `giac_help` function.

Returns a `HelpResult` struct containing parsed help information. The result
auto-displays formatted output in the REPL, and provides programmatic access
to individual fields.

# Arguments
- `cmd`: Command name as Symbol or String

# Returns
- `HelpResult`: Structured help information with fields:
  - `command`: Command name
  - `description`: Description text
  - `related`: Vector of related command names
  - `examples`: Vector of example expressions

# Example
```julia
using Giac
using Giac.Commands: factor

# Recommended: Use Julia's native help system
?factor

# For programmatic access (internal):
result = Giac.help(:factor)
result.description  # "Factorizes a polynomial."
result.examples     # ["factor(x^4-1)", "factor(x^4-4,sqrt(2))", ...]
```

# See also
- [`giac_help`](@ref): Returns raw help string (exported)
- [`HelpResult`](@ref): The return type
"""
function help(cmd::Union{Symbol, String})::HelpResult
    cmd_sym = cmd isa Symbol ? cmd : Symbol(cmd)
    cmd_str = string(cmd_sym)

    # Check if command exists in VALID_COMMANDS (005-nearest-command-suggestions)
    if !isempty(VALID_COMMANDS) && cmd_sym ∉ VALID_COMMANDS
        suggestions = suggest_commands(cmd_sym)
        suggestion_text = _format_suggestions(suggestions)
        return HelpResult(cmd_str, "[No help found for: $cmd_str.$suggestion_text]", String[], String[])
    end

    help_text = giac_help(cmd_sym)

    if isempty(help_text)
        # Get suggestions for unknown commands (005-nearest-command-suggestions)
        suggestions = suggest_commands(cmd_sym)
        suggestion_text = _format_suggestions(suggestions)
        return HelpResult(cmd_str, "[No help found for: $cmd_str.$suggestion_text]", String[], String[])
    end

    return _parse_help(help_text, cmd_str)
end

# ============================================================================
# Command Suggestions (005-nearest-command-suggestions)
# ============================================================================

"""
    _levenshtein(s1::String, s2::String) -> Int

Compute the Levenshtein edit distance between two strings.

The Levenshtein distance is the minimum number of single-character edits
(insertions, deletions, or substitutions) required to change one string
into the other.

Uses an optimized single-row dynamic programming approach with O(min(m,n)) space.

# Arguments
- `s1`: First string
- `s2`: Second string

# Returns
- `Int`: The edit distance (0 = identical, higher = more different)

# Examples
```julia
Giac._levenshtein("factor", "factor")   # 0 (identical)
Giac._levenshtein("factor", "factr")    # 1 (delete 'o')
Giac._levenshtein("sin", "cos")         # 2 (s→c, i→o)
```
"""
function _levenshtein(s1::String, s2::String)::Int
    m, n = length(s1), length(s2)

    # Ensure s1 is the shorter string for space optimization
    if m > n
        s1, s2, m, n = s2, s1, n, m
    end

    # Handle edge cases
    if m == 0
        return n
    end

    # Use single row with in-place updates
    # prev[j] represents the distance to transform s1[1:i-1] to s2[1:j-1]
    prev = collect(0:n)

    for i in 1:m
        curr = i  # Distance to transform s1[1:i] to empty string
        for j in 1:n
            cost = s1[i] != s2[j] ? 1 : 0
            # Minimum of: delete from s1, insert to s1, substitute
            temp = min(prev[j+1] + 1, curr + 1, prev[j] + cost)
            prev[j] = curr
            curr = temp
        end
        prev[n+1] = curr
    end

    return prev[n+1]
end

"""
    _max_threshold(input::String) -> Int

Compute the maximum edit distance threshold for a given input length.

Uses adaptive threshold: min(floor(length/2), 4)
- Short inputs (1-2 chars): max distance 1
- Medium inputs (3-4 chars): max distance 2
- Longer inputs: max distance up to 4

# Arguments
- `input`: The input string

# Returns
- `Int`: Maximum allowed edit distance
"""
function _max_threshold(input::String)::Int
    len = length(input)
    return min(len ÷ 2, 4)
end

"""
    get_suggestion_count() -> Int

Get the current default number of command suggestions.

# Returns
- `Int`: Current suggestion count (default: 4)

# Example
```julia
get_suggestion_count()  # 4 (default)
```

# See also
- [`set_suggestion_count`](@ref): Set the suggestion count
"""
function get_suggestion_count()::Int
    return _suggestion_count[]
end

"""
    set_suggestion_count(n::Int) -> Nothing

Set the default number of command suggestions.

# Arguments
- `n`: Number of suggestions (must be > 0, otherwise resets to default 4)

# Example
```julia
set_suggestion_count(6)
get_suggestion_count()  # 6

set_suggestion_count(-1)  # Invalid, resets to default
get_suggestion_count()  # 4
```

# See also
- [`get_suggestion_count`](@ref): Get the current count
"""
function set_suggestion_count(n::Int)::Nothing
    _suggestion_count[] = n > 0 ? n : DEFAULT_SUGGESTION_COUNT
    return nothing
end

"""
    suggest_commands_with_distances(input::Union{Symbol, String}; n::Int=get_suggestion_count()) -> Vector{Tuple{Symbol, Int}}

Find commands similar to the given input, including edit distances.

# Arguments
- `input`: The mistyped command name (Symbol or String)
- `n`: Maximum number of suggestions to return (default: `get_suggestion_count()`)

# Returns
- `Vector{Tuple{Symbol, Int}}`: Pairs of (command_name, edit_distance), sorted by
  distance (ascending), then alphabetically

# Example
```julia
suggest_commands_with_distances(:factr)
# [(:factor, 1), (:cfactor, 2), (:ifactor, 2), ...]

suggest_commands_with_distances("integrat", n=2)
# [(:integrate, 1), ...]
```

# See also
- [`suggest_commands`](@ref): Returns only command names (no distances)
"""
function suggest_commands_with_distances(input::Union{Symbol, String}; n::Int=get_suggestion_count())::Vector{Tuple{Symbol, Int}}
    input_str = lowercase(string(input))

    if isempty(input_str)
        return Tuple{Symbol, Int}[]
    end

    # If input is already a valid command, no suggestions needed
    input_sym = input isa Symbol ? input : Symbol(input)
    if input_sym in VALID_COMMANDS
        return Tuple{Symbol, Int}[]
    end

    threshold = _max_threshold(input_str)

    # Compute distances for all commands within threshold
    candidates = Tuple{Symbol, Int}[]
    for cmd in VALID_COMMANDS
        dist = _levenshtein(input_str, lowercase(string(cmd)))
        if dist > 0 && dist <= threshold  # Exclude exact matches (dist=0)
            push!(candidates, (cmd, dist))
        end
    end

    # Sort by (distance ASC, command ASC)
    sort!(candidates, by = x -> (x[2], string(x[1])))

    # Return top N
    return candidates[1:min(n, length(candidates))]
end

"""
    suggest_commands(input::Union{Symbol, String}; n::Int=get_suggestion_count()) -> Vector{Symbol}

Find commands similar to the given input using edit distance.

This function helps users recover from typos by suggesting valid GIAC commands
that are similar to the input.

# Arguments
- `input`: The mistyped command name (Symbol or String)
- `n`: Maximum number of suggestions to return (default: `get_suggestion_count()`)

# Returns
- `Vector{Symbol}`: Similar command names, sorted by edit distance (ascending),
  then alphabetically. Returns empty vector if no similar commands found.

# Example
```julia
suggest_commands(:factr)
# [:factor, :cfactor, :ifactor, ...]

suggest_commands("integrat", n=2)
# [:integrate, ...]

suggest_commands(:factor)  # Exact match
# []  (empty, no suggestions needed)
```

# See also
- `suggest_commands_with_distances`: Also returns edit distances (internal function)
- [`set_suggestion_count`](@ref): Configure default suggestion count
"""
function suggest_commands(input::Union{Symbol, String}; n::Int=get_suggestion_count())::Vector{Symbol}
    results = suggest_commands_with_distances(input; n=n)
    return [cmd for (cmd, _) in results]
end

"""
    _format_suggestions(suggestions::Vector{Symbol}) -> String

Format a list of suggestions for display in error messages.

# Arguments
- `suggestions`: Vector of command names (as Symbols) to suggest

# Returns
- `String`: Formatted suggestion text, e.g., "Did you mean: factor, ifactor, cfactor?"
  Returns empty string if no suggestions.
"""
function _format_suggestions(suggestions::Vector{Symbol})::String
    if isempty(suggestions)
        return ""
    end
    return " Did you mean: " * join(string.(suggestions), ", ") * "?"
end

# ============================================================================
# Description Search (006-search-command-description)
# ============================================================================

"""
    _score_help_match(query::String, help_result::HelpResult) -> Int

Calculate relevance score for a search match.

# Arguments
- `query`: Lowercase search query
- `help_result`: Parsed help result with description and examples

# Returns
- `2`: Query found in description
- `1`: Query found only in examples
- `0`: No match
"""
function _score_help_match(query::AbstractString, help_result::HelpResult)::Int
    try
        # Check description first (higher relevance)
        if occursin(query, lowercase(help_result.description))
            return 2
        end

        # Check examples (lower relevance)
        for example in help_result.examples
            if occursin(query, lowercase(example))
                return 1
            end
        end
    catch e
        # Help text from C++ may contain invalid UTF-8 bytes
        if e isa Base.InvalidCharError
            @warn "Invalid UTF-8 in help text for command '$(help_result.command)': $(e)"
            return 0
        end
        rethrow()
    end

    return 0
end

"""
    search_commands_by_description(query; n=20) -> Vector{Symbol}

Search for GIAC commands whose help text contains the given keyword.

Unlike `search_commands` which matches command names, this function searches
the description and example text of each command's help documentation.

# Arguments
- `query::Union{String, Symbol}`: Search term to find in help text
- `n::Int=20`: Maximum number of results to return

# Returns
- `Vector{Symbol}`: Matching command names (as Symbols), sorted by relevance

# Example
```julia
# Find commands related to factorization
search_commands_by_description("factor")
# Returns: [:factor, :ifactor, :cfactor, ...]

# Search for matrix operations
search_commands_by_description("matrix", n=10)
```

# See also
- [`search_commands`](@ref): Search by command name pattern
- [`giac_help`](@ref): Get raw help for a specific command
"""
function search_commands_by_description(query::Union{Symbol, String}; n::Int=DEFAULT_SEARCH_LIMIT)::Vector{Symbol}
    # Convert to lowercase string and trim (String() ensures no SubString)
    query_str = String(strip(lowercase(string(query))))

    # Handle empty/whitespace query
    if isempty(query_str)
        return Symbol[]
    end

    # Handle invalid n
    if n <= 0
        n = DEFAULT_SEARCH_LIMIT
    end

    # Return empty if no commands loaded
    if isempty(VALID_COMMANDS)
        return Symbol[]
    end

    # Commands to skip (operators, keywords that cause GIAC syntax errors)
    # These are valid in GIAC's command list but don't have help entries
    skip_commands = Set{Symbol}([
        # Operators (as Symbols)
        Symbol("*"), Symbol("+"), Symbol("-"), Symbol("/"), Symbol("^"),
        Symbol("%"), Symbol("<"), Symbol(">"), Symbol("="), Symbol("|"),
        Symbol("&"), Symbol("!"), Symbol("@"), Symbol("=="), Symbol("!="),
        Symbol("<="), Symbol(">="), Symbol("&&"), Symbol("||"), Symbol(":="),
        Symbol("+="), Symbol("-="), Symbol("*="), Symbol("/="), Symbol(".*"),
        Symbol("./"), Symbol(".^"), Symbol("&*"), Symbol("&^"), Symbol("%/"),
        Symbol("/%"), Symbol("=<"), Symbol("->"), Symbol("@@"),
        # Keywords (English)
        :if, :then, :else, :elif, :fi, :end, :end_if,
        :for, :from, :to, :by, :step, :do, :od, :end_for,
        :while, :until, :end_while,
        :in, :or, :and, :xor, :not, :mod, :div,
        :begin, :var, :local, :option, :default, :otherwise,
        :try, :catch, :union, :intersect, :minus,
        # Keywords (French)
        :de, :faire, :fpour, :fsi, :sinon, :alors, :jusque, :jusqua, :jusqu_a,
        :ftantque, :ffaire, :ffonction, :ffunction, :pas, :ou, :et,
        # Other problematic
        Symbol("{"), :EndDlog
    ])

    # Search all commands and score matches
    matches = Tuple{Symbol, Int}[]

    # Redirect stderr at file descriptor level to suppress C++ library errors
    if Sys.iswindows()
        old_stderr = ccall(:_dup, Cint, (Cint,), 2)
        devnull_fd = ccall(:_open, Cint, (Cstring, Cint), "NUL", 1)
        ccall(:_dup2, Cint, (Cint, Cint), devnull_fd, 2)
        ccall(:_close, Cint, (Cint,), devnull_fd)
    else
        old_stderr = ccall(:dup, Cint, (Cint,), 2)
        devnull_fd = ccall(:open, Cint, (Cstring, Cint), "/dev/null", 1)  # O_WRONLY = 1
        ccall(:dup2, Cint, (Cint, Cint), devnull_fd, 2)
        ccall(:close, Cint, (Cint,), devnull_fd)
    end

    try
        for cmd in VALID_COMMANDS
            # Skip operators and keywords
            if cmd in skip_commands
                continue
            end

            cmd_str = string(cmd)
            # Skip if doesn't start with a letter (likely an operator)
            if !isempty(cmd_str) && !isletter(first(cmd_str))
                continue
            end

            # Get help text
            help_text = try
                giac_help(cmd)
            catch
                ""
            end

            if isempty(help_text)
                continue
            end

            # Parse help and score
            help_result = _parse_help(help_text, cmd_str)
            score = _score_help_match(query_str, help_result)

            if score > 0
                push!(matches, (cmd, score))
            end
        end
    finally
        # Restore stderr
        if Sys.iswindows()
            ccall(:_dup2, Cint, (Cint, Cint), old_stderr, 2)
            ccall(:_close, Cint, (Cint,), old_stderr)
        else
            ccall(:dup2, Cint, (Cint, Cint), old_stderr, 2)
            ccall(:close, Cint, (Cint,), old_stderr)
        end
    end

    # Sort by (score DESC, command ASC)
    sort!(matches, by = x -> (-x[2], string(x[1])))

    # Return top n command names
    return [cmd for (cmd, _) in matches[1:min(n, length(matches))]]
end

# ============================================================================
# Command Validation and Export Helpers (008-all-giac-commands)
# ============================================================================

"""
    is_valid_command(name::Union{Symbol, String}) -> Bool

Check if a command name is a valid GIAC command.

# Arguments
- `name`: Command name as Symbol or String

# Returns
- `true` if the command exists in GIAC's command list
- `false` otherwise

# Example
```julia
is_valid_command(:factor)      # true
is_valid_command("integrate")  # true
is_valid_command(:notacommand) # false
```

# See also
- [`list_commands`](@ref): Get all command names
- [`suggest_commands`](@ref): Get suggestions for misspelled commands
"""
function is_valid_command(name::Union{Symbol, String})::Bool
    cmd = name isa Symbol ? name : Symbol(name)
    return cmd in VALID_COMMANDS
end

"""
    exportable_commands() -> Vector{Symbol}

Get a list of GIAC commands that can be safely exported without conflicting
with Julia keywords, builtins, or standard library functions.

This function filters the complete command list to include only commands that:
1. Start with an ASCII letter (a-z, A-Z)
2. Do not conflict with Julia (not in `JULIA_CONFLICTS`)

# Returns
- `Vector{Symbol}`: Sorted list of exportable command names (as Symbols)

# Example
```julia
cmds = exportable_commands()
length(cmds)        # ~2000+
:factor in cmds     # true
:eval in cmds       # false (conflicts with Julia)
:sin in cmds        # false (conflicts with Base.sin)
issorted(cmds, by=string)  # true
```

# See also
- [`available_commands`](@ref): All commands starting with ASCII letters
- [`JULIA_CONFLICTS`](@ref): Commands that conflict with Julia
"""
function exportable_commands()::Vector{Symbol}
    if isempty(VALID_COMMANDS)
        return Symbol[]
    end

    result = Symbol[]
    for cmd in VALID_COMMANDS
        cmd_str = string(cmd)
        # Must start with ASCII letter
        if isempty(cmd_str) || !isletter(first(cmd_str))
            continue
        end
        # Must be ASCII letter (filter non-ASCII starters like Greek)
        if !isascii(first(cmd_str))
            continue
        end
        # Must not conflict with Julia
        if cmd in JULIA_CONFLICTS
            continue
        end
        push!(result, cmd)
    end

    return sort!(result, by=string)
end

"""
    conflict_reason(cmd::Union{Symbol, String}) -> Union{Symbol, Nothing}

Get the reason why a GIAC command conflicts with Julia.

# Arguments
- `cmd`: Command name as Symbol or String

# Returns
- `:keyword` - Conflicts with Julia keyword (if, for, while, etc.)
- `:builtin` - Conflicts with Julia builtin function (eval, float, etc.)
- `:base_math` - Conflicts with Base math function (sin, cos, exp, etc.)
- `:linear_algebra` - Conflicts with LinearAlgebra (det, inv, trace, etc.)
- `:statistics` - Conflicts with Statistics (mean, median, var, etc.)
- `nothing` - No conflict

# Example
```julia
conflict_reason(:eval)    # :builtin
conflict_reason(:sin)     # :base_math
conflict_reason(:det)     # :linear_algebra
conflict_reason(:for)     # :keyword
conflict_reason(:factor)  # nothing
```

# See also
- [`JULIA_CONFLICTS`](@ref): Set of all conflicting commands
- [`exportable_commands`](@ref): Commands safe to export
"""
function conflict_reason(cmd::Union{Symbol, String})::Union{Symbol, Nothing}
    cmd_sym = cmd isa Symbol ? cmd : Symbol(cmd)

    # Check each category
    for (category, commands) in CONFLICT_CATEGORIES
        if cmd_sym in commands
            return category
        end
    end

    return nothing
end
